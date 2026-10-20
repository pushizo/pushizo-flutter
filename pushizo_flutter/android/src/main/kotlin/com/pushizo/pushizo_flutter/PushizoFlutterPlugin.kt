package com.pushizo.pushizo_flutter

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.pushizo.sdk.Pushizo
import com.pushizo.sdk.HsCallback
import com.pushizo.sdk.HsChatEventAdapter
import com.pushizo.sdk.HsChatOpenListener
import com.pushizo.sdk.HsClickEvent
import com.pushizo.sdk.HsForegroundEvent
import com.pushizo.sdk.HsInAppClickEvent
import com.pushizo.sdk.HsInAppHandle
import com.pushizo.sdk.HsInAppLifecycleEvent
import com.pushizo.sdk.HsInAppLifecycleListener
import com.pushizo.sdk.HsInAppMessage
import com.pushizo.sdk.HsInAppRenderer
import com.pushizo.sdk.HsInboxItem
import com.pushizo.sdk.HsInboxPage
import com.pushizo.sdk.HsLog
import com.pushizo.sdk.HsMessageCategory
import com.pushizo.sdk.HsPreference
import com.pushizo.sdk.HsPreferenceInput
import com.pushizo.sdk.HsPreferencesResult
import com.pushizo.sdk.HsNotification
import com.pushizo.sdk.HsPushSubscriptionState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.UUID

/** Flutter → Android SDK köprüsü (MethodChannel + EventChannel). */
class PushizoFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null
    /** Sistem konum izni sonucunu bekleyen Dart çağrısı (`requestLocationPermission`); yalnızca ana iş parçacığında. */
    private var pendingLocationPermission: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())
    /** Dart tarafında `setForegroundWillDisplayHandler` kayıtlı mı. */
    @Volatile private var foregroundHandlerEnabled = false

    /**
     * Dart EventChannel dinleyicisi bağlanmadan gelen bildirim tıklamaları (soğuk başlangıç: yerel SDK tıklamayı
     * Dart `initialize` ile eklenen dinleyiciye hemen teslim eder, akış henüz dinlenmiyor olabilir). Yalnızca ana iş
     * parçacığında erişilir; dinleyici bağlanınca sırayla iletilir.
     */
    private val pendingClicks = ArrayList<Map<String, Any?>>()

    /** Dart gösterim kararını beklerken ertelenen ön plan olayları (Dart `display()` için); yalnızca ana iş parçacığında. */
    private val foregroundEvents = LinkedHashMap<String, HsForegroundEvent>()

    private val clickListener: (HsClickEvent) -> Unit = { e -> emitClick(mapOf("type" to "click", "notification" to e.notification.toMap(), "actionId" to e.actionId, "url" to e.url)) }
    private val foregroundListener: (HsForegroundEvent) -> Unit = { e ->
        emit(mapOf("type" to "foreground", "notification" to e.notification.toMap()))
        if (foregroundHandlerEnabled) askDartToDisplay(e)
    }

    /**
     * Gösterim kararı Dart işleyicisine sorulur: yerel gösterim önce ertelenir (preventDefault), Dart
     * `preventDefault()` çağırmadıysa veya çağrı başarısız olursa `display()` ile gösterilir. Engellenen olay
     * `eventId` ile saklanır; Dart sonradan `event.display()` çağırırsa (`displayForegroundNotification`) gösterilir.
     */
    private fun askDartToDisplay(e: HsForegroundEvent) {
        e.preventDefault()
        main.post {
            val eventId = UUID.randomUUID().toString()
            foregroundEvents[eventId] = e
            while (foregroundEvents.size > MAX_FOREGROUND_EVENTS) foregroundEvents.remove(foregroundEvents.keys.first())
            val args = mapOf("notification" to e.notification.toMap(), "eventId" to eventId)
            channel.invokeMethod("foregroundWillDisplay", args, object : MethodChannel.Result {
                override fun success(result: Any?) { if (result != true) displayNow() }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = displayNow()
                override fun notImplemented() = displayNow()
                private fun displayNow() {
                    foregroundEvents.remove(eventId)
                    e.display()
                }
            })
        }
    }
    private val subscriptionObserver: (HsPushSubscriptionState) -> Unit = { s -> emit(mapOf("type" to "subscription", "state" to s.toMap())) }

    /** Canlı sohbet olayları → Dart `Pushizo.Chat.events` (`type: chat`, `event`: message/typing/read/unread/…). */
    private val chatListener = HsChatEventAdapter { event, payload -> emit(mapOf("type" to "chat", "event" to event) + payload) }

    /** Sohbet bildirimine tıklama → Dart `Pushizo.Chat.openStream`; akış dinlenmiyorsa tıklamalar gibi bekletilir. */
    private val chatOpenListener = HsChatOpenListener { info -> emitClick(mapOf("type" to "chatOpen") + info.toMap()) }

    /** Yerel SDK izin gözlemcisi → Dart `permissionStream` / `addPermissionObserver`. */
    private val permissionObserver: (Boolean) -> Unit = { granted -> emit(mapOf("type" to "permission", "permission" to granted)) }

    private val inAppClickListener: (HsInAppClickEvent) -> Unit = { e ->
        emit(mapOf("type" to "inAppClick", "messageId" to e.messageId, "actionId" to e.actionId, "url" to e.url))
    }
    private val inAppLifecycleListener = object : HsInAppLifecycleListener {
        private fun send(event: String, e: HsInAppLifecycleEvent) = emit(mapOf("type" to "inAppLifecycle", "event" to event, "messageId" to e.message.id))
        override fun onWillDisplay(event: HsInAppLifecycleEvent) = send("willDisplay", event)
        override fun onDidDisplay(event: HsInAppLifecycleEvent) = send("didDisplay", event)
        override fun onWillDismiss(event: HsInAppLifecycleEvent) = send("willDismiss", event)
        override fun onDidDismiss(event: HsInAppLifecycleEvent) = send("didDismiss", event)
    }

    /**
     * In-app mesajları Dart (Flutter widget'ları) çizer; tetik, sıklık, olay ve aksiyonlar yerel SDK'dadır. HTML içerikli
     * mesajlar bu çizime gelmez: yerel SDK kendi yalıtılmış WebView'ında çizer (ADR-0027), köprü olayları yine dinleyicilere ulaşır.
     */
    private val inAppHandles = HashMap<String, HsInAppHandle>()
    private val inAppRenderer = object : HsInAppRenderer {
        override fun show(message: HsInAppMessage, handle: HsInAppHandle): Boolean {
            inAppHandles[message.id] = handle
            channel.invokeMethod("inAppShow", mapOf("json" to message.toJson()), object : MethodChannel.Result {
                override fun success(result: Any?) { if (result != true) failed() }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = failed()
                override fun notImplemented() = failed()
                // Dart gösteremedi (navigator yok / başka mesaj açık): mesaj kapatılmış sayılır, gösterim kaydedilmez.
                private fun failed() { inAppHandles.remove(message.id)?.closed() }
            })
            return true
        }

        override fun close(messageId: String) {
            if (inAppHandles.containsKey(messageId)) channel.invokeMethod("inAppClose", mapOf("messageId" to messageId))
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "pushizo_flutter")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "pushizo_flutter/events")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        Pushizo.Notifications.removeClickListener(clickListener)
        Pushizo.Notifications.removeForegroundLifecycleListener(foregroundListener)
        Pushizo.User.pushSubscription.removeObserver(subscriptionObserver)
        Pushizo.Notifications.removePermissionObserver(permissionObserver)
        Pushizo.InAppMessages.removeClickListener(inAppClickListener)
        Pushizo.InAppMessages.removeLifecycleListener(inAppLifecycleListener)
        Pushizo.InAppMessages.setRenderer(null)
        Pushizo.Chat.removeListener(chatListener)
        Pushizo.Chat.removeOpenListener(chatOpenListener)
        inAppHandles.values.toList().forEach { it.closed() }
        inAppHandles.clear()
        foregroundEvents.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    val ctx = context ?: return result.error("NO_CONTEXT", "context yok", null)
                    // Yerel SDK yapılandırmayı (appId, apiUrl, onay zorunluluğu) kalıcı saklar; uygulama kapalıyken gelen
                    // mesaj/tıklama/kapatma, Dart motoru başlamadan da bu yapılandırmayla işlenir (Pushizo.ensureInitialized).
                    Pushizo.initialize(
                        ctx,
                        call.argument<String>("appId")!!,
                        Pushizo.Options(
                            apiUrl = call.argument<String>("apiUrl") ?: "https://api.pushizo.com",
                            requiresPrivacyConsent = call.argument<Boolean>("requiresPrivacyConsent") ?: false,
                            logLevel = logLevel(call.argument<String>("logLevel")),
                        ),
                    )
                    Pushizo.Notifications.addClickListener(clickListener)
                    Pushizo.Notifications.addForegroundLifecycleListener(foregroundListener)
                    Pushizo.User.pushSubscription.addObserver(subscriptionObserver)
                    Pushizo.Notifications.addPermissionObserver(permissionObserver)
                    Pushizo.InAppMessages.addClickListener(inAppClickListener)
                    Pushizo.InAppMessages.addLifecycleListener(inAppLifecycleListener)
                    Pushizo.InAppMessages.setRenderer(inAppRenderer)
                    Pushizo.Chat.addListener(chatListener)
                    Pushizo.Chat.addOpenListener(chatOpenListener)
                    result.success(null)
                }
                "setConsentGiven" -> { Pushizo.setConsentGiven(call.argument<Boolean>("given") ?: false); result.success(null) }
                "login" -> {
                    Pushizo.login(call.argument<String>("externalId")!!, call.argument<String>("identityHash"), call.argument<String>("jwt"))
                    result.success(null)
                }
                // Boş belirteç → INVALID_ARGUMENT; giriş yoksa HS_ERROR (yerel SDK IllegalStateException).
                "updateUserJwt" -> { Pushizo.updateUserJwt(call.argument<String>("jwt").orEmpty()); result.success(null) }
                "logout" -> { Pushizo.logout(); result.success(null) }
                "addTags" -> { Pushizo.User.addTags(call.argument<Map<String, String>>("tags") ?: emptyMap()); result.success(null) }
                "removeTags" -> { Pushizo.User.removeTags(call.argument<List<String>>("keys") ?: emptyList()); result.success(null) }
                "getTags" -> result.success(Pushizo.User.getTags())
                "addAliases" -> { Pushizo.User.addAliases(call.argument<Map<String, String>>("aliases") ?: emptyMap()); result.success(null) }
                "removeAlias" -> { Pushizo.User.removeAlias(call.argument<String>("label")!!); result.success(null) }
                "setForegroundHandlerEnabled" -> { foregroundHandlerEnabled = call.argument<Boolean>("enabled") ?: false; result.success(null) }
                // Dart `PushizoForegroundEvent.display()`: ertelenen bildirim şimdi gösterilir (tek sefer; yerel SDK yineleneni yok sayar).
                "displayForegroundNotification" -> { call.argument<String>("eventId")?.let { foregroundEvents.remove(it) }?.display(); result.success(null) }
                "setLanguage" -> { Pushizo.User.setLanguage(call.argument<String>("code")!!); result.success(null) }
                "getExternalId" -> result.success(Pushizo.User.externalId)
                "getUserId" -> result.success(Pushizo.User.id)
                "getSubscriptionState" -> result.success(Pushizo.User.pushSubscription.state.toMap())
                "optIn" -> { Pushizo.User.pushSubscription.optIn(); result.success(null) }
                "optOut" -> { Pushizo.User.pushSubscription.optOut(); result.success(null) }
                "getPermission" -> result.success(Pushizo.Notifications.permission)
                "requestPermission" -> {
                    val act = activity
                    if (Pushizo.Notifications.permission || act == null) { result.success(Pushizo.Notifications.permission); return }
                    pendingPermission = result
                    Pushizo.Notifications.requestPermission(act)
                }
                // Bildirim tepsisi
                "clearAll" -> { Pushizo.Notifications.clearAll(); result.success(null) }
                // Android tepsi kimliği; yalnızca iOS kimliği (`identifier`) verildiyse Android'de etkisizdir.
                "removeNotification" -> { call.argument<Int>("id")?.let { Pushizo.Notifications.removeNotification(it) }; result.success(null) }
                "removeGroupedNotifications" -> { Pushizo.Notifications.removeGroupedNotifications(call.argument<String>("group")!!); result.success(null) }
                "sendEvent" -> {
                    Pushizo.Session.sendEvent(call.argument<String>("name")!!, call.argument<Map<String, Any?>>("properties") ?: emptyMap(), call.argument<Double>("value"))
                    result.success(null)
                }
                "setLogLevel" -> { Pushizo.Debug.setLogLevel(logLevel(call.argument<String>("level"))); result.success(null) }
                // E-posta / SMS (geçersiz adres → IllegalArgumentException → INVALID_ARGUMENT)
                "addEmail" -> { Pushizo.User.addEmail(call.argument<String>("email") ?: ""); result.success(null) }
                "removeEmail" -> { Pushizo.User.removeEmail(call.argument<String>("email") ?: ""); result.success(null) }
                "addSms" -> { Pushizo.User.addSms(call.argument<String>("phoneNumber") ?: ""); result.success(null) }
                "removeSms" -> { Pushizo.User.removeSms(call.argument<String>("phoneNumber") ?: ""); result.success(null) }
                // In-app
                "addTriggers" -> { Pushizo.InAppMessages.addTriggers(call.argument<Map<String, String>>("triggers") ?: emptyMap()); result.success(null) }
                "removeTriggers" -> { Pushizo.InAppMessages.removeTriggers(call.argument<List<String>>("keys") ?: emptyList()); result.success(null) }
                "clearTriggers" -> { Pushizo.InAppMessages.clearTriggers(); result.success(null) }
                "getTriggers" -> result.success(Pushizo.InAppMessages.getTriggers())
                "setScreen" -> { Pushizo.InAppMessages.setScreen(call.argument<String>("name")); result.success(null) }
                "setInAppPaused" -> { Pushizo.InAppMessages.paused = call.argument<Boolean>("paused") ?: false; result.success(null) }
                "getInAppPaused" -> result.success(Pushizo.InAppMessages.paused)
                "inAppDisplayed" -> { inAppHandle(call)?.displayed(); result.success(null) }
                "inAppButtonClicked" -> { inAppHandle(call)?.buttonClicked(call.argument<String>("buttonId") ?: ""); result.success(null) }
                "inAppDismissed" -> { inAppHandle(call)?.dismissed(); result.success(null) }
                "inAppClosed" -> { call.argument<String>("messageId")?.let { inAppHandles.remove(it) }?.closed(); result.success(null) }
                // Bildirim kutusu (sonuç arka plan iş parçacığından ana iş parçacığına taşınır)
                "inboxList" -> Pushizo.Inbox.list(call.argument<Int>("limit") ?: 50, call.argument<String>("cursor"), reply(result) { it.toMap() })
                "inboxMarkRead" -> Pushizo.Inbox.markRead(call.argument<String>("id")!!, reply(result) { it.toMap() })
                "inboxMarkAllRead" -> Pushizo.Inbox.markAllRead(reply(result) { it })
                "inboxArchive" -> Pushizo.Inbox.archive(call.argument<String>("id")!!, reply(result) { null })
                "inboxUnreadCount" -> Pushizo.Inbox.unreadCount(reply(result) { it })
                // Tercihler (ADR-0019 §4); kanıt ve istek yerel SDK'da
                "getPreferences" -> Pushizo.User.getPreferences(reply(result) { it.toMap() })
                "setPreferences" -> {
                    val inputs = (call.argument<List<Map<String, Any?>>>("preferences") ?: emptyList()).map {
                        HsPreferenceInput(it["category"] as? String ?: "", it["channel"] as? String, it["optedIn"] == true)
                    }
                    Pushizo.User.setPreferences(inputs, reply(result) { it.toMap() })
                }
                // Konum paylaşımı (v2 Faz 17b); gönderim, aralık ve rıza kuralları yerel SDK'dadır.
                "setLocationShared" -> { Pushizo.Location.setShared(call.argument<Boolean>("shared") ?: false); result.success(null) }
                "getLocationShared" -> result.success(Pushizo.Location.isShared)
                "requestLocationPermission" -> requestLocationPermission(call.argument<String>("rationale"), result)
                // Canlı sohbet (ADR-0040): kimlik, kuyruk, akış ve push yerel SDK'dadır.
                "chatStart" -> Pushizo.Chat.start(call.argument<String>("name"), call.argument<String>("email"), call.argument<String>("language"), reply(result) { it.toMap() })
                "chatGetConfig" -> Pushizo.Chat.getConfig(call.argument<String>("language"), reply(result) { it.toMap() })
                "chatGetConversation" -> Pushizo.Chat.getConversation(reply(result) { it.toMap() })
                "chatGetMessages" -> Pushizo.Chat.getMessages(
                    call.argument<Number>("afterSeq")?.toLong(), call.argument<Number>("beforeSeq")?.toLong(),
                    call.argument<Int>("limit") ?: 50, reply(result) { it.toMap() },
                )
                "chatSendMessage" -> Pushizo.Chat.sendMessage(call.argument<String>("text").orEmpty(), call.argument<String>("optionId"), reply(result) { it.toMap() })
                "chatSendAttachment" -> Pushizo.Chat.sendAttachment(
                    call.argument<ByteArray>("bytes") ?: ByteArray(0), call.argument<String>("fileName").orEmpty(),
                    call.argument<String>("mimeType").orEmpty(), call.argument<String>("text"), reply(result) { it.toMap() },
                )
                "chatMarkRead" -> Pushizo.Chat.markRead(call.argument<Number>("seq")?.toLong() ?: 0L, reply(result) { it })
                "chatRefreshUnreadCount" -> Pushizo.Chat.refreshUnreadCount(reply(result) { it })
                "chatGetUnreadCount" -> result.success(Pushizo.Chat.unreadCount)
                "chatLeaveOfflineMessage" -> Pushizo.Chat.leaveOfflineMessage(
                    call.argument<String>("email").orEmpty(), call.argument<String>("text").orEmpty(), call.argument<String>("name"), reply(result) { it.toMap() },
                )
                "chatSetTyping" -> { Pushizo.Chat.setTyping(call.argument<Boolean>("typing") ?: false); result.success(null) }
                "chatStartListening" -> { Pushizo.Chat.startListening(); result.success(null) }
                "chatStopListening" -> { Pushizo.Chat.stopListening(); result.success(null) }
                "chatAttachmentUrl" -> result.success(Pushizo.Chat.attachmentUrl(call.argument<String>("attachmentId").orEmpty(), call.argument<Boolean>("download") ?: false))
                "chatGetVisitorId" -> result.success(Pushizo.Chat.visitorId)
                // Live Activities yalnızca iOS'ta vardır (ADR-0024); Android'de sessizce başarılı dönülmez.
                "setupDefaultLiveActivity", "startDefaultLiveActivity" ->
                    result.error(LIVE_ACTIVITY_UNSUPPORTED_CODE, LIVE_ACTIVITY_UNSUPPORTED_MESSAGE, null)
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_ARGUMENT", e.message, null)
        } catch (e: Exception) {
            result.error("HS_ERROR", e.message, null)
        }
    }

    private fun inAppHandle(call: MethodCall): HsInAppHandle? = call.argument<String>("messageId")?.let { inAppHandles[it] }

    /** SDK geri çağrısını Flutter sonucuna çevirir (Flutter sonucu ana iş parçacığında ister). */
    private fun <T> reply(result: MethodChannel.Result, map: (T) -> Any?) = HsCallback<T> { r ->
        main.post {
            r.fold(
                onSuccess = { result.success(map(it)) },
                onFailure = { e ->
                    val code = when (e) {
                        is com.pushizo.sdk.HsApiException -> e.code
                        is IllegalStateException -> "NOT_READY"
                        is IllegalArgumentException -> "INVALID_ARGUMENT"
                        else -> "HS_ERROR"
                    }
                    result.error(code, e.message, null)
                },
            )
        }
    }

    /**
     * Konum izni: yerel SDK `requestPermission` sonucu bildirmediğinden akış köprüde yürütülür. İzin zaten varsa
     * `true`; manifest'te konum izni yoksa veya Activity yoksa `false`. Aksi hâlde SDK string kaynaklarıyla açıklama
     * diyaloğu gösterilir ("Şimdi değil"/iptal → `false`); "Devam" ile sistem izni `Pushizo.Location.PERMISSION_REQUEST_CODE`
     * koduyla istenir ve sonuç [onRequestPermissionsResult] içinde döner.
     */
    private fun requestLocationPermission(rationale: String?, result: MethodChannel.Result) {
        if (Pushizo.Location.permissionGranted) {
            Pushizo.Location.onPermissionResult()
            result.success(true)
            return
        }
        val act = activity ?: return result.success(false)
        val permissions = declaredLocationPermissions(act)
        if (permissions.isEmpty()) {
            HsLog.w("konum izni istenemedi: uygulama manifest'inde ACCESS_COARSE_LOCATION/ACCESS_FINE_LOCATION yok")
            result.success(false)
            return
        }
        if (pendingLocationPermission != null) {
            result.error("HS_ERROR", "Konum izni isteği zaten sürüyor", null)
            return
        }
        act.runOnUiThread {
            if (act.isFinishing || act.isDestroyed) {
                result.success(false)
                return@runOnUiThread
            }
            // Düğme işleyicisi diyalog kapanmadan önce çalışır; kapanış yalnızca "Devam" seçilmediyse false döndürür.
            var proceeded = false
            AlertDialog.Builder(act)
                .setTitle(com.pushizo.sdk.R.string.hs_location_rationale_title)
                .setMessage(rationale?.takeIf { it.isNotBlank() } ?: act.getString(com.pushizo.sdk.R.string.hs_location_rationale_message))
                .setPositiveButton(com.pushizo.sdk.R.string.hs_location_rationale_continue) { _, _ ->
                    proceeded = true
                    pendingLocationPermission = result
                    act.requestPermissions(permissions.toTypedArray(), Pushizo.Location.PERMISSION_REQUEST_CODE)
                }
                .setNegativeButton(com.pushizo.sdk.R.string.hs_location_rationale_not_now, null)
                .setOnDismissListener { if (!proceeded) result.success(false) }
                .show()
        }
    }

    /** Uygulama manifest'inde tanımlı konum izinleri (eklenti izin eklemez; arka plan konumu istenmez). */
    private fun declaredLocationPermissions(ctx: Context): List<String> {
        val pm = ctx.packageManager
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(ctx.packageName, PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(ctx.packageName, PackageManager.GET_PERMISSIONS)
        }
        val requested = info.requestedPermissions?.toSet() ?: emptySet()
        return LOCATION_PERMISSIONS.filter { it in requested }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == Pushizo.Location.PERMISSION_REQUEST_CODE) {
            Pushizo.Location.onPermissionResult()
            pendingLocationPermission?.success(Pushizo.Location.permissionGranted)
            pendingLocationPermission = null
            return true
        }
        if (requestCode != Pushizo.Notifications.PERMISSION_REQUEST_CODE) return false
        Pushizo.Notifications.onPermissionResult()
        pendingPermission?.success(Pushizo.Notifications.permission)
        pendingPermission = null
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (events == null || pendingClicks.isEmpty()) return
        val buffered = pendingClicks.toList()
        pendingClicks.clear()
        buffered.forEach { events.success(it) }
    }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity; activityBinding = binding; binding.addRequestPermissionsResultListener(this) }
    override fun onDetachedFromActivityForConfigChanges() { onDetachedFromActivity() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
    override fun onDetachedFromActivity() { activityBinding?.removeRequestPermissionsResultListener(this); activity = null; activityBinding = null }

    private fun emit(payload: Map<String, Any?>) { main.post { sink?.success(payload) } }

    /** Tıklama olayı: akış henüz dinlenmiyorsa kaybolmaması için dinleyici bağlanana kadar bekletilir. */
    private fun emitClick(payload: Map<String, Any?>) {
        main.post {
            val events = sink
            if (events != null) {
                events.success(payload)
            } else {
                if (pendingClicks.size >= MAX_PENDING_CLICKS) pendingClicks.removeAt(0)
                pendingClicks.add(payload)
            }
        }
    }

    private fun logLevel(name: String?): HsLog.Level = when (name) {
        "none" -> HsLog.Level.NONE
        "error" -> HsLog.Level.ERROR
        "info" -> HsLog.Level.INFO
        "debug" -> HsLog.Level.DEBUG
        else -> HsLog.Level.WARN
    }

    private fun HsNotification.toMap() = mapOf("title" to title, "body" to body, "url" to url, "deliveryId" to deliveryId, "messageId" to messageId, "data" to data, "androidNotificationId" to androidNotificationId)
    private fun HsInboxItem.toMap() = mapOf(
        "id" to id, "messageId" to messageId, "title" to title, "body" to body, "url" to url, "imageUrl" to imageUrl,
        "data" to data, "read" to read, "readAt" to readAt, "archivedAt" to archivedAt, "expiresAt" to expiresAt, "createdAt" to createdAt,
    )
    private fun HsInboxPage.toMap() = mapOf("items" to items.map { it.toMap() }, "unreadCount" to unreadCount, "nextCursor" to nextCursor, "hasMore" to hasMore)
    private fun HsPreference.toMap() = mapOf("category" to category, "channel" to channel, "optedIn" to optedIn, "explicit" to explicit, "source" to source, "updatedAt" to updatedAt)
    private fun HsMessageCategory.toMap() = mapOf("key" to key, "name" to name, "description" to description, "channels" to channels, "defaultOptedIn" to defaultOptedIn)
    private fun HsPreferencesResult.toMap() = mapOf("data" to preferences.map { it.toMap() }, "categories" to categories.map { it.toMap() })
    private fun HsPushSubscriptionState.toMap() = mapOf("id" to id, "token" to token, "optedIn" to optedIn, "permission" to permission)

    private companion object {
        const val MAX_PENDING_CLICKS = 20
        const val MAX_FOREGROUND_EVENTS = 32
        const val LIVE_ACTIVITY_UNSUPPORTED_CODE = "PLATFORM_NOT_SUPPORTED"
        const val LIVE_ACTIVITY_UNSUPPORTED_MESSAGE = "Live Activities yalnızca iOS'ta desteklenir"
        val LOCATION_PERMISSIONS = listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
    }
}
