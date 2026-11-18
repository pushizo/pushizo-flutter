## 0.3.0

- Android teslimat güçlendirme (ADR-0092): `Pushizo.Delivery.status()`, `shouldShowGuidance()`, `openSettings()`, `showGuidance()`; iOS ve web'de zararsız (`supported: false`).

- Yerel API eşitliği: profille `login`, `User.setProperty`, `User.emails` / `smsNumbers`, `User.setAdsPersonalizationConsent`, `User.getConsents`, `Ads.setAdvertisingId`, `FeatureFlags.changes` ve `Inbox.changes` gözlemcileri, `Session.sendEvent` için `eventId`, `Chat.show()` / `hide()` / `isPresented`, `Location.permissionGranted`, `backgroundPermissionGranted`, `requestBackgroundPermission()` / `requestAlwaysPermission()`, `isInitialized`.

- **Değişti:** `Notifications.setBadgeCount` ve `clearBadge` artık `Future<bool>` döndürür (önce `Future<void>`); Android'de rozet yerel SDK'ya bağlandı, `Notifications.badgeCount` eklendi.

- Web: rozet (App Badging), `Location.permissionGranted`, profille `login`, gözlemciler ve sohbet yardımcıları Web SDK'ya bağlandı.

- Yerel bağımlılıklar: Android `com.pushizo:pushizo-android` 0.3.0, iOS `Pushizo` ~> 0.3.

## 0.2.0

- Özellik bayrakları (ADR-0066): `FeatureFlags.refresh()`, `isEnabled(key, defaultValue:)`, `getValue(key, defaultValue:)`; değerler yerel SDK'da saklanır, okuma ağa çıkmaz. Web'de Web SDK `FeatureFlags` API'sine bağlanır.

- Gömülü yerleşimler (ADR-0068): `Placements.list(key, limit:)` (`PushizoInAppMessage` listesi; çizim uygulamanın), `reportImpression/reportClick/reportDismiss`; anahtar ve `limit` (1-10) Dart'ta doğrulanır (`ArgumentError`). Web'de Web SDK `Placements` API'sine bağlanır.

- Arka plan bölge izleme (ADR-0065): `Location.setGeofencingEnabled(bool)`, `isGeofencingEnabled` (varsayılan kapalı; izin ve manifest/Info.plist girdileri uygulamanın). Web'de etkisiz, durum `false`.

- Yerel bağımlılıklar: Android `com.pushizo:pushizo-android` 0.2.1, iOS `Pushizo` ~> 0.2. iOS'ta geçersiz girdi hataları (`HSError.invalidArgument`) Android ile aynı biçimde `INVALID_ARGUMENT` döner.

## 0.1.0

- Flutter web (ADR-0025): aynı Dart API'si sayfadaki Web SDK'ya köprülenir (`dart:js_interop`, Wasm uyumlu); `PushizoWebOptions` (service worker yolu/kapsamı); web'de karşılığı olmayan yöntemler `PLATFORM_NOT_SUPPORTED`.

- Konum (ADR-0025): `Location.requestPermission({rationale})`, `setShared(bool)`, `isShared`; yalnızca ön plan, kapatınca sunucudaki konum silinir.

- iOS Live Activities (ADR-0024): `LiveActivities.setupDefaultLiveActivity()` ve `startDefaultLiveActivity(activityId, attributes, contentState)` (genel `PushizoDefaultLiveActivityAttributes` türü); girdi Dart'ta doğrulanır (`ArgumentError`), yerel hatalar `PlatformException` (`PLATFORM_NOT_SUPPORTED`, `NOT_READY`, `INVALID_ARGUMENT`, `LIVE_ACTIVITY_FAILED`); Android'de `PLATFORM_NOT_SUPPORTED`.

- JWT ile kimlik doğrulama (ADR-0023 §9): `login(id, jwt: …)`, `updateUserJwt`; belirteç yerel SDK'da saklanır ve `Authorization: Bearer` başlığıyla gider, `logout` ile silinir.

- Soğuk başlangıç: yapılandırma yerelde kalıcı; uygulama kapalıyken received/opened/dismissed kaybolmaz, tıklamalar clickStream dinlenene kadar bekletilir. Ön plan olayında `display()`, `pushSubscription.token`, `InAppMessages.addClickListener/addLifecycleListener` (+ remove), iOS `removeNotificationByIdentifier`.

- Kullanıcı tercihleri (`User.getPreferences/setPreferences`), in-app `variantId` ve `pushPrompt`/`outcome` aksiyon türleri (Faz 12, ADR-0019).

- E-posta/SMS aboneliği (`User.addEmail/removeEmail/addSms/removeSms`), in-app mesajlar (`InAppMessages`: trigger, ekran, duraklatma, tıklama ve yaşam döngüsü akışları; Flutter widget'larıyla çizim) ve bildirim kutusu (`Inbox.list/markRead/markAllRead/archive/unreadCount`).

- İlk sürüm: initialize, consent, login/logout, tag/dil, push aboneliği (optIn/optOut/state/changes), izin isteme, tıklama ve ön plan akışları, olay gönderimi, log seviyesi.
