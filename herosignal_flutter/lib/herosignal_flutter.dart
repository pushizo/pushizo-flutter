/// HeroSignal Flutter SDK: Android/iOS yerel SDK'larını platform kanalı ile sarar.
///
/// ```dart
/// await HeroSignal.initialize('app_…', apiUrl: 'https://api.example.com');
/// await HeroSignal.Notifications.requestPermission();
/// await HeroSignal.login('user_42');
/// await HeroSignal.User.addTags({'plan': 'pro'});
/// HeroSignal.Notifications.clickStream.listen((e) => print(e.url));
/// HeroSignal.Notifications.setForegroundWillDisplayHandler((event) {
///   if (event.notification.data['silent_in_app'] == '1') event.preventDefault();
/// });
/// await HeroSignal.User.addEmail('ali@example.com');
/// await HeroSignal.InAppMessages.addTrigger('level', 'gold');
/// final page = await HeroSignal.Inbox.list(limit: 20);
/// ```
library;

// Statik ad alanları (User, Notifications…) eski sağlayıcı ile aynı API biçimini korur.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'src/in_app_view.dart';
part 'src/messaging_models.dart';
part 'src/models.dart';

/// Günlük seviyesi.
enum HeroSignalLogLevel { none, error, warn, info, debug }

class HeroSignal {
  HeroSignal._();

  static const MethodChannel _channel = MethodChannel('herosignal_flutter');
  static const EventChannel _events = EventChannel('herosignal_flutter/events');
  static Stream<Map<String, dynamic>>? _eventStream;

  static Stream<Map<String, dynamic>> get _rawEvents =>
      _eventStream ??= _events.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));

  /// Ön plan gösterim kararı veren Dart işleyicisi (yoksa yerel SDK bildirimi gösterir).
  static HeroSignalForegroundWillDisplayHandler? _foregroundHandler;

  /// In-app mesajların çizileceği navigator (verilmezse kök navigator aranır).
  static GlobalKey<NavigatorState>? _navigatorKey;

  static bool _handlerInstalled = false;

  /// Yerelden Dart'a çağrı işleyicisi bir kez kurulur (ön plan kararı, in-app çizimi).
  static void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Yerel taraftan Dart'a gelen çağrılar.
  static Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'foregroundWillDisplay':
        final handler = _foregroundHandler;
        if (handler == null) return false;
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final event = HeroSignalForegroundEvent(
            HeroSignalNotification.fromMap(Map<Object?, Object?>.from(args['notification'] as Map)));
        try {
          await handler(event);
        } catch (_) {
          // İşleyici hatası gösterimi engellemez; yerel SDK bildirimi gösterir.
          return false;
        }
        // true → gösterme (preventDefault çağrıldı).
        return event.prevented;
      case 'inAppShow':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final json = jsonDecode(args['json'] as String) as Map<String, dynamic>;
        return _InAppPresenter.instance.show(HeroSignalInAppMessage.fromMap(json));
      case 'inAppClose':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        _InAppPresenter.instance.close(args['messageId'] as String);
        return null;
      default:
        throw MissingPluginException('Bilinmeyen çağrı: ${call.method}');
    }
  }

  /// SDK'yı başlatır. [requiresPrivacyConsent] true ise [setConsentGiven] çağrılana kadar ağ çağrısı yapılmaz.
  static Future<void> initialize(
    String appId, {
    String apiUrl = 'https://api.herosignal.dev',
    bool requiresPrivacyConsent = false,
    HeroSignalLogLevel logLevel = HeroSignalLogLevel.warn,
  }) {
    _ensureHandler();
    return _channel.invokeMethod<void>('initialize', {
      'appId': appId,
      'apiUrl': apiUrl,
      'requiresPrivacyConsent': requiresPrivacyConsent,
      'logLevel': logLevel.name,
    });
  }

  static Future<void> setConsentGiven(bool given) => _channel.invokeMethod<void>('setConsentGiven', {'given': given});

  /// Anonim kullanıcıyı kimlikli kullanıcıya bağlar (gerekirse birleştirir).
  static Future<void> login(String externalId, {String? identityHash}) =>
      _channel.invokeMethod<void>('login', {'externalId': externalId, 'identityHash': identityHash});

  static Future<void> logout() => _channel.invokeMethod<void>('logout');

  static const User = _User();
  static const Notifications = _Notifications();
  static const InAppMessages = _InAppMessages();
  static const Inbox = _Inbox();
  static const Session = _Session();
  static const Debug = _Debug();
}

class _User {
  const _User();

  Future<void> addTag(String key, String value) => addTags({key: value});
  Future<void> addTags(Map<String, String> tags) => HeroSignal._channel.invokeMethod<void>('addTags', {'tags': tags});
  Future<void> removeTag(String key) => removeTags([key]);
  Future<void> removeTags(List<String> keys) => HeroSignal._channel.invokeMethod<void>('removeTags', {'keys': keys});
  Future<Map<String, String>> getTags() async {
    final result = await HeroSignal._channel.invokeMethod<Map<Object?, Object?>>('getTags');
    return result?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
  }

  Future<void> setLanguage(String code) => HeroSignal._channel.invokeMethod<void>('setLanguage', {'code': code});

  /// Kullanıcıya alias ekler (ör. `addAlias('crm_id', '42')`). Etiket: küçük harf, rakam, `_`.
  Future<void> addAlias(String label, String id) => addAliases({label: id});

  /// Birden çok alias'ı tek istekte ekler (en fazla 20; `external_id`/`hs_id` login/logout ile yönetilir).
  Future<void> addAliases(Map<String, String> aliases) =>
      HeroSignal._channel.invokeMethod<void>('addAliases', {'aliases': aliases});

  Future<void> removeAlias(String label) => HeroSignal._channel.invokeMethod<void>('removeAlias', {'label': label});
  /// E-posta aboneliği ekler (yerel SDK küçük harfe çevirir); geçersiz adreste [PlatformException] (`INVALID_ARGUMENT`).
  Future<void> addEmail(String email) => HeroSignal._channel.invokeMethod<void>('addEmail', {'email': email});

  /// E-posta aboneliğini siler.
  Future<void> removeEmail(String email) => HeroSignal._channel.invokeMethod<void>('removeEmail', {'email': email});

  /// SMS aboneliği ekler; numara E.164'e normalize edilir (`+90 (532) 123-45-67` → `+905321234567`).
  Future<void> addSms(String phoneNumber) => HeroSignal._channel.invokeMethod<void>('addSms', {'phoneNumber': phoneNumber});

  /// SMS aboneliğini siler.
  Future<void> removeSms(String phoneNumber) => HeroSignal._channel.invokeMethod<void>('removeSms', {'phoneNumber': phoneNumber});

  Future<String?> get externalId => HeroSignal._channel.invokeMethod<String>('getExternalId');
  Future<String?> get id => HeroSignal._channel.invokeMethod<String>('getUserId');

  _PushSubscription get pushSubscription => const _PushSubscription();
}

class _PushSubscription {
  const _PushSubscription();

  Future<HeroSignalPushSubscriptionState> get state async {
    final result = await HeroSignal._channel.invokeMethod<Map<Object?, Object?>>('getSubscriptionState');
    return HeroSignalPushSubscriptionState.fromMap(result ?? const {});
  }

  Future<String?> get id async => (await state).id;
  Future<bool> get optedIn async => (await state).optedIn;
  Future<void> optIn() => HeroSignal._channel.invokeMethod<void>('optIn');
  Future<void> optOut() => HeroSignal._channel.invokeMethod<void>('optOut');

  /// Abonelik durumu değişiklikleri (token/opt-in/izin).
  Stream<HeroSignalPushSubscriptionState> get changes => HeroSignal._rawEvents
      .where((e) => e['type'] == 'subscription')
      .map((e) => HeroSignalPushSubscriptionState.fromMap(Map<Object?, Object?>.from(e['state'] as Map)));
}

class _Notifications {
  const _Notifications();

  /// Sistem iznini ister; sonuç izin verildi mi.
  Future<bool> requestPermission() async => (await HeroSignal._channel.invokeMethod<bool>('requestPermission')) ?? false;

  Future<bool> get permission async => (await HeroSignal._channel.invokeMethod<bool>('getPermission')) ?? false;

  /// Bildirim/düğme tıklamaları.
  Stream<HeroSignalClickEvent> get clickStream =>
      HeroSignal._rawEvents.where((e) => e['type'] == 'click').map(HeroSignalClickEvent.fromMap);

  /// Ön planda gelen bildirimler (yalnızca bilgi; gösterim kararı için [setForegroundWillDisplayHandler]).
  Stream<HeroSignalNotification> get foregroundStream => HeroSignal._rawEvents
      .where((e) => e['type'] == 'foreground')
      .map((e) => HeroSignalNotification.fromMap(Map<Object?, Object?>.from(e['notification'] as Map)));

  /// Uygulama ön plandayken gelen bildirimin gösterilip gösterilmeyeceğine Dart'ta karar verir:
  /// işleyici `event.preventDefault()` çağırırsa bildirim gösterilmez. `null` işleyiciyi kaldırır.
  /// İşleyici asenkron olabilir (iOS'ta en fazla 25 sn beklenir).
  Future<void> setForegroundWillDisplayHandler(HeroSignalForegroundWillDisplayHandler? handler) {
    HeroSignal._foregroundHandler = handler;
    HeroSignal._ensureHandler();
    return HeroSignal._channel.invokeMethod<void>('setForegroundHandlerEnabled', {'enabled': handler != null});
  }
}

/// In-app mesajlar: liste, tetik değerlendirme, sıklık ve olay kaydı yerel SDK'dadır; mesaj Flutter widget'larıyla
/// (modal/tam ekran → rota, banner → overlay) çizilir.
class _InAppMessages {
  const _InAppMessages();

  Future<void> addTrigger(String key, String value) => addTriggers({key: value});
  Future<void> addTriggers(Map<String, String> triggers) =>
      HeroSignal._channel.invokeMethod<void>('addTriggers', {'triggers': triggers});
  Future<void> removeTrigger(String key) => removeTriggers([key]);
  Future<void> removeTriggers(List<String> keys) => HeroSignal._channel.invokeMethod<void>('removeTriggers', {'keys': keys});
  Future<void> clearTriggers() => HeroSignal._channel.invokeMethod<void>('clearTriggers');
  Future<Map<String, String>> getTriggers() async {
    final result = await HeroSignal._channel.invokeMethod<Map<Object?, Object?>>('getTriggers');
    return result?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
  }

  /// Geçerli ekran adı (`screen` tetikleri); ekrandan çıkarken `null`.
  Future<void> setScreen(String? name) => HeroSignal._channel.invokeMethod<void>('setScreen', {'name': name});

  /// true iken yeni mesaj gösterilmez.
  Future<void> setPaused(bool paused) => HeroSignal._channel.invokeMethod<void>('setInAppPaused', {'paused': paused});
  Future<bool> get paused async => (await HeroSignal._channel.invokeMethod<bool>('getInAppPaused')) ?? false;

  /// Mesajların çizileceği navigator; verilmezse uygulamanın kök navigator'ı kullanılır (MaterialApp `navigatorKey`).
  void setNavigatorKey(GlobalKey<NavigatorState>? key) {
    HeroSignal._navigatorKey = key;
    HeroSignal._ensureHandler();
  }

  /// Düğme tıklamaları (`messageId`, `actionId`, `url`).
  Stream<HeroSignalInAppClickEvent> get clickStream =>
      HeroSignal._rawEvents.where((e) => e['type'] == 'inAppClick').map(HeroSignalInAppClickEvent.fromMap);

  /// Yaşam döngüsü (willDisplay/didDisplay/willDismiss/didDismiss).
  Stream<HeroSignalInAppLifecycleEvent> get lifecycleStream => HeroSignal._rawEvents
      .where((e) => e['type'] == 'inAppLifecycle')
      .map(HeroSignalInAppLifecycleEvent.fromMap)
      .where((e) => e != null)
      .cast<HeroSignalInAppLifecycleEvent>();
}

/// Bildirim kutusu (`add_to_inbox` mesajları); login'de verilen `identityHash` yerel SDK tarafından eklenir.
class _Inbox {
  const _Inbox();

  /// Öğeler (yeniden eskiye), okunmamış sayısı ve sonraki sayfa imleci (`limit` 1-200).
  Future<HeroSignalInboxPage> list({int limit = 50, String? cursor}) async {
    final result = await HeroSignal._channel.invokeMethod<Map<Object?, Object?>>('inboxList', {'limit': limit, 'cursor': cursor});
    return HeroSignalInboxPage.fromMap(result ?? const {});
  }

  /// Okundu işaretler; güncel öğeyi döndürür.
  Future<HeroSignalInboxItem> markRead(String id) async {
    final result = await HeroSignal._channel.invokeMethod<Map<Object?, Object?>>('inboxMarkRead', {'id': id});
    return HeroSignalInboxItem.fromMap(result!);
  }

  /// Tümünü okundu işaretler; kalan okunmamış sayısını döndürür.
  Future<int> markAllRead() async => (await HeroSignal._channel.invokeMethod<int>('inboxMarkAllRead')) ?? 0;

  /// Öğeyi kutudan kaldırır (arşivler).
  Future<void> archive(String id) => HeroSignal._channel.invokeMethod<void>('inboxArchive', {'id': id});

  Future<int> unreadCount() async => (await HeroSignal._channel.invokeMethod<int>('inboxUnreadCount')) ?? 0;
}

class _Session {
  const _Session();

  Future<void> sendEvent(String name, {Map<String, Object?> properties = const {}, double? value}) =>
      HeroSignal._channel.invokeMethod<void>('sendEvent', {'name': name, 'properties': properties, 'value': value});
}

class _Debug {
  const _Debug();

  Future<void> setLogLevel(HeroSignalLogLevel level) => HeroSignal._channel.invokeMethod<void>('setLogLevel', {'level': level.name});
}
