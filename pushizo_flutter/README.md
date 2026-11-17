<!-- pushizo:header -->
<p align="center">
  <a href="https://pushizo.com"><img src="https://raw.githubusercontent.com/pushizo/.github/main/profile/assets/mark.svg" alt="Pushizo" width="56" height="56"></a>
</p>
<p align="center">
  <a href="https://docs.pushizo.com/docs/sdk/flutter"><img src="https://img.shields.io/badge/docs-docs.pushizo.com-5b4bdb" alt="Docs"></a>
  <a href="https://docs.pushizo.com/docs/api"><img src="https://img.shields.io/badge/API-reference-b44fc4" alt="API reference"></a>
  <a href="https://github.com/pushizo/pushizo-flutter/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-16130f" alt="License: MIT"></a>
</p>
<p align="center"><a href="#english">English</a> · <a href="#türkçe">Türkçe</a></p>

## English

**Pushizo Flutter SDK** — One Dart API for iOS, Android and the web: push notifications, in-app messages, embedded placements, feature flags, notification inbox, users, tags and aliases, email and SMS subscriptions, preferences, live chat and Live Activities (iOS). Wraps the native Pushizo Android and iOS SDKs.

```bash
flutter pub add pushizo_flutter
```

The detailed guide below is in Turkish; code samples are language-neutral. Full documentation:
[docs.pushizo.com/docs/sdk/flutter](https://docs.pushizo.com/docs/sdk/flutter) · API reference: [docs.pushizo.com/docs/api](https://docs.pushizo.com/docs/api).

## Türkçe
<!-- /pushizo:header -->

# pushizo_flutter

Pushizo Flutter SDK. Yerel [Android](https://github.com/pushizo/pushizo-android) ve
[iOS](https://github.com/pushizo/pushizo-ios) SDK'larını MethodChannel/EventChannel ile sarar.

```bash
flutter pub add pushizo_flutter
```

Adım adım kurulum, izinler, kanallar ve tüm API: [docs.pushizo.com/docs/sdk/flutter](https://docs.pushizo.com/docs/sdk/flutter).

## Web

Web'de aynı Dart API'si sayfaya yüklenen Web SDK'ya köprülenir: `web/index.html` içine Flutter betiğinden önce
`<script src="https://api.pushizo.com/sdk-web/PushizoSDK.js"></script>` ekleyin. Web'de karşılığı olmayan yöntemler
`PLATFORM_NOT_SUPPORTED` döner. Ayrıntılar: [flutter rehberi](https://docs.pushizo.com/docs/sdk/flutter) → "Flutter web".

## Canlı sohbet

```dart
await Pushizo.Chat.start(name: 'Ali');
final config = await Pushizo.Chat.getConfig();            // online, offlineMessage, ek sınırları
var messages = (await Pushizo.Chat.getMessages()).messages;
Pushizo.Chat.messageStream.listen((m) => messages = mergePushizoChatMessages(messages, [m]));
Pushizo.Chat.openStream.listen((e) => openChat(e.conversationId)); // sohbet bildirimine tıklama
await Pushizo.Chat.startListening();                     // ekran açıkken; ayrılınca stopListening()
await Pushizo.Chat.sendMessage('Merhaba');               // bot hızlı yanıtı: sendMessage(r.label, optionId: r.id)
await Pushizo.Chat.markRead(messages.last.seq);
if (!config.online) await Pushizo.Chat.leaveOfflineMessage(email: 'ali@pushizo.com', text: 'Beni arayın');
```

Ziyaretçi kimliği, çevrimdışı kuyruk (aynı `client_message_id` ile yeniden deneme), canlı akış (SSE; koparsa üstel
geri çekilme + `after_seq` yoklaması) ve push ile gelen temsilci mesajları (`pushizo_chat`) yerel Android/iOS SDK'sındadır;
`start` sonrası login/logout ve push aboneliği değişince bağlama yerel SDK'da yenilenir, logout ziyaretçiyi sıfırlar.
Mesajlar `seq` ile sıralanır; ağ yokken gönderilen mesaj `pending` döner ve gönderilince olayla sunucu kopyası gelir.
Ayrıntı: [android rehberi](https://docs.pushizo.com/docs/sdk/android) / [ios rehberi](https://docs.pushizo.com/docs/sdk/ios) → "Canlı sohbet".
Flutter web'de sohbet Web SDK widget'ıyla sunulur; `Pushizo.Chat` yöntemleri `PLATFORM_NOT_SUPPORTED` döner.

## Gömülü yerleşimler ve özellik bayrakları

```dart
final messages = await Pushizo.Placements.list('home_top', limit: 1); // çizim uygulamanın; anahtar ^[a-z][a-z0-9_.-]{0,63}$, limit 1-10
await Pushizo.Placements.reportImpression(messages.first);           // reportClick(m, buttonId), reportDismiss(m)

await Pushizo.FeatureFlags.refresh();                                  // oturum başında yerel SDK zaten yeniler
if (await Pushizo.FeatureFlags.isEnabled('new_checkout')) { /* … */ }
final limit = await Pushizo.FeatureFlags.getValue('cart_limit', defaultValue: 3); // String | num | bool | Map | List
```

Yerleşim listesi `PushizoInAppMessage` döndürür; rapor çağrıları son listeden gelen mesajla yapılır. Flutter web'de her iki
API sayfadaki Web SDK'ya iletilir. Ayrıntı: [flutter rehberi](https://docs.pushizo.com/docs/sdk/flutter) → "Gömülü yerleşimler", "Özellik bayrakları".

## Android teslimat güçlendirme

```dart
final status = await Pushizo.Delivery.status(); // supported, vendor, rom, risk, restricted, recommendedSettings
if (await Pushizo.Delivery.shouldShowGuidance()) {      // risk var ve diyalog son 14 günde gösterilmedi
  final opened = await Pushizo.Delivery.showGuidance(); // hazır diyalog (22 dil); kabul edilirse ayar ekranı açılır
}
await Pushizo.Delivery.openSettings(setting: PushizoDeliverySetting.autoStart); // kendi arayüzünüzden
```

Bazı Android üreticilerinde pil ve otomatik başlatma yöneticisi arka plandaki uygulamayı durdurur; `Pushizo.Delivery` kısıtları
okur ve kullanıcıyı ilgili ayar ekranına götürür. Yalnızca Android'de etkilidir: iOS'ta ve web'de `status()` `supported: false` ve
`risk: none` döner, `openSettings` ile `showGuidance` hiçbir şey yapmadan `false` döner. Ayrıntı:
[flutter rehberi](https://docs.pushizo.com/docs/sdk/flutter) → "Android teslimat güçlendirme".

## Kimlik profili, rıza, rozet ve konum izni

Yerel Android ve iOS SDK'larındaki kimlik, rıza, reklam kimliği, rozet ve konum izni çağrıları Flutter'da da vardır. Yalnızca tek platformda anlamı olan çağrı diğer platformlarda hata vermez; etkisiz kalır ya da `false` / boş liste döner.

```dart
// Profille giriş: geçersiz e-posta/telefon girişten önce reddedilir (INVALID_ARGUMENT)
await Pushizo.login('user_42', profile: const PushizoUserProfile(email: 'ali@pushizo.com', sms: '+905321234567', tags: {'plan': 'pro'}));
final emails = await Pushizo.User.emails;           // smsNumbers; web'de boş
final ready = await Pushizo.isInitialized;

// Reklam kişiselleştirme rızası ve reklam kimliği
await Pushizo.User.setAdsPersonalizationConsent(true);   // güncel tercih listesini döndürür
final consents = await Pushizo.User.getConsents();        // purpose, granted, source, updatedAt
await Pushizo.Ads.setAdvertisingId(advertisingId);        // GAID / IDFA; null kaydı siler

// Rozet (yalnızca iOS; Android ve web'de etkisiz)
await Pushizo.Notifications.setBadgeCount(3);
await Pushizo.Notifications.clearBadge();

// Konum izni durumu ve arka plan izni (bölge izleme için)
if (await Pushizo.Location.permissionGranted && !await Pushizo.Location.backgroundPermissionGranted) {
  final granted = await Pushizo.Location.requestBackgroundPermission(rationale: 'Mağazaya yaklaşınca haber veririz.');
  if (granted) await Pushizo.Location.setGeofencingEnabled(true);
}

final listening = await Pushizo.Chat.isListening;         // canlı sohbet akışı açık mı
await Pushizo.User.registerAdm(admRegistrationId);        // yalnızca Android (Fire OS)
```

`requestBackgroundPermission` Android'de açıklama diyaloğunu ve sistem iznini (Android 11 ve sonrasında Ayarlar ekranı), iOS'ta "her zaman" iznini ister; `requestAlwaysPermission()` aynı çağrının iOS adıdır. Android manifest'inde `ACCESS_BACKGROUND_LOCATION` yoksa `false` döner. Reklam kimliğini uygulama alır (SDK reklam kitaplığı ve ATT istemi içermez); kimlik yalnızca `ads_personalization` rızası olan kullanıcıda ve SHA-256 özetiyle kullanılır. Web'de rıza çağrıları Web SDK'ya gider; reklam kimliği, rozet, ADM ve konum izni çağrıları etkisizdir.

## Konum

`Pushizo.Location.requestPermission()`, `setShared(bool)`, `isShared` — yalnızca ön planda, kullanıcı izniyle;
`setShared(false)` sunucudaki konumu siler. Android manifest ve iOS `NSLocationWhenInUseUsageDescription` gereksinimleri
[flutter rehberi](https://docs.pushizo.com/docs/sdk/flutter) → "Konum".

Arka plan bölge izleme (varsayılan kapalı): `Pushizo.Location.setGeofencingEnabled(true)`, `isGeofencingEnabled`.
İzlemeyi açmak izin istemi açmaz; arka plan izni `Pushizo.Location.requestBackgroundPermission()` ile istenir,
manifest/Info.plist girdilerini uygulama ekler. Web'de etkisizdir.

## Live Activities (iOS)

```dart
await Pushizo.LiveActivities.setupDefaultLiveActivity();
await Pushizo.LiveActivities.startDefaultLiveActivity('order_42', {'title': 'Sipariş #42'}, {'status': 'Yolda', 'eta': 12});
```

Genel `PushizoDefaultLiveActivityAttributes` türü kullanılır: widget extension'da
`ActivityConfiguration(for: PushizoDefaultLiveActivityAttributes.self)`, Info.plist'te `NSSupportsLiveActivities = YES`,
dashboard/API'de tür adı tam olarak `PushizoDefaultLiveActivityAttributes`. Push-to-start iOS 17.2+, yerel başlatma
iOS 16.1+; Android'de `PlatformException` (`PLATFORM_NOT_SUPPORTED`). Ayrıntı: [flutter rehberi](https://docs.pushizo.com/docs/sdk/flutter) "Live Activities (iOS)".

<!-- pushizo:footer -->
---

## Support · Destek

- **Guide · Rehber:** [docs.pushizo.com/docs/sdk/flutter](https://docs.pushizo.com/docs/sdk/flutter)
- **API reference & OpenAPI · API referansı ve OpenAPI:** [docs.pushizo.com/docs/api](https://docs.pushizo.com/docs/api) ·
  [pushizo-openapi](https://github.com/pushizo/pushizo-openapi)
- **Bugs & ideas · Hata ve öneri:** [Issues](https://github.com/pushizo/pushizo-flutter/issues)
- **Security · Güvenlik:** please do not open public issues; email [security@pushizo.com](mailto:security@pushizo.com) ·
  herkese açık issue açmayın, bu adrese yazın.
- **Help · Destek:** [support@pushizo.com](mailto:support@pushizo.com)

This repository is mirrored automatically from the Pushizo main repository on every release. Please open an issue
instead of a pull request; fixes land in the main repository and ship with the next release.
Bu depo her sürümde Pushizo ana deposundan otomatik yansıtılır. Pull request yerine issue açın; düzeltmeler ana depoda
yapılır ve bir sonraki sürümle buraya gelir.

Released under the MIT License · MIT lisanslıdır — [LICENSE](https://github.com/pushizo/pushizo-flutter/blob/main/LICENSE).
<!-- /pushizo:footer -->
