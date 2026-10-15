/// HeroSignal Flutter SDK: Android/iOS yerel SDK'larını platform kanalı ile sarar.
///
/// ```dart
/// await HeroSignal.initialize('app_…', apiUrl: 'https://api.example.com');
/// await HeroSignal.Notifications.requestPermission();
/// await HeroSignal.login('user_42');
/// await HeroSignal.login('user_42', jwt: jwtFromYourServer); // identity verification `jwt`/`both`
/// await HeroSignal.User.addTags({'plan': 'pro'});
/// HeroSignal.Notifications.clickStream.listen((e) => print(e.url));
/// HeroSignal.Notifications.addPermissionObserver((granted) => print('izin: $granted'));
/// HeroSignal.Notifications.setForegroundWillDisplayHandler((event) {
///   if (event.notification.data['silent_in_app'] == '1') event.preventDefault();
/// });
/// await HeroSignal.User.addEmail('ali@example.com');
/// final prefs = await HeroSignal.User.getPreferences();
/// await HeroSignal.InAppMessages.addTrigger('level', 'gold');
/// final page = await HeroSignal.Inbox.list(limit: 20);
/// await HeroSignal.LiveActivities.setupDefaultLiveActivity(); // yalnızca iOS
/// if (await HeroSignal.Location.requestPermission()) await HeroSignal.Location.setShared(true);
/// ```
///
/// Flutter web'de çağrılar sayfaya yüklenen Web SDK'ya (`window.HeroSignal`) iletilir; web'de karşılığı olmayan
/// yöntemler `PlatformException(code: 'PLATFORM_NOT_SUPPORTED')` döndürür (bkz. `docs/sdk/flutter.md` "Flutter web").
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

  static Stream<Map<String, dynamic>> get _rawEvents {
    final existing = _eventStream;
    if (existing != null) return existing;
    final stream = _events.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));
    _eventStream = stream;
    // Tıklamalar ayrı, bekletmeli akıştan dağıtılır: olay akışı başka bir dinleyiciyle (ör. permissionStream) açıldığında
    // gelen tıklama, `clickStream` henüz dinlenmiyorsa kaybolmaz (soğuk başlangıç).
    stream.where((e) => e['type'] == 'click').listen((e) {
      final click = HeroSignalClickEvent.fromMap(e);
      if (_clicks.hasListener) {
        _clicks.add(click);
      } else {
        if (_pendingClicks.length >= _maxPendingClicks) _pendingClicks.removeAt(0);
        _pendingClicks.add(click);
      }
    });
    return stream;
  }

  /// Bildirim tıklamaları; ilk dinleyici bağlanınca bekleyenler sırayla iletilir.
  static final StreamController<HeroSignalClickEvent> _clicks = StreamController<HeroSignalClickEvent>.broadcast(
    onListen: () {
      final pending = List<HeroSignalClickEvent>.of(_pendingClicks);
      _pendingClicks.clear();
      pending.forEach(_clicks.add);
    },
  );
  static final List<HeroSignalClickEvent> _pendingClicks = [];
  static const int _maxPendingClicks = 20;

  /// [_InAppMessages.addClickListener] / [_InAppMessages.addLifecycleListener] ile eklenen dinleyicilerin abonelikleri.
  static final Map<HeroSignalInAppClickListener, StreamSubscription<HeroSignalInAppClickEvent>> _inAppClickListeners = {};
  static final Map<HeroSignalInAppLifecycleListener, StreamSubscription<HeroSignalInAppLifecycleEvent>>
      _inAppLifecycleListeners = {};

  /// Ön plan gösterim kararı veren Dart işleyicisi (yoksa yerel SDK bildirimi gösterir).
  static HeroSignalForegroundWillDisplayHandler? _foregroundHandler;

  /// In-app mesajların çizileceği navigator (verilmezse kök navigator aranır).
  static GlobalKey<NavigatorState>? _navigatorKey;

  static bool _handlerInstalled = false;

  /// [_Notifications.addPermissionObserver] ile eklenen gözlemciler ve olay akışı aboneliği (ilk gözlemcide açılır).
  static final List<HeroSignalPermissionObserver> _permissionObservers = [];
  static StreamSubscription<bool>? _permissionSubscription;

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
          HeroSignalNotification.fromMap(Map<Object?, Object?>.from(args['notification'] as Map)),
          eventId: args['eventId'] as String?,
        );
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
  /// [web] yalnızca Flutter web'de kullanılır (service worker yolu/kapsamı); Android ve iOS'ta yok sayılır.
  static Future<void> initialize(
    String appId, {
    String apiUrl = 'https://api.herosignal.dev',
    bool requiresPrivacyConsent = false,
    HeroSignalLogLevel logLevel = HeroSignalLogLevel.warn,
    HeroSignalWebOptions? web,
  }) {
    _ensureHandler();
    return _channel.invokeMethod<void>('initialize', {
      'appId': appId,
      'apiUrl': apiUrl,
      'requiresPrivacyConsent': requiresPrivacyConsent,
      'logLevel': logLevel.name,
      'web': ?web?.toMap(),
    });
  }

  static Future<void> setConsentGiven(bool given) => _channel.invokeMethod<void>('setConsentGiven', {'given': given});

  /// Anonim kullanıcıyı kimlikli kullanıcıya bağlar (gerekirse birleştirir). Kimlik kanıtı app ayarına göre HMAC
  /// [identityHash] ve/veya sunucunuzda imzalanmış ES256 [jwt]'dir. JWT yerel SDK'da kalıcı saklanır ve SDK
  /// isteklerinde `Authorization: Bearer` başlığıyla gider; süresi dolunca [updateUserJwt] ile yenilenir. App kanıtı
  /// zorunlu tutuyorsa ve eksikse [PlatformException] döner.
  static Future<void> login(String externalId, {String? identityHash, String? jwt}) =>
      _channel.invokeMethod<void>('login', {
        'externalId': externalId,
        'identityHash': identityHash,
        'jwt': ?jwt,
      });

  /// Giriş yapmış kullanıcının kimlik JWT'sini yeniler; giriş yoksa veya belirteç boşsa [PlatformException].
  static Future<void> updateUserJwt(String jwt) => _channel.invokeMethod<void>('updateUserJwt', {'jwt': jwt});

  /// Kimliği ayırır; kimlik JWT'si ve identity hash cihazdan silinir.
  static Future<void> logout() => _channel.invokeMethod<void>('logout');

  static const User = _User();
  static const Notifications = _Notifications();
  static const InAppMessages = _InAppMessages();
  static const Inbox = _Inbox();
  static const Session = _Session();
  static const LiveActivities = _LiveActivities();
  static const Location = _Location();
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

  /// Kullanıcının kategori/kanal tercihleri ve app kategorileri (ADR-0019 §4); sahiplik kanıtı yerel SDK'da eklenir.
  /// Abonelik henüz yoksa [PlatformException] (`NOT_READY`).
  Future<HeroSignalPreferences> getPreferences() async {
    final result = await HeroSignal._channel.invokeMethod<Map<Object?, Object?>>('getPreferences');
    return HeroSignalPreferences.fromMap(result ?? const {});
  }

  /// Tercihleri yazar (1-100 kayıt; `channel` null = tüm kanallar); güncel listeyi döndürür.
  Future<HeroSignalPreferences> setPreferences(List<HeroSignalPreferenceInput> preferences) async {
    final result = await HeroSignal._channel.invokeMethod<Map<Object?, Object?>>(
      'setPreferences',
      {'preferences': preferences.map((p) => p.toMap()).toList()},
    );
    return HeroSignalPreferences.fromMap(result ?? const {});
  }

  _PushSubscription get pushSubscription => const _PushSubscription();
}

class _PushSubscription {
  const _PushSubscription();

  Future<HeroSignalPushSubscriptionState> get state async {
    final result = await HeroSignal._channel.invokeMethod<Map<Object?, Object?>>('getSubscriptionState');
    return HeroSignalPushSubscriptionState.fromMap(result ?? const {});
  }

  Future<String?> get id async => (await state).id;

  /// Push token'ı (FCM/APNs); henüz alınmadıysa `null`.
  Future<String?> get token async => (await state).token;
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

  /// Etkin bildirim izni değişiklikleri (yerel SDK izin gözlemcisinden): [requestPermission] sonrası ve uygulama
  /// ön plana döndüğünde izin ayarlardan değiştiyse yeni değer gelir. İlk durum gönderilmez; güncel değer için
  /// [permission] okunur.
  Stream<bool> get permissionStream =>
      HeroSignal._rawEvents.where((e) => e['type'] == 'permission').map((e) => e['permission'] == true);

  /// eski sağlayıcı biçimli izin gözlemcisi ([permissionStream] üzerine). Aynı gözlemci iki kez eklenmez.
  void addPermissionObserver(HeroSignalPermissionObserver observer) {
    if (HeroSignal._permissionObservers.contains(observer)) return;
    HeroSignal._permissionObservers.add(observer);
    HeroSignal._permissionSubscription ??= permissionStream.listen((granted) {
      for (final o in List<HeroSignalPermissionObserver>.of(HeroSignal._permissionObservers)) {
        o(granted);
      }
    });
  }

  /// Gözlemciyi kaldırır; son gözlemci kaldırılınca olay akışı aboneliği kapatılır.
  void removePermissionObserver(HeroSignalPermissionObserver observer) {
    HeroSignal._permissionObservers.remove(observer);
    if (HeroSignal._permissionObservers.isEmpty) {
      HeroSignal._permissionSubscription?.cancel();
      HeroSignal._permissionSubscription = null;
    }
  }

  /// Tepsideki/bildirim merkezindeki tüm HeroSignal bildirimlerini kaldırır ve rozeti sıfırlar.
  Future<void> clearAll() => HeroSignal._channel.invokeMethod<void>('clearAll');

  /// Yalnızca Android: tek bir bildirimi [HeroSignalNotification.androidNotificationId] ile kaldırır (iOS'ta etkisiz;
  /// iOS için [removeNotificationByIdentifier]).
  Future<void> removeNotification(int androidNotificationId) =>
      HeroSignal._channel.invokeMethod<void>('removeNotification', {'id': androidNotificationId});

  /// Yalnızca iOS: tek bir bildirimi istek kimliğiyle (`UNNotificationRequest.identifier`; mesajda `collapse_id`
  /// verildiyse odur) bildirim merkezinden kaldırır (Android'de etkisiz).
  Future<void> removeNotificationByIdentifier(String identifier) =>
      HeroSignal._channel.invokeMethod<void>('removeNotification', {'identifier': identifier});

  /// Aynı grup anahtarına sahip bildirimleri kaldırır (Android `android_group`, iOS `thread-id`).
  Future<void> removeGroupedNotifications(String group) =>
      HeroSignal._channel.invokeMethod<void>('removeGroupedNotifications', {'group': group});

  /// Bildirim/düğme tıklamaları. Uygulama kapalıyken (veya akış dinlenmeden önce) gelen tıklamalar ilk dinleyiciye
  /// teslim edilir.
  Stream<HeroSignalClickEvent> get clickStream {
    // Yerel olay akışını açar (tıklama dağıtıcısı ilk erişimde kurulur).
    HeroSignal._rawEvents;
    return HeroSignal._clicks.stream;
  }

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

  /// eski sağlayıcı biçimli tıklama dinleyicisi ([clickStream] üzerine). Aynı dinleyici iki kez eklenmez.
  void addClickListener(HeroSignalInAppClickListener listener) {
    HeroSignal._inAppClickListeners.putIfAbsent(listener, () => clickStream.listen(listener));
  }

  /// [addClickListener] ile eklenen dinleyiciyi kaldırır.
  void removeClickListener(HeroSignalInAppClickListener listener) {
    HeroSignal._inAppClickListeners.remove(listener)?.cancel();
  }

  /// eski sağlayıcı biçimli yaşam döngüsü dinleyicisi ([lifecycleStream] üzerine). Aynı dinleyici iki kez eklenmez.
  void addLifecycleListener(HeroSignalInAppLifecycleListener listener) {
    HeroSignal._inAppLifecycleListeners.putIfAbsent(listener, () => lifecycleStream.listen(listener));
  }

  /// [addLifecycleListener] ile eklenen dinleyiciyi kaldırır.
  void removeLifecycleListener(HeroSignalInAppLifecycleListener listener) {
    HeroSignal._inAppLifecycleListeners.remove(listener)?.cancel();
  }
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

/// iOS Live Activities (ADR-0024), genel `HeroSignalDefaultLiveActivityAttributes` türüyle. Android'de çağrılar
/// [PlatformException] (`PLATFORM_NOT_SUPPORTED`) ile döner; iOS hata kodları: `PLATFORM_NOT_SUPPORTED` (iOS 16.1
/// öncesi), `NOT_READY`, `INVALID_ARGUMENT`, `LIVE_ACTIVITY_FAILED`.
class _LiveActivities {
  const _LiveActivities();

  /// Etkinlik kimliği kuralı (sunucu ve iOS SDK ile aynı): 1-100 karakter; harf, rakam ve `_ . : -`.
  static final RegExp _activityId = RegExp(r'^[A-Za-z0-9_.:-]{1,100}$');

  /// Sunucunun uzaktan başlatmada `attributes` içine yazdığı ayrılmış anahtar.
  static const String _reservedKey = 'herosignal';

  /// Genel türü izlemeye alır: push-to-start belirteci (iOS 17.2+) ve başlayan her etkinliğin güncelleme belirteci
  /// sunucuya kaydedilir. [HeroSignal.initialize]'dan sonra, uygulama her açıldığında çağrılmalıdır.
  Future<void> setupDefaultLiveActivity() => HeroSignal._channel.invokeMethod<void>('setupDefaultLiveActivity');

  /// Genel türle yerel bir etkinlik başlatır (iOS 16.1+); sunucu sonraki `update`/`end` çağrılarını [activityId] ile
  /// yapar. Değerler metin, sonlu sayı veya `bool`; anahtarlar 1-64 karakter; [attributes] içinde `herosignal`
  /// anahtarı ayrılmıştır. Kurala uymayan girdi platforma gitmeden [ArgumentError] fırlatır.
  Future<void> startDefaultLiveActivity(
    String activityId,
    Map<String, Object> attributes,
    Map<String, Object> contentState,
  ) {
    if (!_activityId.hasMatch(activityId)) {
      throw ArgumentError.value(activityId, 'activityId', '1-100 karakter olmalı (harf, rakam ve _ . : -)');
    }
    _checkValues(attributes, 'attributes', reservedKey: _reservedKey);
    _checkValues(contentState, 'contentState');
    return HeroSignal._channel.invokeMethod<void>('startDefaultLiveActivity', {
      'activityId': activityId,
      'attributes': attributes,
      'contentState': contentState,
    });
  }

  static void _checkValues(Map<String, Object> values, String name, {String? reservedKey}) {
    for (final MapEntry(:key, :value) in values.entries) {
      if (key.isEmpty || key.length > 64) {
        throw ArgumentError.value(key, name, 'anahtarlar 1-64 karakter olmalı');
      }
      if (key == reservedKey) {
        throw ArgumentError.value(key, name, "'$reservedKey' anahtarı ayrılmıştır");
      }
      final valid = value is String || value is bool || (value is num && value.isFinite);
      if (!valid) {
        throw ArgumentError.value(value, '$name.$key', 'metin, sonlu sayı veya bool olmalı');
      }
    }
  }
}

/// Konum paylaşımı (v2 Faz 17b): yalnızca uygulama ön plandayken, oturum başında ve ön plana dönüşte en sık 5 dakikada
/// bir yaklaşık konum push aboneliğine yazılır. İzin yoksa veya gizlilik onayı verilmemişse gönderilmez; tercih yerel
/// SDK'da kalıcıdır. İlk konum sunucuda KVKK açık rıza kaydı sayılır; [setShared] `false` konumu ve rıza kaydını sildirir.
class _Location {
  const _Location();

  /// Paylaşımı açar/kapatır (kalıcı). Açılırken izin varsa konum hemen gönderilir; izin için [requestPermission].
  Future<void> setShared(bool shared) =>
      HeroSignal._channel.invokeMethod<void>('setLocationShared', {'shared': shared});

  /// Paylaşım açık mı (kalıcı tercih; izin durumundan bağımsız).
  Future<bool> get isShared async => (await HeroSignal._channel.invokeMethod<bool>('getLocationShared')) ?? false;

  /// Konum iznini ister: izin yoksa önce açıklama ([rationale]; verilmezse SDK'nın tr/en varsayılan metni), kullanıcı
  /// devam ederse sistem istemi. İzin verildiyse (veya zaten varsa) `true`; reddedildi, vazgeçildi veya izin
  /// tanımlanmadıysa (Android manifest / iOS `NSLocationWhenInUseUsageDescription`) `false`.
  Future<bool> requestPermission({String? rationale}) async =>
      (await HeroSignal._channel.invokeMethod<bool>('requestLocationPermission', {'rationale': rationale})) ?? false;
}

class _Debug {
  const _Debug();

  Future<void> setLogLevel(HeroSignalLogLevel level) => HeroSignal._channel.invokeMethod<void>('setLogLevel', {'level': level.name});
}
