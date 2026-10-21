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

# Pushizo Flutter SDK

iOS, Android ve web için tek Dart API'si: push bildirimleri, in-app mesajlar, bildirim kutusu, kullanıcı/tag/alias,
e-posta ve SMS abonelikleri, kullanıcı tercihleri, canlı sohbet ve Live Activities (iOS).

Paket [`pushizo_flutter/`](pushizo_flutter) dizinindedir ve pub.dev'de `pushizo_flutter` adıyla yayımlanır.

## Kurulum

```bash
flutter pub add pushizo_flutter
```

```dart
import 'package:pushizo_flutter/pushizo_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Pushizo.initialize('app_…');
  await Pushizo.Notifications.requestPermission();
  runApp(const MyApp());
}
```

Platform hazırlığı (Firebase `google-services.json`, Xcode Push Notifications yeteneği, Notification Service
Extension) ve tüm API: [docs.pushizo.com/docs/sdk/flutter](https://docs.pushizo.com/docs/sdk/flutter).

## Yapı

| Dizin | İçerik |
|-------|--------|
| [`pushizo_flutter/lib`](pushizo_flutter/lib) | Dart API'si (eski sağlayıcı v5 ile uyumlu yüzey) |
| [`pushizo_flutter/android`](pushizo_flutter/android) | Android köprüsü ([pushizo-android](https://github.com/pushizo/pushizo-android) SDK'sını sarar) |
| [`pushizo_flutter/ios`](pushizo_flutter/ios) | iOS köprüsü ([pushizo-ios](https://github.com/pushizo/pushizo-ios) SDK'sını sarar) |
| [`pushizo_flutter/lib/src/web`](pushizo_flutter/lib/src) | Web: sayfadaki Pushizo Web SDK'sına köprü |

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
