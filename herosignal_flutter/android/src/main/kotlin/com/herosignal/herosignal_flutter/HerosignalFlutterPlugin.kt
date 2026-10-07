package com.herosignal.herosignal_flutter

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.herosignal.sdk.HeroSignal
import com.herosignal.sdk.HsCallback
import com.herosignal.sdk.HsClickEvent
import com.herosignal.sdk.HsForegroundEvent
import com.herosignal.sdk.HsInAppClickEvent
import com.herosignal.sdk.HsInAppHandle
import com.herosignal.sdk.HsInAppLifecycleEvent
import com.herosignal.sdk.HsInAppLifecycleListener
import com.herosignal.sdk.HsInAppMessage
import com.herosignal.sdk.HsInAppRenderer
import com.herosignal.sdk.HsInboxItem
import com.herosignal.sdk.HsInboxPage
import com.herosignal.sdk.HsLog
import com.herosignal.sdk.HsNotification
import com.herosignal.sdk.HsPushSubscriptionState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Flutter → Android SDK köprüsü (MethodChannel + EventChannel). */
class HerosignalFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())
    /** Dart tarafında `setForegroundWillDisplayHandler` kayıtlı mı. */
    @Volatile private var foregroundHandlerEnabled = false

    private val clickListener: (HsClickEvent) -> Unit = { e -> emit(mapOf("type" to "click", "notification" to e.notification.toMap(), "actionId" to e.actionId, "url" to e.url)) }
    private val foregroundListener: (HsForegroundEvent) -> Unit = { e ->
        emit(mapOf("type" to "foreground", "notification" to e.notification.toMap()))
        if (foregroundHandlerEnabled) askDartToDisplay(e)
    }

    /**
     * Gösterim kararı Dart işleyicisine sorulur: yerel gösterim önce ertelenir (preventDefault), Dart
     * `preventDefault()` çağırmadıysa veya çağrı başarısız olursa `display()` ile gösterilir.
     */
    private fun askDartToDisplay(e: HsForegroundEvent) {
        e.preventDefault()
        main.post {
            channel.invokeMethod("foregroundWillDisplay", mapOf("notification" to e.notification.toMap()), object : MethodChannel.Result {
                override fun success(result: Any?) { if (result != true) e.display() }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { e.display() }
                override fun notImplemented() { e.display() }
            })
        }
    }
    private val subscriptionObserver: (HsPushSubscriptionState) -> Unit = { s -> emit(mapOf("type" to "subscription", "state" to s.toMap())) }

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

    /** In-app mesajları Dart (Flutter widget'ları) çizer; tetik, sıklık, olay ve aksiyonlar yerel SDK'dadır. */
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
        channel = MethodChannel(binding.binaryMessenger, "herosignal_flutter")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "herosignal_flutter/events")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        HeroSignal.Notifications.removeClickListener(clickListener)
        HeroSignal.Notifications.removeForegroundLifecycleListener(foregroundListener)
        HeroSignal.User.pushSubscription.removeObserver(subscriptionObserver)
        HeroSignal.InAppMessages.removeClickListener(inAppClickListener)
        HeroSignal.InAppMessages.removeLifecycleListener(inAppLifecycleListener)
        HeroSignal.InAppMessages.setRenderer(null)
        inAppHandles.values.toList().forEach { it.closed() }
        inAppHandles.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    val ctx = context ?: return result.error("NO_CONTEXT", "context yok", null)
                    HeroSignal.initialize(
                        ctx,
                        call.argument<String>("appId")!!,
                        HeroSignal.Options(
                            apiUrl = call.argument<String>("apiUrl") ?: "https://api.herosignal.dev",
                            requiresPrivacyConsent = call.argument<Boolean>("requiresPrivacyConsent") ?: false,
                            logLevel = logLevel(call.argument<String>("logLevel")),
                        ),
                    )
                    HeroSignal.Notifications.addClickListener(clickListener)
                    HeroSignal.Notifications.addForegroundLifecycleListener(foregroundListener)
                    HeroSignal.User.pushSubscription.addObserver(subscriptionObserver)
                    HeroSignal.InAppMessages.addClickListener(inAppClickListener)
                    HeroSignal.InAppMessages.addLifecycleListener(inAppLifecycleListener)
                    HeroSignal.InAppMessages.setRenderer(inAppRenderer)
                    result.success(null)
                }
                "setConsentGiven" -> { HeroSignal.setConsentGiven(call.argument<Boolean>("given") ?: false); result.success(null) }
                "login" -> { HeroSignal.login(call.argument<String>("externalId")!!, call.argument<String>("identityHash")); result.success(null) }
                "logout" -> { HeroSignal.logout(); result.success(null) }
                "addTags" -> { HeroSignal.User.addTags(call.argument<Map<String, String>>("tags") ?: emptyMap()); result.success(null) }
                "removeTags" -> { HeroSignal.User.removeTags(call.argument<List<String>>("keys") ?: emptyList()); result.success(null) }
                "getTags" -> result.success(HeroSignal.User.getTags())
                "addAliases" -> { HeroSignal.User.addAliases(call.argument<Map<String, String>>("aliases") ?: emptyMap()); result.success(null) }
                "removeAlias" -> { HeroSignal.User.removeAlias(call.argument<String>("label")!!); result.success(null) }
                "setForegroundHandlerEnabled" -> { foregroundHandlerEnabled = call.argument<Boolean>("enabled") ?: false; result.success(null) }
                "setLanguage" -> { HeroSignal.User.setLanguage(call.argument<String>("code")!!); result.success(null) }
                "getExternalId" -> result.success(HeroSignal.User.externalId)
                "getUserId" -> result.success(HeroSignal.User.id)
                "getSubscriptionState" -> result.success(HeroSignal.User.pushSubscription.state.toMap())
                "optIn" -> { HeroSignal.User.pushSubscription.optIn(); result.success(null) }
                "optOut" -> { HeroSignal.User.pushSubscription.optOut(); result.success(null) }
                "getPermission" -> result.success(HeroSignal.Notifications.permission)
                "requestPermission" -> {
                    val act = activity
                    if (HeroSignal.Notifications.permission || act == null) { result.success(HeroSignal.Notifications.permission); return }
                    pendingPermission = result
                    HeroSignal.Notifications.requestPermission(act)
                }
                "sendEvent" -> {
                    HeroSignal.Session.sendEvent(call.argument<String>("name")!!, call.argument<Map<String, Any?>>("properties") ?: emptyMap(), call.argument<Double>("value"))
                    result.success(null)
                }
                "setLogLevel" -> { HeroSignal.Debug.setLogLevel(logLevel(call.argument<String>("level"))); result.success(null) }
                // E-posta / SMS (geçersiz adres → IllegalArgumentException → INVALID_ARGUMENT)
                "addEmail" -> { HeroSignal.User.addEmail(call.argument<String>("email") ?: ""); result.success(null) }
                "removeEmail" -> { HeroSignal.User.removeEmail(call.argument<String>("email") ?: ""); result.success(null) }
                "addSms" -> { HeroSignal.User.addSms(call.argument<String>("phoneNumber") ?: ""); result.success(null) }
                "removeSms" -> { HeroSignal.User.removeSms(call.argument<String>("phoneNumber") ?: ""); result.success(null) }
                // In-app
                "addTriggers" -> { HeroSignal.InAppMessages.addTriggers(call.argument<Map<String, String>>("triggers") ?: emptyMap()); result.success(null) }
                "removeTriggers" -> { HeroSignal.InAppMessages.removeTriggers(call.argument<List<String>>("keys") ?: emptyList()); result.success(null) }
                "clearTriggers" -> { HeroSignal.InAppMessages.clearTriggers(); result.success(null) }
                "getTriggers" -> result.success(HeroSignal.InAppMessages.getTriggers())
                "setScreen" -> { HeroSignal.InAppMessages.setScreen(call.argument<String>("name")); result.success(null) }
                "setInAppPaused" -> { HeroSignal.InAppMessages.paused = call.argument<Boolean>("paused") ?: false; result.success(null) }
                "getInAppPaused" -> result.success(HeroSignal.InAppMessages.paused)
                "inAppDisplayed" -> { inAppHandle(call)?.displayed(); result.success(null) }
                "inAppButtonClicked" -> { inAppHandle(call)?.buttonClicked(call.argument<String>("buttonId") ?: ""); result.success(null) }
                "inAppDismissed" -> { inAppHandle(call)?.dismissed(); result.success(null) }
                "inAppClosed" -> { call.argument<String>("messageId")?.let { inAppHandles.remove(it) }?.closed(); result.success(null) }
                // Bildirim kutusu (sonuç arka plan iş parçacığından ana iş parçacığına taşınır)
                "inboxList" -> HeroSignal.Inbox.list(call.argument<Int>("limit") ?: 50, call.argument<String>("cursor"), reply(result) { it.toMap() })
                "inboxMarkRead" -> HeroSignal.Inbox.markRead(call.argument<String>("id")!!, reply(result) { it.toMap() })
                "inboxMarkAllRead" -> HeroSignal.Inbox.markAllRead(reply(result) { it })
                "inboxArchive" -> HeroSignal.Inbox.archive(call.argument<String>("id")!!, reply(result) { null })
                "inboxUnreadCount" -> HeroSignal.Inbox.unreadCount(reply(result) { it })
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
                        is com.herosignal.sdk.HsApiException -> e.code
                        is IllegalStateException -> "NOT_READY"
                        is IllegalArgumentException -> "INVALID_ARGUMENT"
                        else -> "HS_ERROR"
                    }
                    result.error(code, e.message, null)
                },
            )
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != HeroSignal.Notifications.PERMISSION_REQUEST_CODE) return false
        HeroSignal.Notifications.onPermissionResult()
        pendingPermission?.success(HeroSignal.Notifications.permission)
        pendingPermission = null
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity; activityBinding = binding; binding.addRequestPermissionsResultListener(this) }
    override fun onDetachedFromActivityForConfigChanges() { onDetachedFromActivity() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
    override fun onDetachedFromActivity() { activityBinding?.removeRequestPermissionsResultListener(this); activity = null; activityBinding = null }

    private fun emit(payload: Map<String, Any?>) { main.post { sink?.success(payload) } }

    private fun logLevel(name: String?): HsLog.Level = when (name) {
        "none" -> HsLog.Level.NONE
        "error" -> HsLog.Level.ERROR
        "info" -> HsLog.Level.INFO
        "debug" -> HsLog.Level.DEBUG
        else -> HsLog.Level.WARN
    }

    private fun HsNotification.toMap() = mapOf("title" to title, "body" to body, "url" to url, "deliveryId" to deliveryId, "messageId" to messageId, "data" to data)
    private fun HsInboxItem.toMap() = mapOf(
        "id" to id, "messageId" to messageId, "title" to title, "body" to body, "url" to url, "imageUrl" to imageUrl,
        "data" to data, "read" to read, "readAt" to readAt, "archivedAt" to archivedAt, "expiresAt" to expiresAt, "createdAt" to createdAt,
    )
    private fun HsInboxPage.toMap() = mapOf("items" to items.map { it.toMap() }, "unreadCount" to unreadCount, "nextCursor" to nextCursor, "hasMore" to hasMore)
    private fun HsPushSubscriptionState.toMap() = mapOf("id" to id, "token" to token, "optedIn" to optedIn, "permission" to permission)
}
