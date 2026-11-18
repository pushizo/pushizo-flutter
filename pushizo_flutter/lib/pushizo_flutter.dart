/// Pushizo Flutter SDK: Android/iOS yerel SDK'larını platform kanalı ile sarar.
///
/// ```dart
/// await Pushizo.initialize('app_…', apiUrl: 'https://api.pushizo.com');
/// await Pushizo.Notifications.requestPermission();
/// await Pushizo.login('user_42');
/// await Pushizo.login('user_42', jwt: jwtFromYourServer); // identity verification `jwt`/`both`
/// await Pushizo.User.addTags({'plan': 'pro'});
/// Pushizo.Notifications.clickStream.listen((e) => print(e.url));
/// Pushizo.Notifications.addPermissionObserver((granted) => print('izin: $granted'));
/// Pushizo.Notifications.setForegroundWillDisplayHandler((event) {
///   if (event.notification.data['silent_in_app'] == '1') event.preventDefault();
/// });
/// await Pushizo.User.addEmail('ali@pushizo.com');
/// final prefs = await Pushizo.User.getPreferences();
/// await Pushizo.InAppMessages.addTrigger('level', 'gold');
/// final page = await Pushizo.Inbox.list(limit: 20);
/// final banners = await Pushizo.Placements.list('home_top'); // çizim uygulamanın; reportImpression/reportClick
/// if (await Pushizo.FeatureFlags.isEnabled('new_checkout')) showNewCheckout();
/// await Pushizo.Chat.start();
/// Pushizo.Chat.events.listen((e) => print(e.message?.text));
/// await Pushizo.Chat.sendMessage('Merhaba');
/// await Pushizo.LiveActivities.setupDefaultLiveActivity(); // yalnızca iOS
/// if (await Pushizo.Location.requestPermission()) await Pushizo.Location.setShared(true);
/// if (await Pushizo.Delivery.shouldShowGuidance()) await Pushizo.Delivery.showGuidance(); // yalnızca Android
/// await Pushizo.login('user_42', profile: const PushizoUserProfile(email: 'ali@pushizo.com', tags: {'plan': 'pro'}));
/// await Pushizo.User.setAdsPersonalizationConsent(true);
/// await Pushizo.Ads.setAdvertisingId(advertisingId); // GAID / IDFA; null kaydı siler
/// await Pushizo.Notifications.setBadgeCount(3);
/// await Pushizo.User.setProperty('first_name', 'Ali'); // null özelliği siler
/// Pushizo.Inbox.addObserver((e) => print('okunmamış: ${e.unreadCount}'));
/// Pushizo.FeatureFlags.addObserver(() => print('bayraklar yenilendi'));
/// await Pushizo.Session.sendEvent('purchase', value: 49.9, eventId: 'order-1042'); // pikselle tekilleştirme
/// await Pushizo.Chat.show(); // hazır sohbet ekranı
/// ```
///
/// Flutter web'de çağrılar sayfaya yüklenen Web SDK'ya (`window.Pushizo`) iletilir; web'de karşılığı olmayan
/// yöntemler `PlatformException(code: 'PLATFORM_NOT_SUPPORTED')` döndürür (bkz. `docs/sdk/flutter.md` "Flutter web").
library;

// Statik ad alanları (User, Notifications…) eski sağlayıcı ile aynı API biçimini korur.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'src/chat_models.dart';
part 'src/delivery_models.dart';
part 'src/in_app_view.dart';
part 'src/messaging_models.dart';
part 'src/models.dart';
part 'src/strings_gen.dart';

/// Günlük seviyesi.
enum PushizoLogLevel { none, error, warn, info, debug }

class Pushizo {
  Pushizo._();

  static const MethodChannel _channel = MethodChannel('pushizo_flutter');
  static const EventChannel _events = EventChannel('pushizo_flutter/events');
  static Stream<Map<String, dynamic>>? _eventStream;

  static Stream<Map<String, dynamic>> get _rawEvents {
    final existing = _eventStream;
    if (existing != null) return existing;
    final stream = _events.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));
    _eventStream = stream;
    // Tıklamalar ayrı, bekletmeli akıştan dağıtılır: olay akışı başka bir dinleyiciyle (ör. permissionStream) açıldığında
    // gelen tıklama, `clickStream` henüz dinlenmiyorsa kaybolmaz (soğuk başlangıç).
    // Sohbet bildirimi tıklamaları da bekletilir (`Chat.openStream` soğuk başlangıçta henüz dinlenmiyor olabilir).
    stream.where((e) => e['type'] == 'chatOpen').listen((e) {
      final open = PushizoChatOpenEvent.fromMap(e);
      if (_chatOpens.hasListener) {
        _chatOpens.add(open);
      } else {
        if (_pendingChatOpens.length >= _maxPendingClicks) _pendingChatOpens.removeAt(0);
        _pendingChatOpens.add(open);
      }
    });
    stream.where((e) => e['type'] == 'click').listen((e) {
      final click = PushizoClickEvent.fromMap(e);
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
  static final StreamController<PushizoClickEvent> _clicks = StreamController<PushizoClickEvent>.broadcast(
    onListen: () {
      final pending = List<PushizoClickEvent>.of(_pendingClicks);
      _pendingClicks.clear();
      pending.forEach(_clicks.add);
    },
  );
  static final List<PushizoClickEvent> _pendingClicks = [];

  /// Sohbet bildirimi tıklamaları; ilk dinleyici bağlanınca bekleyenler iletilir.
  static final StreamController<PushizoChatOpenEvent> _chatOpens = StreamController<PushizoChatOpenEvent>.broadcast(
    onListen: () {
      final pending = List<PushizoChatOpenEvent>.of(_pendingChatOpens);
      _pendingChatOpens.clear();
      pending.forEach(_chatOpens.add);
    },
  );
  static final List<PushizoChatOpenEvent> _pendingChatOpens = [];
  static const int _maxPendingClicks = 20;

  /// [_InAppMessages.addClickListener] / [_InAppMessages.addLifecycleListener] ile eklenen dinleyicilerin abonelikleri.
  static final Map<PushizoInAppClickListener, StreamSubscription<PushizoInAppClickEvent>> _inAppClickListeners = {};
  static final Map<PushizoInAppLifecycleListener, StreamSubscription<PushizoInAppLifecycleEvent>>
      _inAppLifecycleListeners = {};

  /// Ön plan gösterim kararı veren Dart işleyicisi (yoksa yerel SDK bildirimi gösterir).
  static PushizoForegroundWillDisplayHandler? _foregroundHandler;

  /// In-app mesajların çizileceği navigator (verilmezse kök navigator aranır).
  static GlobalKey<NavigatorState>? _navigatorKey;

  static bool _handlerInstalled = false;

  /// [_FeatureFlags.addObserver] / [_Inbox.addObserver] ile eklenen gözlemcilerin abonelikleri.
  static final Map<PushizoFeatureFlagObserver, StreamSubscription<void>> _featureFlagObservers = {};
  static final Map<PushizoInboxObserver, StreamSubscription<PushizoInboxChangeEvent>> _inboxObservers = {};

  /// [_Notifications.addPermissionObserver] ile eklenen gözlemciler ve olay akışı aboneliği (ilk gözlemcide açılır).
  static final List<PushizoPermissionObserver> _permissionObservers = [];
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
        final event = PushizoForegroundEvent(
          PushizoNotification.fromMap(Map<Object?, Object?>.from(args['notification'] as Map)),
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
        return _InAppPresenter.instance.show(PushizoInAppMessage.fromMap(json));
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
    String apiUrl = 'https://api.pushizo.com',
    bool requiresPrivacyConsent = false,
    PushizoLogLevel logLevel = PushizoLogLevel.warn,
    PushizoWebOptions? web,
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

  /// Yerel SDK başlatıldı mı ([initialize] çağrıldı mı; Android'de saklanan yapılandırmayla erken başlatma dahil).
  static Future<bool> get isInitialized async => (await _channel.invokeMethod<bool>('isInitialized')) ?? false;

  static Future<void> setConsentGiven(bool given) => _channel.invokeMethod<void>('setConsentGiven', {'given': given});

  /// Anonim kullanıcıyı kimlikli kullanıcıya bağlar (gerekirse birleştirir). Kimlik kanıtı app ayarına göre HMAC
  /// [identityHash] ve/veya sunucunuzda imzalanmış ES256 [jwt]'dir. JWT yerel SDK'da kalıcı saklanır ve SDK
  /// isteklerinde `Authorization: Bearer` başlığıyla gider; süresi dolunca [updateUserJwt] ile yenilenir. App kanıtı
  /// zorunlu tutuyorsa ve eksikse [PlatformException] döner.
  ///
  /// [profile] verilirse e-posta, SMS, etiketler ve alias'lar girişle birlikte ayarlanır. Geçersiz e-posta veya telefon
  /// girişten önce reddedilir (`INVALID_ARGUMENT`); yarım kalmış bir kimlik değişimi olmaz.
  static Future<void> login(String externalId, {String? identityHash, String? jwt, PushizoUserProfile? profile}) =>
      _channel.invokeMethod<void>('login', {
        'externalId': externalId,
        'identityHash': identityHash,
        'jwt': ?jwt,
        'profile': ?profile?.toMap(),
      });

  /// Giriş yapmış kullanıcının kimlik JWT'sini yeniler; giriş yoksa veya belirteç boşsa [PlatformException].
  static Future<void> updateUserJwt(String jwt) => _channel.invokeMethod<void>('updateUserJwt', {'jwt': jwt});

  /// Kimliği ayırır; kimlik JWT'si ve identity hash cihazdan silinir.
  static Future<void> logout() => _channel.invokeMethod<void>('logout');

  static const User = _User();
  static const Notifications = _Notifications();
  static const InAppMessages = _InAppMessages();
  static const Inbox = _Inbox();

  /// İçerik kartları (ADR-0082).
  static const ContentCards = _ContentCards();
  static const Placements = _Placements();
  static const FeatureFlags = _FeatureFlags();
  static const Chat = _Chat();
  static const Session = _Session();
  static const LiveActivities = _LiveActivities();
  static const Location = _Location();

  /// Android teslimat güçlendirme (ADR-0092).
  static const Delivery = _Delivery();

  /// Mobil reklam kimliği (ADR-0037).
  static const Ads = _Ads();
  static const Debug = _Debug();
}

class _User {
  const _User();

  Future<void> addTag(String key, String value) => addTags({key: value});
  Future<void> addTags(Map<String, String> tags) => Pushizo._channel.invokeMethod<void>('addTags', {'tags': tags});
  Future<void> removeTag(String key) => removeTags([key]);
  Future<void> removeTags(List<String> keys) => Pushizo._channel.invokeMethod<void>('removeTags', {'keys': keys});
  Future<Map<String, String>> getTags() async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('getTags');
    return result?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
  }

  Future<void> setLanguage(String code) => Pushizo._channel.invokeMethod<void>('setLanguage', {'code': code});

  /// Kullanıcı özelliği yazar (ör. `setProperty('first_name', 'Ali')`); `null` özelliği siler. Değer metin, sonlu sayı,
  /// `bool` ya da bunların listesi/haritası (anahtarları metin) olabilir; çevrimdışıyken yerel SDK kuyruğunda bekler.
  /// Anahtar 1-64 karakter olmalıdır. Kurala uymayan girdi platforma gitmeden [ArgumentError] fırlatır.
  Future<void> setProperty(String key, Object? value) {
    final name = key.trim();
    if (name.isEmpty || name.length > 64) throw ArgumentError.value(key, 'key', 'özellik anahtarı 1-64 karakter olmalı');
    if (value != null && !_isPropertyValue(value)) {
      throw ArgumentError.value(value, 'value', 'metin, sonlu sayı, bool ya da bunların listesi/haritası olmalı');
    }
    return Pushizo._channel.invokeMethod<void>('setProperty', {'key': name, 'value': value});
  }

  static bool _isPropertyValue(Object? value) => switch (value) {
        String() || bool() => true,
        num() => value.isFinite,
        List() => value.every(_isPropertyValue),
        Map() => value.entries.every((e) => e.key is String && _isPropertyValue(e.value)),
        _ => false,
      };

  /// Kullanıcıya alias ekler (ör. `addAlias('crm_id', '42')`). Etiket: küçük harf, rakam, `_`.
  Future<void> addAlias(String label, String id) => addAliases({label: id});

  /// Birden çok alias'ı tek istekte ekler (en fazla 20; `external_id`/`hs_id` login/logout ile yönetilir).
  Future<void> addAliases(Map<String, String> aliases) =>
      Pushizo._channel.invokeMethod<void>('addAliases', {'aliases': aliases});

  Future<void> removeAlias(String label) => Pushizo._channel.invokeMethod<void>('removeAlias', {'label': label});
  /// E-posta aboneliği ekler (yerel SDK küçük harfe çevirir); geçersiz adreste [PlatformException] (`INVALID_ARGUMENT`).
  Future<void> addEmail(String email) => Pushizo._channel.invokeMethod<void>('addEmail', {'email': email});

  /// E-posta aboneliğini siler.
  Future<void> removeEmail(String email) => Pushizo._channel.invokeMethod<void>('removeEmail', {'email': email});

  /// SMS aboneliği ekler; numara E.164'e normalize edilir (`+90 (532) 123-45-67` → `+905321234567`).
  Future<void> addSms(String phoneNumber) => Pushizo._channel.invokeMethod<void>('addSms', {'phoneNumber': phoneNumber});

  /// SMS aboneliğini siler.
  Future<void> removeSms(String phoneNumber) => Pushizo._channel.invokeMethod<void>('removeSms', {'phoneNumber': phoneNumber});

  /// ADM (Fire OS) kayıt kimliğini ekler; ana FCM aboneliğinin yerine geçmez. Yalnızca Android: iOS ve web'de etkisizdir.
  /// Geçersiz kimlikte [PlatformException] (`INVALID_ARGUMENT`).
  Future<void> registerAdm(String token) => Pushizo._channel.invokeMethod<void>('registerAdm', {'token': token});

  /// Kullanıcının bu cihazda eklenen e-posta abonelikleri. Web'de Web SDK listeyi sunmadığından boş döner.
  Future<List<String>> get emails async =>
      (await Pushizo._channel.invokeListMethod<String>('getEmails')) ?? const <String>[];

  /// Kullanıcının bu cihazda eklenen SMS abonelikleri (E.164). Web'de boş döner.
  Future<List<String>> get smsNumbers async =>
      (await Pushizo._channel.invokeListMethod<String>('getSmsNumbers')) ?? const <String>[];

  Future<String?> get externalId => Pushizo._channel.invokeMethod<String>('getExternalId');
  Future<String?> get id => Pushizo._channel.invokeMethod<String>('getUserId');

  /// Kullanıcının kategori/kanal tercihleri ve app kategorileri (ADR-0019 §4); sahiplik kanıtı yerel SDK'da eklenir.
  /// Abonelik henüz yoksa [PlatformException] (`NOT_READY`).
  Future<PushizoPreferences> getPreferences() async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('getPreferences');
    return PushizoPreferences.fromMap(result ?? const {});
  }

  /// Tercihleri yazar (1-100 kayıt; `channel` null = tüm kanallar); güncel listeyi döndürür.
  Future<PushizoPreferences> setPreferences(List<PushizoPreferenceInput> preferences) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>(
      'setPreferences',
      {'preferences': preferences.map((p) => p.toMap()).toList()},
    );
    return PushizoPreferences.fromMap(result ?? const {});
  }

  /// Reklam kişiselleştirme rızası (ADR-0037): `true` iken kullanıcının e-posta/telefon özeti app'in bağladığı reklam
  /// platformlarının kitlelerine gönderilebilir; `false` rızayı geri alır. Güncel tercih listesini döndürür.
  /// Abonelik henüz yoksa [PlatformException] (`NOT_READY`).
  Future<PushizoPreferences> setAdsPersonalizationConsent(bool granted) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>(
      'setAdsPersonalizationConsent',
      {'granted': granted},
    );
    return PushizoPreferences.fromMap(result ?? const {});
  }

  /// Rıza kayıtları (`ads_personalization` …). Abonelik henüz yoksa [PlatformException] (`NOT_READY`).
  Future<List<PushizoConsent>> getConsents() async {
    final result = await Pushizo._channel.invokeListMethod<Object?>('getConsents');
    return (result ?? const <Object?>[])
        .whereType<Map>()
        .map((m) => PushizoConsent.fromMap(m.cast<Object?, Object?>()))
        .toList();
  }

  _PushSubscription get pushSubscription => const _PushSubscription();
}

class _PushSubscription {
  const _PushSubscription();

  Future<PushizoPushSubscriptionState> get state async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('getSubscriptionState');
    return PushizoPushSubscriptionState.fromMap(result ?? const {});
  }

  Future<String?> get id async => (await state).id;

  /// Push token'ı (FCM/APNs); henüz alınmadıysa `null`.
  Future<String?> get token async => (await state).token;
  Future<bool> get optedIn async => (await state).optedIn;
  Future<void> optIn() => Pushizo._channel.invokeMethod<void>('optIn');
  Future<void> optOut() => Pushizo._channel.invokeMethod<void>('optOut');

  /// Abonelik durumu değişiklikleri (token/opt-in/izin).
  Stream<PushizoPushSubscriptionState> get changes => Pushizo._rawEvents
      .where((e) => e['type'] == 'subscription')
      .map((e) => PushizoPushSubscriptionState.fromMap(Map<Object?, Object?>.from(e['state'] as Map)));
}

class _Notifications {
  const _Notifications();

  /// Sistem iznini ister; sonuç izin verildi mi.
  Future<bool> requestPermission() async => (await Pushizo._channel.invokeMethod<bool>('requestPermission')) ?? false;

  Future<bool> get permission async => (await Pushizo._channel.invokeMethod<bool>('getPermission')) ?? false;

  /// Etkin bildirim izni değişiklikleri (yerel SDK izin gözlemcisinden): [requestPermission] sonrası ve uygulama
  /// ön plana döndüğünde izin ayarlardan değiştiyse yeni değer gelir. İlk durum gönderilmez; güncel değer için
  /// [permission] okunur.
  Stream<bool> get permissionStream =>
      Pushizo._rawEvents.where((e) => e['type'] == 'permission').map((e) => e['permission'] == true);

  /// eski sağlayıcı biçimli izin gözlemcisi ([permissionStream] üzerine). Aynı gözlemci iki kez eklenmez.
  void addPermissionObserver(PushizoPermissionObserver observer) {
    if (Pushizo._permissionObservers.contains(observer)) return;
    Pushizo._permissionObservers.add(observer);
    Pushizo._permissionSubscription ??= permissionStream.listen((granted) {
      for (final o in List<PushizoPermissionObserver>.of(Pushizo._permissionObservers)) {
        o(granted);
      }
    });
  }

  /// Gözlemciyi kaldırır; son gözlemci kaldırılınca olay akışı aboneliği kapatılır.
  void removePermissionObserver(PushizoPermissionObserver observer) {
    Pushizo._permissionObservers.remove(observer);
    if (Pushizo._permissionObservers.isEmpty) {
      Pushizo._permissionSubscription?.cancel();
      Pushizo._permissionSubscription = null;
    }
  }

  /// Tepsideki/bildirim merkezindeki tüm Pushizo bildirimlerini kaldırır ve rozeti sıfırlar.
  Future<void> clearAll() => Pushizo._channel.invokeMethod<void>('clearAll');

  /// Uygulama rozetini ayarlar; sonuç rozetin bu cihazda gösterilip gösterilemediğidir. Negatif değerde [ArgumentError].
  ///
  /// - iOS: uygulama simgesi rozeti ve bildirim uzantısıyla paylaşılan sayaç ayarlanır; `true`.
  /// - Android: başlatıcı rozeti için standart bir "sayıyı ayarla" API'si yoktur. Yerel SDK sayıyı saklar ve sonraki
  ///   bildirimlere yazar (sayı gösteren başlatıcılar bunu kullanır; tepside bildirim yokken rozet görünmez). Android 8
  ///   öncesinde, bildirimler kapalıyken ya da kanalın rozeti kapatıldıysa `false` (sayı yine saklanır).
  /// - Web: App Badging API (yüklü PWA'larda görünür); tarayıcı desteklemiyorsa ya da Web SDK yüklenmediyse `false`.
  Future<bool> setBadgeCount(int count) async {
    if (count < 0) throw ArgumentError.value(count, 'count', 'Rozet sayısı negatif olamaz');
    return (await Pushizo._channel.invokeMethod<bool>('setBadgeCount', {'count': count})) ?? false;
  }

  /// Rozeti sıfırlar ([setBadgeCount] `0`); tepsideki bildirimleri de kaldırmak için [clearAll].
  Future<bool> clearBadge() => setBadgeCount(0);

  /// Geçerli rozet sayısı: Android'de [setBadgeCount] ile saklanan son değer, iOS'ta uygulama simgesindeki rozet,
  /// web'de bu oturumda başarıyla ayarlanan son değer (tarayıcı rozeti okutmaz).
  Future<int> get badgeCount async => (await Pushizo._channel.invokeMethod<int>('getBadgeCount')) ?? 0;

  /// Yalnızca Android: tek bir bildirimi [PushizoNotification.androidNotificationId] ile kaldırır (iOS'ta etkisiz;
  /// iOS için [removeNotificationByIdentifier]).
  Future<void> removeNotification(int androidNotificationId) =>
      Pushizo._channel.invokeMethod<void>('removeNotification', {'id': androidNotificationId});

  /// Yalnızca iOS: tek bir bildirimi istek kimliğiyle (`UNNotificationRequest.identifier`; mesajda `collapse_id`
  /// verildiyse odur) bildirim merkezinden kaldırır (Android'de etkisiz).
  Future<void> removeNotificationByIdentifier(String identifier) =>
      Pushizo._channel.invokeMethod<void>('removeNotification', {'identifier': identifier});

  /// Aynı grup anahtarına sahip bildirimleri kaldırır (Android `android_group`, iOS `thread-id`).
  Future<void> removeGroupedNotifications(String group) =>
      Pushizo._channel.invokeMethod<void>('removeGroupedNotifications', {'group': group});

  /// Bildirim/düğme tıklamaları. Uygulama kapalıyken (veya akış dinlenmeden önce) gelen tıklamalar ilk dinleyiciye
  /// teslim edilir.
  Stream<PushizoClickEvent> get clickStream {
    // Yerel olay akışını açar (tıklama dağıtıcısı ilk erişimde kurulur).
    Pushizo._rawEvents;
    return Pushizo._clicks.stream;
  }

  /// Ön planda gelen bildirimler (yalnızca bilgi; gösterim kararı için [setForegroundWillDisplayHandler]).
  Stream<PushizoNotification> get foregroundStream => Pushizo._rawEvents
      .where((e) => e['type'] == 'foreground')
      .map((e) => PushizoNotification.fromMap(Map<Object?, Object?>.from(e['notification'] as Map)));

  /// Uygulama ön plandayken gelen bildirimin gösterilip gösterilmeyeceğine Dart'ta karar verir:
  /// işleyici `event.preventDefault()` çağırırsa bildirim gösterilmez. `null` işleyiciyi kaldırır.
  /// İşleyici asenkron olabilir (iOS'ta en fazla 25 sn beklenir).
  Future<void> setForegroundWillDisplayHandler(PushizoForegroundWillDisplayHandler? handler) {
    Pushizo._foregroundHandler = handler;
    Pushizo._ensureHandler();
    return Pushizo._channel.invokeMethod<void>('setForegroundHandlerEnabled', {'enabled': handler != null});
  }
}

/// In-app mesajlar: liste, tetik değerlendirme, sıklık ve olay kaydı yerel SDK'dadır; mesaj Flutter widget'larıyla
/// (modal/tam ekran → rota, banner → overlay) çizilir.
class _InAppMessages {
  const _InAppMessages();

  Future<void> addTrigger(String key, String value) => addTriggers({key: value});
  Future<void> addTriggers(Map<String, String> triggers) =>
      Pushizo._channel.invokeMethod<void>('addTriggers', {'triggers': triggers});
  Future<void> removeTrigger(String key) => removeTriggers([key]);
  Future<void> removeTriggers(List<String> keys) => Pushizo._channel.invokeMethod<void>('removeTriggers', {'keys': keys});
  Future<void> clearTriggers() => Pushizo._channel.invokeMethod<void>('clearTriggers');
  Future<Map<String, String>> getTriggers() async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('getTriggers');
    return result?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {};
  }

  /// Geçerli ekran adı (`screen` tetikleri); ekrandan çıkarken `null`.
  Future<void> setScreen(String? name) => Pushizo._channel.invokeMethod<void>('setScreen', {'name': name});

  /// true iken yeni mesaj gösterilmez.
  Future<void> setPaused(bool paused) => Pushizo._channel.invokeMethod<void>('setInAppPaused', {'paused': paused});
  Future<bool> get paused async => (await Pushizo._channel.invokeMethod<bool>('getInAppPaused')) ?? false;

  /// Mesajların çizileceği navigator; verilmezse uygulamanın kök navigator'ı kullanılır (MaterialApp `navigatorKey`).
  void setNavigatorKey(GlobalKey<NavigatorState>? key) {
    Pushizo._navigatorKey = key;
    Pushizo._ensureHandler();
  }

  /// Düğme tıklamaları (`messageId`, `actionId`, `url`).
  Stream<PushizoInAppClickEvent> get clickStream =>
      Pushizo._rawEvents.where((e) => e['type'] == 'inAppClick').map(PushizoInAppClickEvent.fromMap);

  /// Yaşam döngüsü (willDisplay/didDisplay/willDismiss/didDismiss).
  Stream<PushizoInAppLifecycleEvent> get lifecycleStream => Pushizo._rawEvents
      .where((e) => e['type'] == 'inAppLifecycle')
      .map(PushizoInAppLifecycleEvent.fromMap)
      .where((e) => e != null)
      .cast<PushizoInAppLifecycleEvent>();

  /// eski sağlayıcı biçimli tıklama dinleyicisi ([clickStream] üzerine). Aynı dinleyici iki kez eklenmez.
  void addClickListener(PushizoInAppClickListener listener) {
    Pushizo._inAppClickListeners.putIfAbsent(listener, () => clickStream.listen(listener));
  }

  /// [addClickListener] ile eklenen dinleyiciyi kaldırır.
  void removeClickListener(PushizoInAppClickListener listener) {
    Pushizo._inAppClickListeners.remove(listener)?.cancel();
  }

  /// eski sağlayıcı biçimli yaşam döngüsü dinleyicisi ([lifecycleStream] üzerine). Aynı dinleyici iki kez eklenmez.
  void addLifecycleListener(PushizoInAppLifecycleListener listener) {
    Pushizo._inAppLifecycleListeners.putIfAbsent(listener, () => lifecycleStream.listen(listener));
  }

  /// [addLifecycleListener] ile eklenen dinleyiciyi kaldırır.
  void removeLifecycleListener(PushizoInAppLifecycleListener listener) {
    Pushizo._inAppLifecycleListeners.remove(listener)?.cancel();
  }
}

/// Canlı sohbet (ADR-0040; Android ve iOS). Ziyaretçi kimliği, çevrimdışı kuyruk, canlı akış (SSE + yoklama yedeği) ve
/// push ile gelen mesajlar yerel SDK'dadır; login/logout ve push aboneliği değişince bağlama yerel SDK'da yenilenir.
/// Hazır arayüz için [show] / [hide]; kendi arayüzünüz için aşağıdaki veri yöntemleri.
///
/// Flutter web'de [show], [hide], [isPresented], [getConfig], [getConversation], [setTyping], [attachmentUrl],
/// [unreadCount] ve [refreshUnreadCount] Web SDK'ya iletilir; mesajlaşma yöntemleri ([start], [getMessages],
/// [sendMessage], [sendAttachment], [markRead], [leaveOfflineMessage], [startListening], [stopListening], [visitorId])
/// `PLATFORM_NOT_SUPPORTED` döner: web'de mesajlaşma Web SDK sohbet widget'ıyla ([show]) yapılır.
class _Chat {
  const _Chat();

  /// Hazır sohbet ekranını açar: Android'de yerel SDK'nın sohbet Activity'si, iOS'ta modal sohbet ekranı, web'de Web SDK
  /// sohbet widget'ı (açık hâlde). Ekran zaten açıksa yeniden açılmaz. SDK başlatılmadıysa ya da (web) sohbet app
  /// ayarında kapalıysa hiçbir şey yapılmaz.
  Future<void> show() => Pushizo._channel.invokeMethod<void>('chatShow');

  /// [show] ile açılan sohbet ekranını kapatır (web'de widget'ı sayfadan kaldırır); açık bir ekran kapatıldıysa `true`.
  Future<bool> hide() async => (await Pushizo._channel.invokeMethod<bool>('chatHide')) ?? false;

  /// [show] ile açılan sohbet ekranı şu an açık mı (web'de: sohbet widget'ı sayfada mı).
  Future<bool> get isPresented async => (await Pushizo._channel.invokeMethod<bool>('chatIsPresented')) ?? false;

  /// Sohbeti etkinleştirir ve ziyaretçiyi bağlar (giriş yapmış kullanıcı, push aboneliği); konuşma varsa döner.
  Future<PushizoChatIdentifyResult> start({String? name, String? email, String? language}) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('chatStart', {
      'name': ?name,
      'email': ?email,
      'language': ?language,
    });
    return PushizoChatIdentifyResult.fromMap(result ?? const {});
  }

  /// Widget ayarları, çevrimiçi durumu, çevrimdışı metni ve ek sınırları. Web'de [language] yok sayılır (Web SDK dili
  /// kullanılır).
  Future<PushizoChatConfig> getConfig({String? language}) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('chatGetConfig', {'language': ?language});
    return PushizoChatConfig.fromMap(result ?? const {});
  }

  /// Konuşma (yoksa null) ve okunmamış sayısı.
  Future<PushizoChatConversationState> getConversation() async => PushizoChatConversationState.fromMap(
        await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('chatGetConversation') ?? const {},
      );

  /// Mesajlar (kronolojik): parametresiz en yeni [limit]; [afterSeq] sonrakiler, [beforeSeq] daha eski geçmiş (1-100).
  Future<PushizoChatMessagePage> getMessages({int? afterSeq, int? beforeSeq, int limit = 50}) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit', '1-100 olmalı');
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('chatGetMessages', {
      'afterSeq': ?afterSeq,
      'beforeSeq': ?beforeSeq,
      'limit': limit,
    });
    return PushizoChatMessagePage.fromMap(result ?? const {});
  }

  /// Mesaj gönderir (ilk mesaj konuşmayı açar); [optionId] bot sorusunda seçilen hızlı yanıttır. Ağ yoksa mesaj yerel
  /// SDK kuyruğuna alınır ve `pending` mesaj döner; gönderilince [events] üzerinden sunucu kopyası gelir.
  Future<PushizoChatMessage> sendMessage(String text, {String? optionId}) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('chatSendMessage', {
      'text': text,
      'optionId': ?optionId,
    });
    return PushizoChatMessage.fromMap(result!);
  }

  /// Ek gönderir (PNG/JPEG/WebP/GIF/PDF/düz metin, en çok 10 MB).
  Future<PushizoChatMessage> sendAttachment(Uint8List bytes, {required String fileName, required String mimeType, String? text}) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('chatSendAttachment', {
      'bytes': bytes,
      'fileName': fileName,
      'mimeType': mimeType,
      'text': ?text,
    });
    return PushizoChatMessage.fromMap(result!);
  }

  /// [seq] numarasına kadar okundu işaretler; kalan okunmamış sayısını döndürür.
  Future<int> markRead(int seq) async => (await Pushizo._channel.invokeMethod<int>('chatMarkRead', {'seq': seq})) ?? 0;

  /// Okunmamış sayısını sunucudan yeniler.
  Future<int> refreshUnreadCount() async => (await Pushizo._channel.invokeMethod<int>('chatRefreshUnreadCount')) ?? 0;

  /// Son bilinen okunmamış sayısı (ağ çağrısı yok).
  Future<int> get unreadCount async => (await Pushizo._channel.invokeMethod<int>('chatGetUnreadCount')) ?? 0;

  /// Çevrimdışı / çalışma saatleri dışında e-postayla mesaj bırakır.
  Future<PushizoChatMessage> leaveOfflineMessage({required String email, required String text, String? name}) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('chatLeaveOfflineMessage', {
      'email': email,
      'text': text,
      'name': ?name,
    });
    return PushizoChatMessage.fromMap(result!);
  }

  /// Yazıyor göstergesi (yerel SDK tekrarları seyreltir).
  Future<void> setTyping(bool typing) => Pushizo._channel.invokeMethod<void>('chatSetTyping', {'typing': typing});

  /// Canlı dinlemeyi başlatır; koparsa yerel SDK geri çekilmeyle yeniden bağlanır ve eksikleri yoklar.
  Future<void> startListening() => Pushizo._channel.invokeMethod<void>('chatStartListening');

  /// Canlı dinlemeyi durdurur (arka plana geçişte önerilir; temsilci mesajı push ile gelir).
  Future<void> stopListening() => Pushizo._channel.invokeMethod<void>('chatStopListening');

  /// Ek dosyasının adresi; ziyaretçi belirtecini taşır, yalnızca görsel yükleyiciye verin ve loglamayın.
  Future<String> attachmentUrl(String attachmentId, {bool download = false}) async =>
      (await Pushizo._channel.invokeMethod<String>('chatAttachmentUrl', {'attachmentId': attachmentId, 'download': download}))!;

  /// Bu cihazın ziyaretçi kimliği (sohbet henüz kullanılmadıysa null).
  Future<String?> get visitorId => Pushizo._channel.invokeMethod<String>('chatGetVisitorId');

  /// Canlı olay akışı ([startListening]) açık mı. Web'de her zaman `false`.
  Future<bool> get isListening async => (await Pushizo._channel.invokeMethod<bool>('chatIsListening')) ?? false;

  /// Canlı sohbet olayları (mesaj, yazıyor, okundu, okunmamış, konuşma, bağlantı, hata).
  Stream<PushizoChatEvent> get events => Pushizo._rawEvents
      .where((e) => e['type'] == 'chat')
      .map((e) => PushizoChatEvent.fromMap(Map<Object?, Object?>.from(e)));

  /// Yeni mesajlar ([events] içindeki `message` olayları).
  Stream<PushizoChatMessage> get messageStream => events.where((e) => e.type == 'message').map((e) => e.message!);

  /// Okunmamış sayısı değişimleri.
  Stream<int> get unreadCountStream => events.where((e) => e.type == 'unread').map((e) => e.count);

  /// Sohbet bildirimine tıklamalar (uygulama sohbet ekranını açmalı); soğuk başlangıçta gelenler ilk dinleyiciye iletilir.
  Stream<PushizoChatOpenEvent> get openStream {
    // Yerel olay akışını açar (bekletmeli dağıtıcı ilk erişimde kurulur).
    Pushizo._rawEvents;
    return Pushizo._chatOpens.stream;
  }
}

/// Bildirim kutusu (`add_to_inbox` mesajları); login'de verilen `identityHash` yerel SDK tarafından eklenir.
class _Inbox {
  const _Inbox();

  /// Öğeler (yeniden eskiye), okunmamış sayısı ve sonraki sayfa imleci (`limit` 1-200).
  Future<PushizoInboxPage> list({int limit = 50, String? cursor}) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('inboxList', {'limit': limit, 'cursor': cursor});
    return PushizoInboxPage.fromMap(result ?? const {});
  }

  /// Okundu işaretler; güncel öğeyi döndürür.
  Future<PushizoInboxItem> markRead(String id) async {
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('inboxMarkRead', {'id': id});
    return PushizoInboxItem.fromMap(result!);
  }

  /// Tümünü okundu işaretler; kalan okunmamış sayısını döndürür.
  Future<int> markAllRead() async => (await Pushizo._channel.invokeMethod<int>('inboxMarkAllRead')) ?? 0;

  /// Öğeyi kutudan kaldırır (arşivler).
  Future<void> archive(String id) => Pushizo._channel.invokeMethod<void>('inboxArchive', {'id': id});

  Future<int> unreadCount() async => (await Pushizo._channel.invokeMethod<int>('inboxUnreadCount')) ?? 0;

  /// Kutu değişimleri (yerel SDK kutu gözlemcisinden): `read`, `read_all` ve `archived` her işlemde, `listed` ve
  /// `count` yalnızca okunmamış sayısı değiştiğinde gelir. Rozet güncellemek için kullanılır; [Pushizo.initialize]'dan
  /// sonra yapılan çağrıların olayları iletilir.
  Stream<PushizoInboxChangeEvent> get changes => Pushizo._rawEvents
      .where((e) => e['type'] == 'inboxChange')
      .map((e) => PushizoInboxChangeEvent.fromMap(Map<Object?, Object?>.from(e)));

  /// Kutu değişim gözlemcisi ([changes] üzerine). Aynı gözlemci iki kez eklenmez.
  void addObserver(PushizoInboxObserver observer) {
    Pushizo._inboxObservers.putIfAbsent(observer, () => changes.listen(observer));
  }

  /// [addObserver] ile eklenen gözlemciyi kaldırır.
  void removeObserver(PushizoInboxObserver observer) {
    Pushizo._inboxObservers.remove(observer)?.cancel();
  }
}

/// İçerik kartları (ADR-0082): kalıcı kart akışı (`content_card` mesajları); kartlar bildirim kutusunda görünmez.
class _ContentCards {
  const _ContentCards();

  /// Kart akışı (sabitlenmiş → öncelik → yeni; `limit` 1-100).
  Future<PushizoContentCardFeed> list({int limit = 50}) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit', '1-100 olmalı');
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('contentCardsList', {'limit': limit});
    return PushizoContentCardFeed.fromMap(result ?? const {});
  }

  Future<PushizoContentCard> _event(String id, String event) async {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'kart kimliği gerekli');
    final result = await Pushizo._channel.invokeMethod<Map<Object?, Object?>>('contentCardEvent', {'id': id, 'event': event});
    return PushizoContentCard.fromMap(result!);
  }

  /// Kart ekranda gösterildi (ilk gösterim kaydedilir).
  Future<PushizoContentCard> logImpression(String id) => _event(id, 'impression');

  /// Karta tıklandı (gösterim ve okundu da sayılır).
  Future<PushizoContentCard> logClick(String id) => _event(id, 'click');

  /// Kart kapatıldı; akıştan kalkar.
  Future<PushizoContentCard> dismiss(String id) => _event(id, 'dismiss');
}

/// Gömülü yerleşimler (ADR-0068): uygulamanın ayırdığı alana içerik. [list] modeli döndürür, çizim uygulamanındır;
/// içerik ekrana gelince [reportImpression], düğmeye basılınca [reportClick], kapatılınca [reportDismiss] çağrılır.
/// Abonelik yoksa veya gizlilik onayı bekleniyorsa liste boştur.
class _Placements {
  const _Placements();

  /// Yerleşim anahtarı kuralı (sunucu ve yerel SDK'larla aynı).
  static final RegExp _key = RegExp(r'^[a-z][a-z0-9_.-]{0,63}$');

  /// [key] alanının içeriği (en çok [limit] mesaj, 1-10). Kurala uymayan girdi platforma gitmeden [ArgumentError] fırlatır.
  Future<List<PushizoInAppMessage>> list(String key, {int limit = 1}) async {
    if (!_key.hasMatch(key)) throw ArgumentError.value(key, 'key', 'geçersiz yerleşim anahtarı');
    if (limit < 1 || limit > 10) throw ArgumentError.value(limit, 'limit', '1-10 olmalı');
    final result = await Pushizo._channel.invokeMethod<List<Object?>>('placementsList', {'key': key, 'limit': limit});
    return [
      for (final json in result ?? const <Object?>[])
        if (json is String) PushizoInAppMessage.fromMap(jsonDecode(json) as Map<String, dynamic>),
    ];
  }

  /// İçerik ekrana geldi; [message] son [list] çağrılarından gelen mesaj olmalıdır (yerel taraf kimliğe göre bulur).
  Future<void> reportImpression(PushizoInAppMessage message) =>
      Pushizo._channel.invokeMethod<void>('placementsReportImpression', {'messageId': message.id});

  /// [buttonId] düğmesine basıldı ([PushizoInAppButton.id]).
  Future<void> reportClick(PushizoInAppMessage message, String buttonId) =>
      Pushizo._channel.invokeMethod<void>('placementsReportClick', {'messageId': message.id, 'buttonId': buttonId});

  /// Kullanıcı içeriği kapattı.
  Future<void> reportDismiss(PushizoInAppMessage message) =>
      Pushizo._channel.invokeMethod<void>('placementsReportDismiss', {'messageId': message.id});
}

/// Özellik bayrakları (ADR-0066): değerler oturum başında yerel SDK tarafından yenilenir ve cihazda saklanır; okuma
/// çağrıları ağa çıkmaz.
class _FeatureFlags {
  const _FeatureFlags();

  /// Değerleri hemen yeniler; başarıyla alındıysa `true`. Hata son değerleri korur; gizlilik onayı beklenirken istek
  /// gönderilmez.
  Future<bool> refresh() async => (await Pushizo._channel.invokeMethod<bool>('featureFlagsRefresh')) ?? false;

  /// Bayrak bu kullanıcı için açık mı; değer henüz yoksa [defaultValue].
  Future<bool> isEnabled(String key, {bool defaultValue = false}) async =>
      (await Pushizo._channel.invokeMethod<bool>('featureFlagsIsEnabled', {'key': key, 'defaultValue': defaultValue})) ??
      defaultValue;

  /// Bayrağın değeri: `String`, `num`, `bool`, `Map<String, dynamic>` veya `List<dynamic>` (JSON); değer yoksa
  /// [defaultValue].
  Future<Object?> getValue(String key, {Object? defaultValue}) async {
    // Yerel taraf değeri `{"value": …}` JSON metni olarak taşır; böylece nesne ve dizi değerler platformlar arasında
    // aynı Dart türlerine çözülür.
    final json = await Pushizo._channel.invokeMethod<String>('featureFlagsGetValue', {'key': key});
    if (json == null) return defaultValue;
    return (jsonDecode(json) as Map<String, dynamic>)['value'] ?? defaultValue;
  }

  /// Bayrak değerleri sunucudan her başarıyla yenilendiğinde (oturum başı ve [refresh]) bir olay gelir; güncel değerler
  /// [isEnabled] / [getValue] ile okunur.
  Stream<void> get changes => Pushizo._rawEvents.where((e) => e['type'] == 'featureFlags').map((_) {});

  /// Bayrak gözlemcisi ([changes] üzerine). Aynı gözlemci iki kez eklenmez.
  void addObserver(PushizoFeatureFlagObserver observer) {
    Pushizo._featureFlagObservers.putIfAbsent(observer, () => changes.listen((_) => observer()));
  }

  /// [addObserver] ile eklenen gözlemciyi kaldırır.
  void removeObserver(PushizoFeatureFlagObserver observer) {
    Pushizo._featureFlagObservers.remove(observer)?.cancel();
  }
}

class _Session {
  const _Session();

  /// Özel olay gönderir. [eventId] (isteğe bağlı) tekilleştirme kimliğidir: reklam pikseli / Conversions API ile aynı
  /// kimlik verilirse sunucu olayı tekilleşir (ADR-0038). 8-64 karakter; harf, rakam ve `. _ : -`. Verilmezse ya da
  /// biçim geçersizse SDK kendi kimliğini üretir.
  Future<void> sendEvent(String name, {Map<String, Object?> properties = const {}, double? value, String? eventId}) =>
      Pushizo._channel.invokeMethod<void>('sendEvent', {
        'name': name,
        'properties': properties,
        'value': value,
        'eventId': ?eventId,
      });
}

/// iOS Live Activities (ADR-0024), genel `PushizoDefaultLiveActivityAttributes` türüyle. Android'de çağrılar
/// [PlatformException] (`PLATFORM_NOT_SUPPORTED`) ile döner; iOS hata kodları: `PLATFORM_NOT_SUPPORTED` (iOS 16.1
/// öncesi), `NOT_READY`, `INVALID_ARGUMENT`, `LIVE_ACTIVITY_FAILED`.
class _LiveActivities {
  const _LiveActivities();

  /// Etkinlik kimliği kuralı (sunucu ve iOS SDK ile aynı): 1-100 karakter; harf, rakam ve `_ . : -`.
  static final RegExp _activityId = RegExp(r'^[A-Za-z0-9_.:-]{1,100}$');

  /// Sunucunun uzaktan başlatmada `attributes` içine yazdığı ayrılmış anahtar.
  static const String _reservedKey = 'pushizo';

  /// Genel türü izlemeye alır: push-to-start belirteci (iOS 17.2+) ve başlayan her etkinliğin güncelleme belirteci
  /// sunucuya kaydedilir. [Pushizo.initialize]'dan sonra, uygulama her açıldığında çağrılmalıdır.
  Future<void> setupDefaultLiveActivity() => Pushizo._channel.invokeMethod<void>('setupDefaultLiveActivity');

  /// Genel türle yerel bir etkinlik başlatır (iOS 16.1+); sunucu sonraki `update`/`end` çağrılarını [activityId] ile
  /// yapar. Değerler metin, sonlu sayı veya `bool`; anahtarlar 1-64 karakter; [attributes] içinde `pushizo`
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
    return Pushizo._channel.invokeMethod<void>('startDefaultLiveActivity', {
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
      Pushizo._channel.invokeMethod<void>('setLocationShared', {'shared': shared});

  /// Paylaşım açık mı (kalıcı tercih; izin durumundan bağımsız).
  Future<bool> get isShared async => (await Pushizo._channel.invokeMethod<bool>('getLocationShared')) ?? false;

  /// Konum iznini ister: izin yoksa önce açıklama ([rationale]; verilmezse SDK'nın tr/en varsayılan metni), kullanıcı
  /// devam ederse sistem istemi. İzin verildiyse (veya zaten varsa) `true`; reddedildi, vazgeçildi veya izin
  /// tanımlanmadıysa (Android manifest / iOS `NSLocationWhenInUseUsageDescription`) `false`.
  Future<bool> requestPermission({String? rationale}) async =>
      (await Pushizo._channel.invokeMethod<bool>('requestLocationPermission', {'rationale': rationale})) ?? false;

  /// Arka plan bölge izlemeyi açar/kapatır (ADR-0065; varsayılan kapalı, tercih kalıcı). İzlemeyi işletim sistemi yapar,
  /// sunucuya koordinat gitmez, yalnızca bölgeye giriş/çıkış bildirilir. [setShared] açık ve arka plan ("her zaman")
  /// konum izni verilmiş olmalıdır ([requestBackgroundPermission]); manifest/Info.plist girdileri uygulamanın
  /// sorumluluğundadır ve bu çağrı izin istemi açmaz. Web'de etkisizdir.
  Future<void> setGeofencingEnabled(bool enabled) =>
      Pushizo._channel.invokeMethod<void>('setGeofencingEnabled', {'enabled': enabled});

  /// Bölge izleme açık mı (kalıcı tercih; izin durumundan bağımsız). Web'de her zaman `false`.
  Future<bool> get isGeofencingEnabled async =>
      (await Pushizo._channel.invokeMethod<bool>('getGeofencingEnabled')) ?? false;

  /// Konum izni verilmiş mi (Android: yaklaşık veya hassas; iOS: "kullanırken" veya "her zaman"; web: tarayıcı konum
  /// izninin son bilinen durumu). İstem açmaz.
  Future<bool> get permissionGranted async =>
      (await Pushizo._channel.invokeMethod<bool>('getLocationPermissionGranted')) ?? false;

  /// Arka plan konum izni verilmiş mi (Android `ACCESS_BACKGROUND_LOCATION`, iOS "her zaman"). Web'de `false`.
  Future<bool> get backgroundPermissionGranted async =>
      (await Pushizo._channel.invokeMethod<bool>('getLocationBackgroundPermissionGranted')) ?? false;

  /// Arka plan konum iznini ister (bölge izleme için); sonuç izin verildi mi. Android'de önce açıklama diyaloğu
  /// ([rationale]; verilmezse SDK'nın yerelleştirilmiş metni) gösterilir, Android 11 ve sonrasında sistem Ayarlar
  /// ekranını açar; manifest'te `ACCESS_BACKGROUND_LOCATION` yoksa `false`. iOS'ta "her zaman" izni istenir
  /// ([rationale] yok sayılır). Önce [requestPermission] ile ön plan izni alınmış olmalıdır. Web'de `false`.
  Future<bool> requestBackgroundPermission({String? rationale}) async =>
      (await Pushizo._channel.invokeMethod<bool>('requestLocationBackgroundPermission', {'rationale': rationale})) ??
      false;

  /// [requestBackgroundPermission] ile aynı izin (iOS adlandırması): iOS'ta "her zaman", Android'de arka plan konum izni.
  Future<bool> requestAlwaysPermission() => requestBackgroundPermission();
}

/// Android teslimat güçlendirme (ADR-0092): bazı üreticilerin pil/otomatik başlatma yöneticisi arka plandaki uygulamayı
/// durdurduğu için bildirimler gecikir ya da gelmez. Bu API cihazdaki kısıtları okur ve kullanıcıyı ilgili ayar ekranına
/// götürür. Yalnızca Android'de etkilidir; iOS'ta ve web'de durum [PushizoDeliveryStatus.unsupported] döner,
/// [openSettings] ve [showGuidance] hiçbir şey yapmadan `false` döner (istisna atmaz).
class _Delivery {
  const _Delivery();

  /// Cihazın teslim durumu: üretici, ROM, pil muafiyeti, arka plan kısıtı, risk ve önerilen ayar ekranları.
  Future<PushizoDeliveryStatus> status() async => PushizoDeliveryStatus.fromMap(
        await Pushizo._channel.invokeMapMethod<Object?, Object?>('deliveryStatus'),
      );

  /// Hazır açıklama diyaloğu şimdi gösterilmeli mi: teslim riski var ve diyalog son [minIntervalDays] gün içinde
  /// gösterilmedi (verilmezse yerel SDK varsayılanı: 14 gün).
  Future<bool> shouldShowGuidance({int? minIntervalDays}) async =>
      (await Pushizo._channel.invokeMethod<bool>('deliveryShouldShowGuidance', {'minIntervalDays': minIntervalDays})) ??
      false;

  /// Ayar ekranını açar. [PushizoDeliverySetting.auto] duruma en uygun ekranı seçer; üreticiye özgü ekran bulunamazsa
  /// standart Android ekranına düşülür. Bir ekran açıldıysa `true`.
  Future<bool> openSettings({PushizoDeliverySetting setting = PushizoDeliverySetting.auto}) async =>
      (await Pushizo._channel.invokeMethod<bool>('deliveryOpenSettings', {'setting': setting.wire})) ?? false;

  /// Hazır açıklama diyaloğunu gösterir (22 dil; [message] verilirse SDK metni yerine o gösterilir). Kullanıcı kabul
  /// ederse [setting] ekranı açılır. Ayar ekranı açıldıysa `true`; kullanıcı vazgeçtiyse, ekran açılamadıysa ya da
  /// görünür bir Activity yoksa `false`. SDK diyaloğu kendiliğinden göstermez; uygun anı uygulama seçer
  /// ([shouldShowGuidance]).
  Future<bool> showGuidance({PushizoDeliverySetting setting = PushizoDeliverySetting.auto, String? message}) async =>
      (await Pushizo._channel.invokeMethod<bool>('deliveryShowGuidance', {'setting': setting.wire, 'message': message})) ??
      false;
}

/// Mobil reklam kimliği (GAID / IDFA; ADR-0037). SDK reklam kitaplığı içermez ve izin istemez: uygulama, kullanıcı
/// izin verdiyse kimliği kendisi alıp verir. Kimlik yalnızca `ads_personalization` rızası olan kullanıcılarda ve
/// SHA-256 özetiyle reklam kitlesine gönderilir.
class _Ads {
  const _Ads();

  /// Reklam kimliğini yazar; `null` veya sıfır kimlik sunucudaki kaydı siler. Web'de etkisizdir.
  Future<void> setAdvertisingId(String? id) => Pushizo._channel.invokeMethod<void>('setAdvertisingId', {'id': id});
}

class _Debug {
  const _Debug();

  Future<void> setLogLevel(PushizoLogLevel level) => Pushizo._channel.invokeMethod<void>('setLogLevel', {'level': level.name});
}
