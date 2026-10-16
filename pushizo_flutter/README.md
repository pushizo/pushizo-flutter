# pushizo_flutter

Pushizo Flutter SDK. Android (`sdk/android`) ve iOS (`sdk/ios`) yerel SDK'larını MethodChannel/EventChannel ile sarar.

Kurulum ve kullanım: `docs/sdk/flutter.md`. Örnek uygulama: `examples/flutter-app`.

## Web

Web'de aynı Dart API'si sayfaya yüklenen Web SDK'ya köprülenir: `web/index.html` içine Flutter betiğinden önce
`<script src="https://api.example.com/sdk-web/PushizoSDK.js"></script>` ekleyin. Web'de karşılığı olmayan yöntemler
`PLATFORM_NOT_SUPPORTED` döner. Ayrıntılar: `docs/sdk/flutter.md` → "Flutter web".

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
