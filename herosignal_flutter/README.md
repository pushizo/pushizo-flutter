# herosignal_flutter

HeroSignal Flutter SDK. Android (`sdk/android`) ve iOS (`sdk/ios`) yerel SDK'larını MethodChannel/EventChannel ile sarar.

Kurulum ve kullanım: `docs/sdk/flutter.md`. Örnek uygulama: `examples/flutter-app`.

## Live Activities (iOS)

```dart
await HeroSignal.LiveActivities.setupDefaultLiveActivity();
await HeroSignal.LiveActivities.startDefaultLiveActivity('order_42', {'title': 'Sipariş #42'}, {'status': 'Yolda', 'eta': 12});
```

Genel `HeroSignalDefaultLiveActivityAttributes` türü kullanılır: widget extension'da
`ActivityConfiguration(for: HeroSignalDefaultLiveActivityAttributes.self)`, Info.plist'te `NSSupportsLiveActivities = YES`,
dashboard/API'de tür adı tam olarak `HeroSignalDefaultLiveActivityAttributes`. Push-to-start iOS 17.2+, yerel başlatma
iOS 16.1+; Android'de `PlatformException` (`PLATFORM_NOT_SUPPORTED`). Ayrıntı: `docs/sdk/flutter.md` "Live Activities (iOS)".
