import Flutter
import Pushizo
// SPM: ayrı modül; CocoaPods alt spec'leri tek "Pushizo" modülünde derlenir.
#if canImport(PushizoCore)
import PushizoCore
#endif
import UIKit
import UserNotifications

/// Flutter → iOS SDK köprüsü (MethodChannel + EventChannel). APNs token teslimi için UIApplicationDelegate olaylarına bağlanır.
public class PushizoFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, HSInAppRenderer, HSInAppLifecycleListener {
    private var sink: FlutterEventSink?
    private let channel: FlutterMethodChannel
    private var listenersRegistered = false
    /// Dart tarafında `setForegroundWillDisplayHandler` kayıtlı mı.
    private var foregroundHandlerEnabled = false
    /// Dart'ın çizdiği in-app mesajların etkileşim kanalları (mesaj kimliğine göre).
    private var inAppHandles: [String: HSInAppHandle] = [:]
    /// Dart EventChannel dinleyicisi bağlanmadan gelen bildirim tıklamaları (soğuk başlangıç); bağlanınca sırayla
    /// iletilir. Yalnızca ana kuyrukta erişilir.
    private var pendingClicks: [[String: Any]] = []
    private static let maxPendingClicks = 20
    /// Dart gösterim kararını beklerken ertelenen ön plan olayları (Dart `display()` için); yalnızca ana kuyrukta.
    private var foregroundEvents: [String: HSForegroundEvent] = [:]
    private var foregroundEventOrder: [String] = []
    private static let maxForegroundEvents = 32

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "pushizo_flutter", binaryMessenger: registrar.messenger())
        let events = FlutterEventChannel(name: "pushizo_flutter/events", binaryMessenger: registrar.messenger())
        let instance = PushizoFlutterPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        events.setStreamHandler(instance)
        registrar.addApplicationDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "initialize":
            guard let appId = args["appId"] as? String else { result(FlutterError(code: "ARGS", message: "appId gerekli", details: nil)); return }
            Pushizo.initialize(appId) { options in
                options.apiUrl = args["apiUrl"] as? String ?? options.apiUrl
                options.requiresPrivacyConsent = args["requiresPrivacyConsent"] as? Bool ?? false
                options.logLevel = Self.logLevel(args["logLevel"] as? String)
            }
            // Dinleyiciler bir kez eklenir (initialize tekrar çağrılsa da olaylar çoğalmaz).
            if !listenersRegistered {
                listenersRegistered = true
                Pushizo.Notifications.addClickListener { [weak self] e in
                    self?.emitClick(["type": "click", "notification": Self.map(e.notification), "actionId": e.actionId as Any, "url": e.url as Any])
                }
                Pushizo.Notifications.addForegroundLifecycleListener { [weak self] e in
                    self?.emit(["type": "foreground", "notification": Self.map(e.notification)])
                    if self?.foregroundHandlerEnabled == true { self?.askDartToDisplay(e) }
                }
                Pushizo.User.pushSubscription.addObserver { [weak self] s in
                    self?.emit(["type": "subscription", "state": Self.map(s)])
                }
                // Yerel SDK izin gözlemcisi → Dart `permissionStream` / `addPermissionObserver`.
                Pushizo.Notifications.addPermissionObserver { [weak self] granted in
                    self?.emit(["type": "permission", "permission": granted])
                }
                Pushizo.InAppMessages.addClickListener { [weak self] e in
                    self?.emit(["type": "inAppClick", "messageId": e.messageId, "actionId": e.actionId, "url": e.url as Any])
                }
                Pushizo.InAppMessages.addLifecycleListener(self)
                // In-app mesajları Dart (Flutter widget'ları) çizer; tetik, sıklık, olay ve aksiyonlar yerel SDK'dadır.
                Pushizo.InAppMessages.setRenderer(self)
            }
            result(nil)
        case "setConsentGiven": Pushizo.setConsentGiven(args["given"] as? Bool ?? false); result(nil)
        case "login":
            let identityHash = args["identityHash"] as? String
            let jwt = args["jwt"] as? String
            // Kanıt app'in kimlik doğrulama kipine uymuyorsa Dart'a hata döner (Android köprüsüyle aynı davranış).
            if let message = Pushizo.loginProofError(identityHash: identityHash, jwt: jwt) {
                result(FlutterError(code: "HS_ERROR", message: message, details: nil)); return
            }
            Pushizo.login(args["externalId"] as? String ?? "", identityHash: identityHash, jwt: jwt); result(nil)
        case "updateUserJwt":
            do {
                try Pushizo.updateUserJwt(args["jwt"] as? String ?? "")
                result(nil)
            } catch HSError.invalidArgument(let message) {
                result(FlutterError(code: "INVALID_ARGUMENT", message: message, details: nil))
            } catch {
                result(FlutterError(code: "HS_ERROR", message: "\(error)", details: nil))
            }
        case "logout": Pushizo.logout(); result(nil)
        case "addTags": Pushizo.User.addTags(args["tags"] as? [String: String] ?? [:]); result(nil)
        case "removeTags": Pushizo.User.removeTags(args["keys"] as? [String] ?? []); result(nil)
        case "getTags": result(Pushizo.User.getTags())
        case "addAliases": Pushizo.User.addAliases(args["aliases"] as? [String: String] ?? [:]); result(nil)
        case "removeAlias": Pushizo.User.removeAlias(args["label"] as? String ?? ""); result(nil)
        case "setForegroundHandlerEnabled": foregroundHandlerEnabled = args["enabled"] as? Bool ?? false; result(nil)
        // Dart `PushizoForegroundEvent.display()`: ertelenen bildirim şimdi gösterilir (SDK yineleneni yok sayar).
        case "displayForegroundNotification":
            if let id = args["eventId"] as? String { takeForegroundEvent(id)?.display() }
            result(nil)
        case "setLanguage": Pushizo.User.setLanguage(args["code"] as? String ?? "en"); result(nil)
        case "getExternalId": result(Pushizo.User.externalId)
        case "getUserId": result(Pushizo.User.id)
        case "getSubscriptionState":
            Task { let s = await Pushizo.User.pushSubscription.state(); DispatchQueue.main.async { result(Self.map(s)) } }
        case "optIn": Pushizo.User.pushSubscription.optIn(); result(nil)
        case "optOut": Pushizo.User.pushSubscription.optOut(); result(nil)
        case "getPermission":
            Task { let p = await Pushizo.Notifications.permission(); DispatchQueue.main.async { result(p == .authorized || p == .provisional) } }
        case "requestPermission":
            Pushizo.Notifications.requestPermission { granted in DispatchQueue.main.async { result(granted) } }
        // Bildirim merkezi: tümünü temizle (rozet dahil), thread-id ile grup kaldırma ve istek kimliğiyle
        // (`UNNotificationRequest.identifier`) tekil kaldırma. Yalnızca Android tepsi kimliği verildiyse iOS'ta karşılığı
        // olmadığından çağrı etkisiz tamamlanır.
        case "clearAll": Pushizo.Notifications.clearAll(); result(nil)
        case "removeGroupedNotifications": Pushizo.Notifications.removeGroupedNotifications(args["group"] as? String ?? ""); result(nil)
        case "removeNotification":
            if let identifier = args["identifier"] as? String, !identifier.isEmpty {
                Pushizo.Notifications.removeNotification(identifier: identifier)
            }
            result(nil)
        case "sendEvent":
            Pushizo.Session.sendEvent(args["name"] as? String ?? "", properties: args["properties"] as? [String: Any] ?? [:], value: args["value"] as? Double)
            result(nil)
        case "setLogLevel": Pushizo.Debug.setLogLevel(Self.logLevel(args["level"] as? String)); result(nil)
        // E-posta / SMS: geçersiz adres Dart'a INVALID_ARGUMENT olarak döner.
        case "addEmail", "removeEmail":
            let email = args["email"] as? String ?? ""
            guard HSContacts.normalizeEmail(email) != nil else { result(FlutterError(code: "INVALID_ARGUMENT", message: "Geçersiz e-posta adresi.", details: nil)); return }
            if call.method == "addEmail" { Pushizo.User.addEmail(email) } else { Pushizo.User.removeEmail(email) }
            result(nil)
        case "addSms", "removeSms":
            let phone = args["phoneNumber"] as? String ?? ""
            guard HSContacts.normalizePhone(phone) != nil else { result(FlutterError(code: "INVALID_ARGUMENT", message: "Geçersiz telefon numarası (E.164 bekleniyor).", details: nil)); return }
            if call.method == "addSms" { Pushizo.User.addSms(phone) } else { Pushizo.User.removeSms(phone) }
            result(nil)
        // In-app
        case "addTriggers": Pushizo.InAppMessages.addTriggers(args["triggers"] as? [String: String] ?? [:]); result(nil)
        case "removeTriggers": Pushizo.InAppMessages.removeTriggers(args["keys"] as? [String] ?? []); result(nil)
        case "clearTriggers": Pushizo.InAppMessages.clearTriggers(); result(nil)
        case "getTriggers": result(Pushizo.InAppMessages.getTriggers())
        case "setScreen": Pushizo.InAppMessages.setScreen(args["name"] as? String); result(nil)
        case "setInAppPaused": Pushizo.InAppMessages.paused = args["paused"] as? Bool ?? false; result(nil)
        case "getInAppPaused": result(Pushizo.InAppMessages.paused)
        case "inAppDisplayed": inAppHandle(args)?.displayed(); result(nil)
        case "inAppButtonClicked": inAppHandle(args)?.buttonClicked(args["buttonId"] as? String ?? ""); result(nil)
        case "inAppDismissed": inAppHandle(args)?.dismissed(); result(nil)
        case "inAppClosed":
            if let id = args["messageId"] as? String { inAppHandles.removeValue(forKey: id)?.closed() }
            result(nil)
        // Bildirim kutusu
        case "inboxList":
            inbox(result) { try await Self.map(Pushizo.Inbox.list(limit: args["limit"] as? Int ?? 50, cursor: args["cursor"] as? String)) }
        case "inboxMarkRead":
            inbox(result) { try await Self.map(Pushizo.Inbox.markRead(args["id"] as? String ?? "")) }
        case "inboxMarkAllRead":
            inbox(result) { try await Pushizo.Inbox.markAllRead() }
        case "inboxArchive":
            inbox(result) { try await Pushizo.Inbox.archive(args["id"] as? String ?? ""); return nil }
        case "inboxUnreadCount":
            inbox(result) { try await Pushizo.Inbox.unreadCount() }
        // Tercihler (ADR-0019 §4); kanıt ve istek yerel SDK'da
        case "getPreferences":
            inbox(result) { Self.map(try await Pushizo.User.getPreferences()) }
        case "setPreferences":
            let inputs = (args["preferences"] as? [[String: Any]] ?? []).map {
                HSPreferenceInput(category: $0["category"] as? String ?? "", channel: $0["channel"] as? String, optedIn: $0["optedIn"] as? Bool ?? false)
            }
            inbox(result) { Self.map(try await Pushizo.User.setPreferences(inputs)) }
        // Konum paylaşımı (v2 Faz 17b): açıklama uyarısı, When In Use izni ve gönderim kuralları yerel SDK'dadır.
        case "setLocationShared": Pushizo.Location.setShared(args["shared"] as? Bool ?? false); result(nil)
        case "getLocationShared": result(Pushizo.Location.isShared)
        case "requestLocationPermission":
            // Tamamlama ana iş parçacığında çağrılır; reddedilmiş/kısıtlı izin veya eksik Info.plist anahtarı → false.
            Pushizo.Location.requestPermission(rationale: args["rationale"] as? String) { granted in result(granted) }
        // Live Activities (ADR-0024): genel `PushizoDefaultLiveActivityAttributes` türü; değer doğrulaması yerel SDK'dadır.
        case "setupDefaultLiveActivity":
            liveActivity(result) { try Pushizo.LiveActivities.setupDefaultLiveActivity() }
        case "startDefaultLiveActivity":
            guard let activityId = args["activityId"] as? String, !activityId.isEmpty else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "activityId gerekli", details: nil)); return
            }
            guard let attributes = args["attributes"] as? [String: Any], let contentState = args["contentState"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "attributes ve contentState nesne olmalı", details: nil)); return
            }
            liveActivity(result) {
                try Pushizo.LiveActivities.startDefaultLiveActivity(activityId: activityId, attributes: attributes, contentState: contentState)
            }
        default: result(FlutterMethodNotImplemented)
        }
    }

    // MARK: APNs token → SDK

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Pushizo.setDeviceToken(deviceToken)
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Pushizo.setDeviceTokenError(error)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        let buffered = pendingClicks
        pendingClicks.removeAll()
        buffered.forEach { events($0) }
        return nil
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

    private func emit(_ payload: [String: Any]) { DispatchQueue.main.async { self.sink?(payload) } }

    /// Tıklama olayı: akış henüz dinlenmiyorsa (soğuk başlangıç) kaybolmaması için dinleyici bağlanana kadar bekletilir.
    private func emitClick(_ payload: [String: Any]) {
        DispatchQueue.main.async {
            if let sink = self.sink {
                sink(payload)
            } else {
                if self.pendingClicks.count >= Self.maxPendingClicks { self.pendingClicks.removeFirst() }
                self.pendingClicks.append(payload)
            }
        }
    }

    private func takeForegroundEvent(_ id: String) -> HSForegroundEvent? {
        foregroundEventOrder.removeAll { $0 == id }
        return foregroundEvents.removeValue(forKey: id)
    }

    /// Gösterim kararı Dart işleyicisine sorulur: önce ertelenir; Dart `preventDefault()` çağırmadıysa
    /// veya çağrı başarısız olursa `display()` ile gösterilir (yanıt gelmezse SDK 25 sn sonra kapatır). Engellenen olay
    /// `eventId` ile saklanır; Dart sonradan `event.display()` çağırırsa (`displayForegroundNotification`) gösterilir.
    private func askDartToDisplay(_ event: HSForegroundEvent) {
        event.preventDefault()
        DispatchQueue.main.async {
            let eventId = UUID().uuidString
            self.foregroundEvents[eventId] = event
            self.foregroundEventOrder.append(eventId)
            while self.foregroundEventOrder.count > Self.maxForegroundEvents {
                self.foregroundEvents.removeValue(forKey: self.foregroundEventOrder.removeFirst())
            }
            let args: [String: Any] = ["notification": Self.map(event.notification), "eventId": eventId]
            self.channel.invokeMethod("foregroundWillDisplay", arguments: args) { [weak self] result in
                if (result as? Bool) != true {
                    _ = self?.takeForegroundEvent(eventId)
                    event.display()
                }
            }
        }
    }

    // MARK: In-app (Dart çizimi)

    /// HTML içerikli mesajlar bu çizime gelmez: yerel SDK kendi yalıtılmış WKWebView'ında çizer (ADR-0027).
    public func show(_ message: HSInAppMessage, handle: HSInAppHandle) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: message.raw), let json = String(data: data, encoding: .utf8) else { return false }
        inAppHandles[message.id] = handle
        channel.invokeMethod("inAppShow", arguments: ["json": json]) { [weak self] result in
            // Dart gösteremedi (navigator yok / başka mesaj açık): mesaj kapatılmış sayılır, gösterim kaydedilmez.
            if (result as? Bool) != true { self?.inAppHandles.removeValue(forKey: message.id)?.closed() }
        }
        return true
    }

    public func close(messageId: String) {
        guard inAppHandles[messageId] != nil else { return }
        channel.invokeMethod("inAppClose", arguments: ["messageId": messageId])
    }

    public func onWillDisplay(_ message: HSInAppMessage) { emitLifecycle("willDisplay", message) }
    public func onDidDisplay(_ message: HSInAppMessage) { emitLifecycle("didDisplay", message) }
    public func onWillDismiss(_ message: HSInAppMessage) { emitLifecycle("willDismiss", message) }
    public func onDidDismiss(_ message: HSInAppMessage) { emitLifecycle("didDismiss", message) }

    private func emitLifecycle(_ event: String, _ message: HSInAppMessage) {
        emit(["type": "inAppLifecycle", "event": event, "messageId": message.id])
    }

    private func inAppHandle(_ args: [String: Any]) -> HSInAppHandle? {
        (args["messageId"] as? String).flatMap { inAppHandles[$0] }
    }

    /// Bildirim kutusu çağrısı: sonuç ana iş parçacığında döner; hata kodu `HSApiError.code` / `NOT_READY`.
    private func inbox(_ result: @escaping FlutterResult, _ body: @escaping () async throws -> Any?) {
        Task {
            do {
                let value = try await body()
                DispatchQueue.main.async { result(value) }
            } catch let error as HSApiError {
                DispatchQueue.main.async { result(FlutterError(code: error.code, message: error.message, details: nil)) }
            } catch {
                DispatchQueue.main.async { result(FlutterError(code: "NOT_READY", message: "\(error)", details: nil)) }
            }
        }
    }

    /// Live Activity çağrısı: `HSLiveActivityError` kodu ve mesajı aynen iletilir; beklenmeyen hata `LIVE_ACTIVITY_FAILED`.
    private func liveActivity(_ result: FlutterResult, _ body: () throws -> Void) {
        do {
            try body()
            result(nil)
        } catch let error as HSLiveActivityError {
            result(FlutterError(code: error.code, message: error.message, details: nil))
        } catch {
            result(FlutterError(code: "LIVE_ACTIVITY_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private static func millis(_ date: Date?) -> Any { date.map { Int64($0.timeIntervalSince1970 * 1000) } as Any }

    private static func map(_ item: HSInboxItem) -> [String: Any] {
        ["id": item.id, "messageId": item.messageId as Any, "title": item.title as Any, "body": item.body as Any,
         "url": item.url as Any, "imageUrl": item.imageUrl as Any, "data": item.data, "read": item.read,
         "readAt": millis(item.readAt), "archivedAt": millis(item.archivedAt), "expiresAt": millis(item.expiresAt), "createdAt": millis(item.createdAt)]
    }

    private static func map(_ p: HSPreference) -> [String: Any] {
        ["category": p.category, "channel": p.channel as Any, "optedIn": p.optedIn, "explicit": p.explicit, "source": p.source as Any, "updatedAt": millis(p.updatedAt)]
    }

    private static func map(_ c: HSMessageCategory) -> [String: Any] {
        ["key": c.key, "name": c.name, "description": c.description, "channels": c.channels as Any, "defaultOptedIn": c.defaultOptedIn]
    }

    private static func map(_ r: HSPreferencesResult) -> [String: Any] {
        ["data": r.preferences.map { map($0) }, "categories": r.categories.map { map($0) }]
    }

    private static func map(_ page: HSInboxPage) -> [String: Any] {
        ["items": page.items.map { map($0) }, "unreadCount": page.unreadCount, "nextCursor": page.nextCursor as Any, "hasMore": page.hasMore]
    }

    private static func logLevel(_ name: String?) -> HSLog.Level {
        switch name { case "none": return HSLog.Level.none; case "error": return .error; case "info": return .info; case "debug": return .debug; default: return .warn }
    }

    private static func map(_ n: HSNotification) -> [String: Any] {
        ["title": n.title as Any, "body": n.body as Any, "url": n.url as Any, "deliveryId": n.deliveryId as Any, "messageId": n.messageId as Any, "data": n.data]
    }

    private static func map(_ s: HSPushSubscriptionState) -> [String: Any] {
        ["id": s.id as Any, "token": s.token as Any, "optedIn": s.optedIn, "permission": s.permission == .authorized || s.permission == .provisional]
    }
}
