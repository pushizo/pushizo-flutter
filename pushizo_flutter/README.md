# pushizo_flutter

Pushizo Flutter SDK. Android (`sdk/android`) ve iOS (`sdk/ios`) yerel SDK'larını MethodChannel/EventChannel ile sarar.

Kurulum ve kullanım: `docs/sdk/flutter.md`. Örnek uygulama: `examples/flutter-app`.

## Web

Web'de aynı Dart API'si sayfaya yüklenen Web SDK'ya köprülenir: `web/index.html` içine Flutter betiğinden önce
`<script src="https://api.example.com/sdk-web/PushizoSDK.js"></script>` ekleyin. Web'de karşılığı olmayan yöntemler
`PLATFORM_NOT_SUPPORTED` döner. Ayrıntılar: `docs/sdk/flutter.md` → "Flutter web".

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
Ayrıntı: `docs/sdk/android.md` / `docs/sdk/ios.md` → "Canlı sohbet" (ADR-0040).
Flutter web'de sohbet Web SDK widget'ıyla sunulur; `Pushizo.Chat` yöntemleri `PLATFORM_NOT_SUPPORTED` döner.

## Konum

`Pushizo.Location.requestPermission()`, `setShared(bool)`, `isShared` — yalnızca ön planda, kullanıcı izniyle;
`setShared(false)` sunucudaki konumu siler. Android manifest ve iOS `NSLocationWhenInUseUsageDescription` gereksinimleri
`docs/sdk/flutter.md` → "Konum".

## Live Activities (iOS)

```dart
await Pushizo.LiveActivities.setupDefaultLiveActivity();
await Pushizo.LiveActivities.startDefaultLiveActivity('order_42', {'title': 'Sipariş #42'}, {'status': 'Yolda', 'eta': 12});
```

Genel `PushizoDefaultLiveActivityAttributes` türü kullanılır: widget extension'da
`ActivityConfiguration(for: PushizoDefaultLiveActivityAttributes.self)`, Info.plist'te `NSSupportsLiveActivities = YES`,
dashboard/API'de tür adı tam olarak `PushizoDefaultLiveActivityAttributes`. Push-to-start iOS 17.2+, yerel başlatma
iOS 16.1+; Android'de `PlatformException` (`PLATFORM_NOT_SUPPORTED`). Ayrıntı: `docs/sdk/flutter.md` "Live Activities (iOS)".
