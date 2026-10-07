import Flutter
import HeroSignal
// SPM: ayrı modül; CocoaPods alt spec'leri tek "HeroSignal" modülünde derlenir.
#if canImport(HeroSignalCore)
import HeroSignalCore
#endif
import UIKit
import UserNotifications

/// Flutter → iOS SDK köprüsü (MethodChannel + EventChannel). APNs token teslimi için UIApplicationDelegate olaylarına bağlanır.
public class HerosignalFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, HSInAppRenderer, HSInAppLifecycleListener {
    private var sink: FlutterEventSink?
    private let channel: FlutterMethodChannel
    private var listenersRegistered = false
    /// Dart tarafında `setForegroundWillDisplayHandler` kayıtlı mı.
    private var foregroundHandlerEnabled = false
    /// Dart'ın çizdiği in-app mesajların etkileşim kanalları (mesaj kimliğine göre).
    private var inAppHandles: [String: HSInAppHandle] = [:]

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "herosignal_flutter", binaryMessenger: registrar.messenger())
        let events = FlutterEventChannel(name: "herosignal_flutter/events", binaryMessenger: registrar.messenger())
        let instance = HerosignalFlutterPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        events.setStreamHandler(instance)
        registrar.addApplicationDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "initialize":
            guard let appId = args["appId"] as? String else { result(FlutterError(code: "ARGS", message: "appId gerekli", details: nil)); return }
            HeroSignal.initialize(appId) { options in
                options.apiUrl = args["apiUrl"] as? String ?? options.apiUrl
                options.requiresPrivacyConsent = args["requiresPrivacyConsent"] as? Bool ?? false
                options.logLevel = Self.logLevel(args["logLevel"] as? String)
            }
            // Dinleyiciler bir kez eklenir (initialize tekrar çağrılsa da olaylar çoğalmaz).
            if !listenersRegistered {
                listenersRegistered = true
                HeroSignal.Notifications.addClickListener { [weak self] e in
                    self?.emit(["type": "click", "notification": Self.map(e.notification), "actionId": e.actionId as Any, "url": e.url as Any])
                }
                HeroSignal.Notifications.addForegroundLifecycleListener { [weak self] e in
                    self?.emit(["type": "foreground", "notification": Self.map(e.notification)])
                    if self?.foregroundHandlerEnabled == true { self?.askDartToDisplay(e) }
                }
                HeroSignal.User.pushSubscription.addObserver { [weak self] s in
                    self?.emit(["type": "subscription", "state": Self.map(s)])
                }
                // Yerel SDK izin gözlemcisi → Dart `permissionStream` / `addPermissionObserver`.
                HeroSignal.Notifications.addPermissionObserver { [weak self] granted in
                    self?.emit(["type": "permission", "permission": granted])
                }
                HeroSignal.InAppMessages.addClickListener { [weak self] e in
                    self?.emit(["type": "inAppClick", "messageId": e.messageId, "actionId": e.actionId, "url": e.url as Any])
                }
                HeroSignal.InAppMessages.addLifecycleListener(self)
                // In-app mesajları Dart (Flutter widget'ları) çizer; tetik, sıklık, olay ve aksiyonlar yerel SDK'dadır.
                HeroSignal.InAppMessages.setRenderer(self)
            }
            result(nil)
        case "setConsentGiven": HeroSignal.setConsentGiven(args["given"] as? Bool ?? false); result(nil)
        case "login": HeroSignal.login(args["externalId"] as? String ?? "", identityHash: args["identityHash"] as? String); result(nil)
        case "logout": HeroSignal.logout(); result(nil)
        case "addTags": HeroSignal.User.addTags(args["tags"] as? [String: String] ?? [:]); result(nil)
        case "removeTags": HeroSignal.User.removeTags(args["keys"] as? [String] ?? []); result(nil)
        case "getTags": result(HeroSignal.User.getTags())
        case "addAliases": HeroSignal.User.addAliases(args["aliases"] as? [String: String] ?? [:]); result(nil)
        case "removeAlias": HeroSignal.User.removeAlias(args["label"] as? String ?? ""); result(nil)
        case "setForegroundHandlerEnabled": foregroundHandlerEnabled = args["enabled"] as? Bool ?? false; result(nil)
        case "setLanguage": HeroSignal.User.setLanguage(args["code"] as? String ?? "en"); result(nil)
        case "getExternalId": result(HeroSignal.User.externalId)
        case "getUserId": result(HeroSignal.User.id)
        case "getSubscriptionState":
            Task { let s = await HeroSignal.User.pushSubscription.state(); DispatchQueue.main.async { result(Self.map(s)) } }
        case "optIn": HeroSignal.User.pushSubscription.optIn(); result(nil)
        case "optOut": HeroSignal.User.pushSubscription.optOut(); result(nil)
        case "getPermission":
            Task { let p = await HeroSignal.Notifications.permission(); DispatchQueue.main.async { result(p == .authorized || p == .provisional) } }
        case "requestPermission":
            HeroSignal.Notifications.requestPermission { granted in DispatchQueue.main.async { result(granted) } }
        // Bildirim merkezi: tümünü temizle (rozet dahil) ve thread-id ile grup kaldırma. Tekil kaldırma Android
        // bildirim kimliği ister; iOS'ta karşılığı olmadığından çağrı etkisiz tamamlanır (eski sağlayıcı ile aynı).
        case "clearAll": HeroSignal.Notifications.clearAll(); result(nil)
        case "removeGroupedNotifications": HeroSignal.Notifications.removeGroupedNotifications(args["group"] as? String ?? ""); result(nil)
        case "removeNotification": result(nil)
        case "sendEvent":
            HeroSignal.Session.sendEvent(args["name"] as? String ?? "", properties: args["properties"] as? [String: Any] ?? [:], value: args["value"] as? Double)
            result(nil)
        case "setLogLevel": HeroSignal.Debug.setLogLevel(Self.logLevel(args["level"] as? String)); result(nil)
        // E-posta / SMS: geçersiz adres Dart'a INVALID_ARGUMENT olarak döner.
        case "addEmail", "removeEmail":
            let email = args["email"] as? String ?? ""
            guard HSContacts.normalizeEmail(email) != nil else { result(FlutterError(code: "INVALID_ARGUMENT", message: "Geçersiz e-posta adresi.", details: nil)); return }
            if call.method == "addEmail" { HeroSignal.User.addEmail(email) } else { HeroSignal.User.removeEmail(email) }
            result(nil)
        case "addSms", "removeSms":
            let phone = args["phoneNumber"] as? String ?? ""
            guard HSContacts.normalizePhone(phone) != nil else { result(FlutterError(code: "INVALID_ARGUMENT", message: "Geçersiz telefon numarası (E.164 bekleniyor).", details: nil)); return }
            if call.method == "addSms" { HeroSignal.User.addSms(phone) } else { HeroSignal.User.removeSms(phone) }
            result(nil)
        // In-app
        case "addTriggers": HeroSignal.InAppMessages.addTriggers(args["triggers"] as? [String: String] ?? [:]); result(nil)
        case "removeTriggers": HeroSignal.InAppMessages.removeTriggers(args["keys"] as? [String] ?? []); result(nil)
        case "clearTriggers": HeroSignal.InAppMessages.clearTriggers(); result(nil)
        case "getTriggers": result(HeroSignal.InAppMessages.getTriggers())
        case "setScreen": HeroSignal.InAppMessages.setScreen(args["name"] as? String); result(nil)
        case "setInAppPaused": HeroSignal.InAppMessages.paused = args["paused"] as? Bool ?? false; result(nil)
        case "getInAppPaused": result(HeroSignal.InAppMessages.paused)
        case "inAppDisplayed": inAppHandle(args)?.displayed(); result(nil)
        case "inAppButtonClicked": inAppHandle(args)?.buttonClicked(args["buttonId"] as? String ?? ""); result(nil)
        case "inAppDismissed": inAppHandle(args)?.dismissed(); result(nil)
        case "inAppClosed":
            if let id = args["messageId"] as? String { inAppHandles.removeValue(forKey: id)?.closed() }
            result(nil)
        // Bildirim kutusu
        case "inboxList":
            inbox(result) { try await Self.map(HeroSignal.Inbox.list(limit: args["limit"] as? Int ?? 50, cursor: args["cursor"] as? String)) }
        case "inboxMarkRead":
            inbox(result) { try await Self.map(HeroSignal.Inbox.markRead(args["id"] as? String ?? "")) }
        case "inboxMarkAllRead":
            inbox(result) { try await HeroSignal.Inbox.markAllRead() }
        case "inboxArchive":
            inbox(result) { try await HeroSignal.Inbox.archive(args["id"] as? String ?? ""); return nil }
        case "inboxUnreadCount":
            inbox(result) { try await HeroSignal.Inbox.unreadCount() }
        default: result(FlutterMethodNotImplemented)
        }
    }

    // MARK: APNs token → SDK

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        HeroSignal.setDeviceToken(deviceToken)
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        HeroSignal.setDeviceTokenError(error)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

    private func emit(_ payload: [String: Any]) { DispatchQueue.main.async { self.sink?(payload) } }

    /// Gösterim kararı Dart işleyicisine sorulur: önce ertelenir; Dart `preventDefault()` çağırmadıysa
    /// veya çağrı başarısız olursa `display()` ile gösterilir (yanıt gelmezse SDK 25 sn sonra kapatır).
    private func askDartToDisplay(_ event: HSForegroundEvent) {
        event.preventDefault()
        DispatchQueue.main.async {
            self.channel.invokeMethod("foregroundWillDisplay", arguments: ["notification": Self.map(event.notification)]) { result in
                if (result as? Bool) != true { event.display() }
            }
        }
    }

    // MARK: In-app (Dart çizimi)

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

    private static func millis(_ date: Date?) -> Any { date.map { Int64($0.timeIntervalSince1970 * 1000) } as Any }

    private static func map(_ item: HSInboxItem) -> [String: Any] {
        ["id": item.id, "messageId": item.messageId as Any, "title": item.title as Any, "body": item.body as Any,
         "url": item.url as Any, "imageUrl": item.imageUrl as Any, "data": item.data, "read": item.read,
         "readAt": millis(item.readAt), "archivedAt": millis(item.archivedAt), "expiresAt": millis(item.expiresAt), "createdAt": millis(item.createdAt)]
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
