/// HeroSignal Flutter web eklentisi: `herosignal_flutter` MethodChannel çağrılarını ve `herosignal_flutter/events`
/// olay akışını sayfaya yüklenen Web SDK'ya (`window.HeroSignal`, `HeroSignalSDK.js`) bağlar. Dart genel API'si
/// (`HeroSignal.*`) Android/iOS ile aynıdır; web'de karşılığı olmayan yöntemler
/// `PlatformException(code: 'PLATFORM_NOT_SUPPORTED')` döndürür. Kayıt Flutter aracının ürettiği web eklenti kaydıyla
/// otomatik yapılır; uygulama kodunda içe aktarılması gerekmez.
library;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/web/js_web_sdk.dart';
import 'src/web/web_bridge.dart';

/// `pubspec.yaml` `flutter.plugin.platforms.web.pluginClass`.
class HerosignalFlutterWeb {
  HerosignalFlutterWeb._();

  static void registerWith(Registrar registrar) {
    final channel = MethodChannel('herosignal_flutter', const StandardMethodCodec(), registrar);
    // Web eklentisinden Dart'a çağrı (ön plan gösterim kararı) aynı kanalla, eklenti → çerçeve yönünde gider.
    final bridge = HeroSignalWebBridge(
      JsWebSdkFacade(),
      invokeDart: (method, arguments) => channel.invokeMethod<Object?>(method, arguments),
    );
    channel.setMethodCallHandler(bridge.handle);
    PluginEventChannel<Map<String, Object?>>('herosignal_flutter/events', const StandardMethodCodec(), registrar)
        .setController(bridge.eventController);
  }
}
