/// Flutter web köprüsünün saf Dart katmanı: `herosignal_flutter` MethodChannel çağrılarını Web SDK'ya
/// (`window.HeroSignal`) eşler, argümanları doğrular, Web SDK hatalarını [PlatformException] kodlarına çevirir ve
/// Web SDK olaylarını Android/iOS köprüleriyle aynı biçimde `herosignal_flutter/events` akışına verir.
///
/// Bu dosya `dart:js_interop` / `package:web` içe aktarmaz; JavaScript erişimi [WebSdkFacade] arkasındadır. Böylece
/// eşleme `flutter test` (VM) ile sahte bir cephe üzerinden birim test edilir.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Web SDK'nın ön plan olayı: bildirim içeriği, senkron gösterim engelleme ve engellenen bildirimi sonradan gösterme.
abstract interface class WebForegroundEvent {
  /// Web SDK bildirim nesnesi (`title`, `body`, `deliveryId`, `messageId`, `data`).
  Map<Object?, Object?> get notification;

  /// Bildirimin service worker tarafından gösterilmesini engeller; Web SDK dinleyicisi içinde senkron çağrılmalıdır.
  void preventDefault();

  /// Engellenen bildirimi aynı içerikle gösterir (yalnızca bir kez).
  Future<void> display();
}

/// Web SDK'nın attığı hata: `name` (ör. `ContactValidationError`), API hatalarında `code` (ör. `HS_FORBIDDEN`) ve mesaj.
class WebSdkError implements Exception {
  const WebSdkError(this.message, {this.name, this.code});

  final String message;
  final String? name;
  final String? code;

  @override
  String toString() => 'WebSdkError(${name ?? 'Error'}${code == null ? '' : ', $code'}): $message';
}

/// Köprünün kullandığı Web SDK yüzeyi. Değerler JavaScript'ten Dart'a çevrilmiş ham biçimdedir (`Map`, `List`, `num`,
/// `String`, `bool`, `null`). Web SDK'nın attığı hatalar [WebSdkError] olarak fırlatılır.
abstract interface class WebSdkFacade {
  /// Sayfada `window.HeroSignal` var mı (HeroSignalSDK.js yüklendi mi).
  bool get isLoaded;

  Future<void> init(Map<String, Object?> options);
  Future<void> setConsentGiven(bool given);
  Future<void> login(String externalId, {String? identityHash, String? jwt});
  Future<void> updateUserJwt(String jwt);
  Future<void> logout();

  Future<void> addTags(Map<String, String> tags);
  Future<void> removeTags(List<String> keys);
  Future<Map<Object?, Object?>> getTags();
  Future<void> addAliases(Map<String, String> aliases);
  Future<void> removeAlias(String label);
  Future<void> addEmail(String email);
  Future<void> removeEmail(String email);
  Future<void> addSms(String phoneNumber);
  Future<void> removeSms(String phoneNumber);
  Future<void> setLanguage(String code);
  Future<String?> externalId();
  Future<String?> userId();
  Future<Map<Object?, Object?>> getPreferences();
  Future<void> setPreferences(List<Map<String, Object?>> preferences);

  /// `User.pushSubscription.state` (`permission` Web SDK izin durumu dizesidir).
  Future<Map<Object?, Object?>> pushSubscriptionState();
  Future<void> optIn();
  Future<void> optOut();

  /// `Notifications.permission`: `default`, `granted`, `denied` veya `unsupported`.
  Future<String> notificationPermission();
  Future<String> requestNotificationPermission();
  Future<void> clearAllNotifications();

  Future<void> sendEvent(String name, Map<String, Object?> properties, double? value);
  Future<void> setLogLevel(String level);

  Future<void> addTriggers(Map<String, String> triggers);
  Future<void> removeTriggers(List<String> keys);
  Future<void> clearTriggers();
  Future<Map<Object?, Object?>> getTriggers();
  Future<void> setScreen(String? name);
  Future<bool> inAppPaused();
  Future<void> setInAppPaused(bool paused);

  Future<Map<Object?, Object?>> inboxList({int? limit, String? cursor});
  Future<Map<Object?, Object?>> inboxMarkRead(String id);

  /// `{updated, unreadCount}`.
  Future<Map<Object?, Object?>> inboxMarkAllRead();
  Future<void> inboxArchive(String id);
  Future<num> inboxUnreadCount();

  Future<void> setLocationShared(bool shared);
  Future<bool> locationShared();
  Future<bool> requestLocationPermission(String? rationale);

  void addClickListener(void Function(Map<Object?, Object?> event) listener);
  void addForegroundListener(void Function(WebForegroundEvent event) listener);
  void addSubscriptionObserver(void Function(Map<Object?, Object?> state) observer);

  /// Web SDK izin gözlemcisi; yalnızca değişimde çağrılır (ilk durum gönderilmez).
  void addPermissionObserver(void Function(bool granted) observer);
  void addInAppClickListener(void Function(Map<Object?, Object?> event) listener);

  /// [listener] `willDisplay`, `didDisplay`, `willDismiss` veya `didDismiss` ve mesaj kimliğiyle çağrılır.
  void addInAppLifecycleListener(void Function(String event, String messageId) listener);
}

/// Web SDK hatasını köprünün hata koduna çevirir: API hatasının kodu aynen; geçersiz e-posta/telefon
/// `INVALID_ARGUMENT`; `init` veya gizlilik onayı eksikse `NOT_READY`; diğerleri [fallback].
String webErrorCode(WebSdkError error, {String fallback = 'HS_ERROR'}) {
  final code = error.code;
  if (code != null && code.isNotEmpty) return code;
  if (error.name == 'ContactValidationError') return 'INVALID_ARGUMENT';
  final message = error.message;
  if (message.contains('init önce çağrılmalı') || message.contains('Gizlilik onayı verilmedi')) return 'NOT_READY';
  return fallback;
}

/// Dart `initialize` argümanlarını Web SDK `init` seçeneklerine çevirir (`logLevel: none` → `silent`; `null` alanlar
/// gönderilmez, Web SDK varsayılanı geçerli olur).
Map<String, Object?> webInitOptions(Map<Object?, Object?> args) {
  final web = args['web'];
  final webOptions = web is Map ? web : const <Object?, Object?>{};
  final level = args['logLevel'];
  return {
    'appId': args['appId'],
    'apiUrl': ?(args['apiUrl'] as String?),
    'requiresPrivacyConsent': args['requiresPrivacyConsent'] == true,
    'logLevel': ?(level is String ? webLogLevel(level) : null),
    'serviceWorkerPath': ?(webOptions['serviceWorkerPath'] as String?),
    'serviceWorkerScope': ?(webOptions['serviceWorkerScope'] as String?),
    'allowLocalhostAsSecureOrigin': ?(webOptions['allowLocalhostAsSecureOrigin'] as bool?),
  };
}

/// Dart günlük seviyesi adını Web SDK seviyesine çevirir.
String webLogLevel(String level) => switch (level) {
      'none' => 'silent',
      'error' || 'warn' || 'info' || 'debug' => level,
      _ => 'warn',
    };

/// MethodChannel çağrılarını Web SDK'ya iletir; Web SDK olaylarını [eventController] üzerinden yayınlar.
class HeroSignalWebBridge {
  HeroSignalWebBridge(this._sdk, {required Future<Object?> Function(String method, Object? arguments) invokeDart, DateTime Function()? clock})
      : _invokeDart = invokeDart,
        _clock = clock ?? DateTime.now {
    _events = StreamController<Map<String, Object?>>.broadcast(onListen: _flushPendingClicks);
  }

  final WebSdkFacade _sdk;
  final Future<Object?> Function(String method, Object? arguments) _invokeDart;
  final DateTime Function() _clock;
  late final StreamController<Map<String, Object?>> _events;

  bool _listenersAttached = false;
  bool _foregroundHandlerEnabled = false;
  int _foregroundSeq = 0;

  /// Dart gösterim kararını beklerken engellenen ön plan olayları (Dart `display()` için), en fazla [_maxForegroundEvents].
  final Map<String, WebForegroundEvent> _foregroundEvents = {};

  /// Olay akışı dinlenmeden gelen bildirim tıklamaları (Android/iOS köprüleriyle aynı bekletme).
  final List<Map<String, Object?>> _pendingClicks = [];

  static const int _maxPendingClicks = 20;
  static const int _maxForegroundEvents = 32;

  /// Web'de karşılığı olmayan kanal yöntemleri ve ret gerekçeleri (`PLATFORM_NOT_SUPPORTED`).
  static const Map<String, String> unsupportedMethods = {
    'setupDefaultLiveActivity': "Live Activities yalnızca iOS'ta desteklenir",
    'startDefaultLiveActivity': "Live Activities yalnızca iOS'ta desteklenir",
    'removeNotification': "removeNotification yalnızca Android ve iOS'ta kullanılabilir",
    'removeGroupedNotifications': "removeGroupedNotifications yalnızca Android ve iOS'ta kullanılabilir",
    'inAppDisplayed': "Web'de in-app mesajları Web SDK çizer; Flutter çizim geri bildirimi kullanılmaz",
    'inAppButtonClicked': "Web'de in-app mesajları Web SDK çizer; Flutter çizim geri bildirimi kullanılmaz",
    'inAppDismissed': "Web'de in-app mesajları Web SDK çizer; Flutter çizim geri bildirimi kullanılmaz",
    'inAppClosed': "Web'de in-app mesajları Web SDK çizer; Flutter çizim geri bildirimi kullanılmaz",
  };

  /// Web'de desteklenen kanal yöntemleri.
  static const Set<String> supportedMethods = {
    'initialize', 'setConsentGiven', 'login', 'updateUserJwt', 'logout',
    'addTags', 'removeTags', 'getTags', 'addAliases', 'removeAlias', 'setLanguage', 'getExternalId', 'getUserId',
    'addEmail', 'removeEmail', 'addSms', 'removeSms', 'getPreferences', 'setPreferences',
    'getSubscriptionState', 'optIn', 'optOut', 'getPermission', 'requestPermission', 'clearAll',
    'setForegroundHandlerEnabled', 'displayForegroundNotification', 'sendEvent', 'setLogLevel',
    'addTriggers', 'removeTriggers', 'clearTriggers', 'getTriggers', 'setScreen', 'setInAppPaused', 'getInAppPaused',
    'inboxList', 'inboxMarkRead', 'inboxMarkAllRead', 'inboxArchive', 'inboxUnreadCount',
    'setLocationShared', 'getLocationShared', 'requestLocationPermission',
  };

  /// Bilinmeyen yöntem hatası yerine kullanılan, Web SDK yüklenmemiş durumu açıklaması.
  static const String notLoadedMessage =
      'HeroSignal Web SDK yüklenmedi (window.HeroSignal yok): web/index.html içine Flutter betiğinden önce '
      'HeroSignalSDK.js script etiketini ekleyin.';

  /// `herosignal_flutter/events` akışı (PluginEventChannel denetleyicisi).
  StreamController<Map<String, Object?>> get eventController => _events;

  /// Kanal çağrısını işler; sonuç Android/iOS köprüleriyle aynı biçimdedir.
  Future<Object?> handle(MethodCall call) async {
    final reason = unsupportedMethods[call.method];
    if (reason != null) throw PlatformException(code: 'PLATFORM_NOT_SUPPORTED', message: reason);
    if (!supportedMethods.contains(call.method)) {
      throw MissingPluginException('herosignal_flutter web: bilinmeyen çağrı ${call.method}');
    }
    if (!_sdk.isLoaded) throw PlatformException(code: 'NOT_READY', message: notLoadedMessage);
    final rawArgs = call.arguments;
    final args = rawArgs is Map ? rawArgs : const <Object?, Object?>{};
    try {
      return await _dispatch(call.method, args);
    } on WebSdkError catch (e) {
      throw PlatformException(code: webErrorCode(e, fallback: _fallbackCode(call.method)), message: e.message, details: e.name);
    }
  }

  /// Web SDK düz `Error` attığında yönteme göre kod: inbox/tercihlerde abonelik eksikliği `NOT_READY` (iOS köprüsüyle
  /// aynı), alias doğrulaması `INVALID_ARGUMENT`, diğerleri `HS_ERROR`.
  static String _fallbackCode(String method) {
    if (method.startsWith('inbox') || method == 'getPreferences' || method == 'setPreferences') return 'NOT_READY';
    if (method == 'addAliases' || method == 'removeAlias') return 'INVALID_ARGUMENT';
    return 'HS_ERROR';
  }

  Future<Object?> _dispatch(String method, Map<Object?, Object?> args) async {
    switch (method) {
      case 'initialize':
        _requireNonEmpty(args, 'appId');
        await _sdk.init(webInitOptions(args));
        _attachListeners();
        return null;
      case 'setConsentGiven':
        await _sdk.setConsentGiven(args['given'] == true);
        return null;
      case 'login':
        final externalId = _requireNonEmpty(args, 'externalId');
        await _sdk.login(externalId, identityHash: _optionalString(args, 'identityHash'), jwt: _optionalString(args, 'jwt'));
        return null;
      case 'updateUserJwt':
        // Boş belirteç Android/iOS köprüleriyle aynı biçimde INVALID_ARGUMENT döner.
        await _sdk.updateUserJwt(_requireNonEmpty(args, 'jwt'));
        return null;
      case 'logout':
        await _sdk.logout();
        return null;
      case 'addTags':
        await _sdk.addTags(_stringMap(args['tags']));
        return null;
      case 'removeTags':
        await _sdk.removeTags(_stringList(args['keys']));
        return null;
      case 'getTags':
        return _stringMap(await _sdk.getTags());
      case 'addAliases':
        await _sdk.addAliases(_stringMap(args['aliases']));
        return null;
      case 'removeAlias':
        await _sdk.removeAlias(_requireString(args, 'label'));
        return null;
      case 'setLanguage':
        await _sdk.setLanguage(_requireNonEmpty(args, 'code'));
        return null;
      case 'getExternalId':
        return _sdk.externalId();
      case 'getUserId':
        return _sdk.userId();
      case 'addEmail':
        await _sdk.addEmail(_requireString(args, 'email'));
        return null;
      case 'removeEmail':
        await _sdk.removeEmail(_requireString(args, 'email'));
        return null;
      case 'addSms':
        await _sdk.addSms(_requireString(args, 'phoneNumber'));
        return null;
      case 'removeSms':
        await _sdk.removeSms(_requireString(args, 'phoneNumber'));
        return null;
      case 'getPreferences':
        return mapPreferences(await _sdk.getPreferences());
      case 'setPreferences':
        return _setPreferences(args['preferences']);
      case 'getSubscriptionState':
        return mapSubscriptionState(await _sdk.pushSubscriptionState());
      case 'optIn':
        await _sdk.optIn();
        return null;
      case 'optOut':
        await _sdk.optOut();
        return null;
      case 'getPermission':
        return await _sdk.notificationPermission() == 'granted';
      case 'requestPermission':
        return await _sdk.requestNotificationPermission() == 'granted';
      case 'clearAll':
        await _sdk.clearAllNotifications();
        return null;
      case 'setForegroundHandlerEnabled':
        _foregroundHandlerEnabled = args['enabled'] == true;
        return null;
      case 'displayForegroundNotification':
        final eventId = args['eventId'];
        if (eventId is String) await _foregroundEvents.remove(eventId)?.display();
        return null;
      case 'sendEvent':
        final properties = args['properties'];
        final value = args['value'];
        await _sdk.sendEvent(
          _requireNonEmpty(args, 'name'),
          properties is Map ? properties.map((k, v) => MapEntry(k.toString(), v)) : const {},
          value is num ? value.toDouble() : null,
        );
        return null;
      case 'setLogLevel':
        final level = args['level'];
        await _sdk.setLogLevel(webLogLevel(level is String ? level : 'warn'));
        return null;
      case 'addTriggers':
        await _sdk.addTriggers(_stringMap(args['triggers']));
        return null;
      case 'removeTriggers':
        await _sdk.removeTriggers(_stringList(args['keys']));
        return null;
      case 'clearTriggers':
        await _sdk.clearTriggers();
        return null;
      case 'getTriggers':
        return _stringMap(await _sdk.getTriggers());
      case 'setScreen':
        await _sdk.setScreen(_optionalString(args, 'name'));
        return null;
      case 'setInAppPaused':
        await _sdk.setInAppPaused(args['paused'] == true);
        return null;
      case 'getInAppPaused':
        return _sdk.inAppPaused();
      case 'inboxList':
        final limit = args['limit'];
        return mapInboxPage(await _sdk.inboxList(limit: limit is num ? limit.toInt() : null, cursor: _optionalString(args, 'cursor')));
      case 'inboxMarkRead':
        return mapInboxItem(await _sdk.inboxMarkRead(_requireNonEmpty(args, 'id')));
      case 'inboxMarkAllRead':
        return _int((await _sdk.inboxMarkAllRead())['unreadCount']);
      case 'inboxArchive':
        await _sdk.inboxArchive(_requireNonEmpty(args, 'id'));
        return null;
      case 'inboxUnreadCount':
        return (await _sdk.inboxUnreadCount()).toInt();
      case 'setLocationShared':
        await _sdk.setLocationShared(args['shared'] == true);
        return null;
      case 'getLocationShared':
        return _sdk.locationShared();
      case 'requestLocationPermission':
        final rationale = _optionalString(args, 'rationale');
        return _sdk.requestLocationPermission(rationale == null || rationale.trim().isEmpty ? null : rationale);
    }
    throw MissingPluginException('herosignal_flutter web: bilinmeyen çağrı $method');
  }

  /// Web SDK tercih yazmasını çevrimdışı kuyruğa alır ve sonuç döndürmez. Android/iOS ile aynı sözleşme için önce güncel
  /// liste okunur (abonelik ve sahiplik kanıtı gerekir; yoksa `NOT_READY`), kategori/kanal sunucu kurallarıyla denetlenir,
  /// yazma kuyruğa verilir ve sunucunun yazma sonrası döndüreceği liste üretilir (Capacitor web eklentisiyle aynı kural).
  Future<Map<String, Object?>> _setPreferences(Object? raw) async {
    final inputs = (raw is List ? raw : const <Object?>[]).map((e) {
      if (e is! Map) throw PlatformException(code: 'INVALID_ARGUMENT', message: 'Tercih kaydı nesne olmalı');
      final category = e['category'];
      if (category is! String || category.trim().isEmpty || category.trim().length > 64) {
        throw PlatformException(code: 'INVALID_ARGUMENT', message: 'Geçersiz kategori anahtarı');
      }
      final channel = e['channel'];
      return (category: category.trim(), channel: channel is String ? channel : null, optedIn: e['optedIn'] == true);
    }).toList();
    if (inputs.isEmpty || inputs.length > 100) {
      throw PlatformException(code: 'INVALID_ARGUMENT', message: '1-100 tercih gerekli');
    }
    final current = mapPreferences(await _sdk.getPreferences());
    final categories = (current['categories'] as List).cast<Map<String, Object?>>();
    for (final input in inputs) {
      final category = categories.where((c) => c['key'] == input.category).firstOrNull;
      if (category == null) throw PlatformException(code: 'HS_NOT_FOUND', message: 'Kategori bulunamadı: ${input.category}');
      final channels = category['channels'] as List?;
      if (input.channel != null && channels != null && !channels.contains(input.channel)) {
        throw PlatformException(
          code: 'HS_VALIDATION_ERROR',
          message: "'${input.category}' kategorisi ${input.channel} kanalını kapsamıyor",
        );
      }
    }
    await _sdk.setPreferences([
      for (final p in inputs) {'category': p.category, 'optedIn': p.optedIn, 'channel': p.channel},
    ]);
    final now = _clock().millisecondsSinceEpoch;
    final preferences = (current['data'] as List).cast<Map<String, Object?>>().toList();
    for (final input in inputs) {
      final next = <String, Object?>{
        'category': input.category,
        'channel': input.channel,
        'optedIn': input.optedIn,
        'explicit': true,
        'source': 'sdk',
        'updatedAt': now,
      };
      final index = preferences.indexWhere((p) => p['category'] == input.category && p['channel'] == input.channel);
      if (index >= 0) {
        preferences[index] = next;
        continue;
      }
      final last = preferences.lastIndexWhere((p) => p['category'] == input.category);
      preferences.insert(last >= 0 ? last + 1 : preferences.length, next);
    }
    return {'data': preferences, 'categories': categories};
  }

  // --- Olaylar ---

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    _sdk.addClickListener((e) {
      final result = e['result'];
      final r = result is Map ? result : const <Object?, Object?>{};
      _emitClick({
        'type': 'click',
        'notification': mapNotification(e['notification']),
        'actionId': r['actionId'] as String?,
        'url': r['url'] as String?,
      });
    });
    _sdk.addForegroundListener(_onForeground);
    _sdk.addSubscriptionObserver((s) => _emit({'type': 'subscription', 'state': mapSubscriptionState(s)}));
    _sdk.addPermissionObserver((granted) => _emit({'type': 'permission', 'permission': granted}));
    _sdk.addInAppClickListener((e) {
      final message = e['message'];
      final result = e['result'];
      final r = result is Map ? result : const <Object?, Object?>{};
      _emit({
        'type': 'inAppClick',
        'messageId': (message is Map ? message['id'] as String? : null) ?? '',
        'actionId': r['actionId'] as String? ?? '',
        'url': r['url'] as String?,
      });
    });
    _sdk.addInAppLifecycleListener((event, messageId) {
      _emit({'type': 'inAppLifecycle', 'event': event, 'messageId': messageId});
    });
  }

  /// Ön plan bildirimi: bilgi olayı her zaman gönderilir. Dart işleyicisi kayıtlıysa Web SDK kararı senkron istediğinden
  /// gösterim önce engellenir, karar Dart'a sorulur; Dart `preventDefault()` çağırmadıysa veya çağrı başarısız olursa
  /// bildirim `display()` ile gösterilir (Android köprüsüyle aynı akış).
  void _onForeground(WebForegroundEvent event) {
    final notification = mapNotification(event.notification);
    _emit({'type': 'foreground', 'notification': notification});
    if (!_foregroundHandlerEnabled) return;
    event.preventDefault();
    final eventId = 'web-${++_foregroundSeq}';
    _foregroundEvents[eventId] = event;
    while (_foregroundEvents.length > _maxForegroundEvents) {
      _foregroundEvents.remove(_foregroundEvents.keys.first);
    }
    void displayNow() {
      final pending = _foregroundEvents.remove(eventId);
      if (pending != null) unawaited(pending.display().catchError((Object _) {}));
    }

    _invokeDart('foregroundWillDisplay', {'notification': notification, 'eventId': eventId}).then(
      (result) {
        if (result != true) displayNow();
      },
      onError: (Object _) => displayNow(),
    );
  }

  void _emit(Map<String, Object?> payload) {
    if (_events.hasListener) _events.add(payload);
  }

  /// Tıklama olayı: akış henüz dinlenmiyorsa kaybolmaması için dinleyici bağlanana kadar bekletilir.
  void _emitClick(Map<String, Object?> payload) {
    if (_events.hasListener) {
      _events.add(payload);
      return;
    }
    if (_pendingClicks.length >= _maxPendingClicks) _pendingClicks.removeAt(0);
    _pendingClicks.add(payload);
  }

  void _flushPendingClicks() {
    final pending = List<Map<String, Object?>>.of(_pendingClicks);
    _pendingClicks.clear();
    pending.forEach(_events.add);
  }

  // --- Eşlemeler (Android/iOS köprülerinin harita biçimi) ---

  /// Web SDK bildirimi → `HeroSignalNotification.fromMap` biçimi (boş başlık/gövde `null`; `data` değerleri metin).
  static Map<String, Object?> mapNotification(Object? raw) {
    final n = raw is Map ? raw : const <Object?, Object?>{};
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    return {
      'title': text(n['title']),
      'body': text(n['body']),
      'url': text(n['url']),
      'deliveryId': text(n['deliveryId']),
      'messageId': text(n['messageId']),
      'data': _stringMap(n['data']),
      'androidNotificationId': null,
    };
  }

  static Map<String, Object?> mapSubscriptionState(Map<Object?, Object?> s) => {
        'id': s['id'] as String?,
        'token': s['token'] as String?,
        'optedIn': s['optedIn'] == true,
        'permission': s['permission'] == 'granted',
      };

  static Map<String, Object?> mapInboxItem(Map<Object?, Object?> item) => {
        'id': item['id'],
        'messageId': item['messageId'],
        'title': item['title'],
        'body': item['body'],
        'url': item['url'],
        'imageUrl': item['imageUrl'],
        'data': _stringMap(item['data']),
        'read': item['read'] == true,
        'readAt': _millis(item['readAt']),
        'archivedAt': _millis(item['archivedAt']),
        'expiresAt': _millis(item['expiresAt']),
        'createdAt': _millis(item['createdAt']),
      };

  static Map<String, Object?> mapInboxPage(Map<Object?, Object?> page) => {
        'items': [
          for (final item in (page['items'] as List?) ?? const []) mapInboxItem((item as Map).cast<Object?, Object?>()),
        ],
        'unreadCount': _int(page['unreadCount']),
        'nextCursor': page['nextCursor'] as String?,
        'hasMore': page['hasMore'] == true,
      };

  /// Web SDK `{preferences, categories}` → köprü biçimi `{data, categories}` (zamanlar epoch ms).
  static Map<String, Object?> mapPreferences(Map<Object?, Object?> result) => {
        'data': [
          for (final p in (result['preferences'] as List?) ?? const [])
            if (p is Map)
              {
                'category': p['category'],
                'channel': p['channel'] as String?,
                'optedIn': p['optedIn'] == true,
                'explicit': p['explicit'] == true,
                'source': p['source'] as String?,
                'updatedAt': _millis(p['updatedAt']),
              },
        ],
        'categories': [
          for (final c in (result['categories'] as List?) ?? const [])
            if (c is Map)
              {
                'key': c['key'],
                'name': _stringMap(c['name']),
                'description': _stringMap(c['description']),
                'channels': (c['channels'] as List?)?.map((e) => e.toString()).toList(),
                'defaultOptedIn': c['defaultOptedIn'] == true,
              },
        ],
      };

  // --- Argüman yardımcıları ---

  static String _requireString(Map<Object?, Object?> args, String key) {
    final value = args[key];
    if (value is String) return value;
    throw PlatformException(code: 'INVALID_ARGUMENT', message: '$key gerekli');
  }

  static String _requireNonEmpty(Map<Object?, Object?> args, String key) {
    final value = _requireString(args, key);
    if (value.isEmpty) throw PlatformException(code: 'INVALID_ARGUMENT', message: '$key boş olamaz');
    return value;
  }

  static String? _optionalString(Map<Object?, Object?> args, String key) {
    final value = args[key];
    return value is String ? value : null;
  }

  /// Değerleri metne çevirir: tam sayı değerli `num` ondalıksız (`3`), nesne/liste JSON; `null` değerler atlanır.
  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        if (value != null) key.toString(): _text(value),
    };
  }

  static String _text(Object value) => switch (value) {
        String() => value,
        num() when value.isFinite && value == value.truncate() => value.toInt().toString(),
        num() || bool() => value.toString(),
        _ => jsonEncode(value),
      };

  static List<String> _stringList(Object? raw) => raw is List ? [for (final v in raw) if (v != null) v.toString()] : [];

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  static int? _millis(Object? value) {
    if (value is num) return value.toInt();
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.millisecondsSinceEpoch;
  }
}
