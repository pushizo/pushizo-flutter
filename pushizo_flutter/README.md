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

**Pushizo Flutter SDK** — One Dart API for iOS, Android and the web: push notifications, in-app messages, notification inbox, users, tags and aliases, email and SMS subscriptions, preferences, live chat and Live Activities (iOS). Wraps the native Pushizo Android and iOS SDKs.

> **Status:** Publishing to pub.dev is in progress; until then you can build from this repository.<br>
> **Durum:** pub.dev yayını hazırlanıyor; o zamana kadar bu depodan derleyerek kullanabilirsiniz.

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
`<script src="https://api.example.com/sdk-web/PushizoSDK.js"></script>` ekleyin. Web'de karşılığı olmayan yöntemler
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
if (!config.online) await Pushizo.Chat.leaveOfflineMessage(email: 'ali@example.com', text: 'Beni arayın');
```

Ziyaretçi kimliği, çevrimdışı kuyruk (aynı `client_message_id` ile yeniden deneme), canlı akış (SSE; koparsa üstel
geri çekilme + `after_seq` yoklaması) ve push ile gelen temsilci mesajları (`pushizo_chat`) yerel Android/iOS SDK'sındadır;
`start` sonrası login/logout ve push aboneliği değişince bağlama yerel SDK'da yenilenir, logout ziyaretçiyi sıfırlar.
Mesajlar `seq` ile sıralanır; ağ yokken gönderilen mesaj `pending` döner ve gönderilince olayla sunucu kopyası gelir.
Ayrıntı: [android rehberi](https://docs.pushizo.com/docs/sdk/android) / [ios rehberi](https://docs.pushizo.com/docs/sdk/ios) → "Canlı sohbet".
Flutter web'de sohbet Web SDK widget'ıyla sunulur; `Pushizo.Chat` yöntemleri `PLATFORM_NOT_SUPPORTED` döner.

## Konum

`Pushizo.Location.requestPermission()`, `setShared(bool)`, `isShared` — yalnızca ön planda, kullanıcı izniyle;
`setShared(false)` sunucudaki konumu siler. Android manifest ve iOS `NSLocationWhenInUseUsageDescription` gereksinimleri
[flutter rehberi](https://docs.pushizo.com/docs/sdk/flutter) → "Konum".

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
