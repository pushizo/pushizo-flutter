## 0.1.0

- Flutter web (ADR-0025): aynı Dart API'si sayfadaki Web SDK'ya köprülenir (`dart:js_interop`, Wasm uyumlu); `PushizoWebOptions` (service worker yolu/kapsamı); web'de karşılığı olmayan yöntemler `PLATFORM_NOT_SUPPORTED`.

- Konum (ADR-0025): `Location.requestPermission({rationale})`, `setShared(bool)`, `isShared`; yalnızca ön plan, kapatınca sunucudaki konum silinir.

- iOS Live Activities (ADR-0024): `LiveActivities.setupDefaultLiveActivity()` ve `startDefaultLiveActivity(activityId, attributes, contentState)` (genel `PushizoDefaultLiveActivityAttributes` türü); girdi Dart'ta doğrulanır (`ArgumentError`), yerel hatalar `PlatformException` (`PLATFORM_NOT_SUPPORTED`, `NOT_READY`, `INVALID_ARGUMENT`, `LIVE_ACTIVITY_FAILED`); Android'de `PLATFORM_NOT_SUPPORTED`.

- JWT ile kimlik doğrulama (ADR-0023 §9): `login(id, jwt: …)`, `updateUserJwt`; belirteç yerel SDK'da saklanır ve `Authorization: Bearer` başlığıyla gider, `logout` ile silinir.

- Soğuk başlangıç: yapılandırma yerelde kalıcı; uygulama kapalıyken received/opened/dismissed kaybolmaz, tıklamalar clickStream dinlenene kadar bekletilir. Ön plan olayında `display()`, `pushSubscription.token`, `InAppMessages.addClickListener/addLifecycleListener` (+ remove), iOS `removeNotificationByIdentifier`.

- Kullanıcı tercihleri (`User.getPreferences/setPreferences`), in-app `variantId` ve `pushPrompt`/`outcome` aksiyon türleri (Faz 12, ADR-0019).

- E-posta/SMS aboneliği (`User.addEmail/removeEmail/addSms/removeSms`), in-app mesajlar (`InAppMessages`: trigger, ekran, duraklatma, tıklama ve yaşam döngüsü akışları; Flutter widget'larıyla çizim) ve bildirim kutusu (`Inbox.list/markRead/markAllRead/archive/unreadCount`).

- İlk sürüm: initialize, consent, login/logout, tag/dil, push aboneliği (optIn/optOut/state/changes), izin isteme, tıklama ve ön plan akışları, olay gönderimi, log seviyesi.
