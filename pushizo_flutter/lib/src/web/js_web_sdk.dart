/// [WebSdkFacade]'in `dart:js_interop` uygulaması: sayfaya `PushizoSDK.js` ile yüklenen `window.Pushizo`
/// global'ine bağlanır. Yalnızca web derlemesinde kullanılır.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_bridge.dart';

/// `window.Pushizo` cephesi. Yöntem çağrıları `Promise.resolve().then(bağlıYöntem)` ile yapılır: Web SDK'nın
/// senkron attığı hatalar da (ör. `ContactValidationError`) Promise reddi olarak, `name`/`code`/`message` alanlarıyla
/// okunabilir hâlde gelir (dart2js ve dart2wasm'da aynı davranış).
class JsWebSdkFacade implements WebSdkFacade {
  /// [root] verilmezse `window` kullanılır (testlerde sahte global nesne verilebilir).
  JsWebSdkFacade([JSObject? root]) : _root = root ?? web.window;

  final JSObject _root;

  JSObject get _sdk {
    final sdk = _root.getProperty<JSAny?>('Pushizo'.toJS);
    if (sdk == null || !sdk.isA<JSObject>()) {
      throw const WebSdkError(PushizoWebBridge.notLoadedMessage, code: 'NOT_READY');
    }
    return sdk as JSObject;
  }

  JSObject _ns(String name) => _object(_sdk, name);

  JSObject get _pushSubscription => _object(_ns('User'), 'pushSubscription');

  static JSObject _object(JSObject target, String name) {
    final value = target.getProperty<JSAny?>(name.toJS);
    if (value == null || !value.isA<JSObject>()) {
      throw WebSdkError('Web SDK alanı bulunamadı: $name (PushizoSDK.js sürümü eski olabilir)');
    }
    return value as JSObject;
  }

  @override
  bool get isLoaded {
    final sdk = _root.getProperty<JSAny?>('Pushizo'.toJS);
    return sdk != null && sdk.isA<JSObject>();
  }

  /// [target] üzerindeki [method] yöntemini [args] ile çağırır; dönen Promise beklenir, ret [WebSdkError] olur.
  /// [undefinedAt] içindeki argüman sıraları JavaScript `undefined` olarak gider (aradaki isteğe bağlı argümanı atlamak
  /// için).
  static Future<JSAny?> _call(JSObject target, String method, [List<JSAny?> args = const [], Set<int> undefinedAt = const {}]) async {
    final fn = target.getProperty<JSAny?>(method.toJS);
    if (fn == null || !fn.isA<JSFunction>()) {
      throw WebSdkError('Web SDK yöntemi bulunamadı: $method (PushizoSDK.js sürümü eski olabilir)');
    }
    final JSFunction bound;
    if (undefinedAt.isEmpty) {
      bound = (fn as JSFunction).callMethodVarArgs<JSFunction>('bind'.toJS, [target, ...args]);
    } else {
      // `undefined` Dart'tan taşınamaz (dart2wasm'da `null` olur): argümanlar boşluklu bir diziye yazılır ve
      // `bind.apply(fn, dizi)` ile bağlanır; dizi boşlukları `undefined` okunur.
      final argv = JSArray<JSAny?>.withLength(args.length + 1)..setProperty(0.toJS, target);
      for (var i = 0; i < args.length; i++) {
        if (!undefinedAt.contains(i)) argv.setProperty((i + 1).toJS, args[i]);
      }
      bound = (fn as JSFunction).getProperty<JSFunction>('bind'.toJS).callMethod<JSFunction>('apply'.toJS, fn, argv);
    }
    final promise = globalContext.getProperty<JSObject>('Promise'.toJS);
    WebSdkError? failure;
    final settled = promise
        .callMethod<JSObject>('resolve'.toJS)
        .callMethod<JSObject>('then'.toJS, bound)
        .callMethod<JSPromise<JSAny?>>(
          'catch'.toJS,
          ((JSAny? reason) {
            failure = _describe(reason);
            return null;
          }).toJS,
        );
    final value = await settled.toDart;
    final error = failure;
    if (error != null) throw error;
    return value;
  }

  static WebSdkError _describe(JSAny? reason) {
    if (reason == null || !reason.isA<JSObject>()) {
      return WebSdkError(reason?.dartify()?.toString() ?? 'Web SDK isteği reddedildi');
    }
    final error = reason as JSObject;
    String? text(String key) {
      final value = error.getProperty<JSAny?>(key.toJS);
      return value != null && value.isA<JSString>() ? (value as JSString).toDart : null;
    }

    return WebSdkError(text('message') ?? 'Web SDK hatası', name: text('name'), code: text('code'));
  }

  static Map<Object?, Object?> _map(JSAny? value) {
    final dart = value.dartify();
    return dart is Map ? dart.cast<Object?, Object?>() : <Object?, Object?>{};
  }

  static String? _string(JSAny? value) => value != null && value.isA<JSString>() ? (value as JSString).toDart : null;

  static bool _bool(JSAny? value) => value != null && value.isA<JSBoolean>() && (value as JSBoolean).toDart;

  JSAny? _get(JSObject target, String name) => target.getProperty<JSAny?>(name.toJS);

  @override
  Future<void> init(Map<String, Object?> options) => _call(_sdk, 'init', [options.jsify()]);

  @override
  Future<void> setConsentGiven(bool given) => _call(_sdk, 'setConsentGiven', [given.toJS]);

  @override
  Future<void> login(String externalId, {String? identityHash, String? jwt, Map<String, Object?>? profile}) {
    // Kanıt yoksa ikinci argüman hiç verilmez (Web SDK `typeof proof === 'object'` denetimi null'ı kabul etmez);
    // profil varsa kanıt yerine boş nesne gider (üçüncü argümanın yeri korunur).
    final proof = <String, Object?>{'identityHash': ?identityHash, 'jwt': ?jwt};
    final hasProfile = profile != null && profile.isNotEmpty;
    return _call(_sdk, 'login', [
      externalId.toJS,
      if (proof.isNotEmpty || hasProfile) proof.jsify(),
      if (hasProfile) profile.jsify(),
    ]);
  }

  @override
  Future<void> updateUserJwt(String jwt) => _call(_sdk, 'updateUserJwt', [jwt.toJS]);

  @override
  Future<void> logout() => _call(_sdk, 'logout');

  @override
  Future<void> addTags(Map<String, String> tags) => _call(_ns('User'), 'addTags', [tags.jsify()]);

  @override
  Future<void> removeTags(List<String> keys) => _call(_ns('User'), 'removeTags', [keys.jsify()]);

  @override
  Future<Map<Object?, Object?>> getTags() async => _map(await _call(_ns('User'), 'getTags'));

  @override
  Future<void> addAliases(Map<String, String> aliases) => _call(_ns('User'), 'addAliases', [aliases.jsify()]);

  @override
  Future<void> removeAlias(String label) => _call(_ns('User'), 'removeAlias', [label.toJS]);

  @override
  Future<void> addEmail(String email) => _call(_ns('User'), 'addEmail', [email.toJS]);

  @override
  Future<void> removeEmail(String email) => _call(_ns('User'), 'removeEmail', [email.toJS]);

  @override
  Future<void> addSms(String phoneNumber) => _call(_ns('User'), 'addSms', [phoneNumber.toJS]);

  @override
  Future<void> removeSms(String phoneNumber) => _call(_ns('User'), 'removeSms', [phoneNumber.toJS]);

  @override
  Future<void> setLanguage(String code) => _call(_ns('User'), 'setLanguage', [code.toJS]);

  @override
  Future<void> setProperty(String key, Object? value) => _call(_ns('User'), 'setProperty', [key.toJS, value.jsify()]);

  @override
  Future<String?> externalId() async => _string(_get(_ns('User'), 'externalId'));

  @override
  Future<String?> userId() async => _string(_get(_ns('User'), 'id'));

  @override
  Future<Map<Object?, Object?>> getPreferences() async => _map(await _call(_ns('User'), 'getPreferences'));

  @override
  Future<void> setPreferences(List<Map<String, Object?>> preferences) =>
      _call(_ns('User'), 'setPreferences', [preferences.jsify()]);

  @override
  Future<void> setAdsPersonalizationConsent(bool granted) =>
      _call(_ns('User'), 'setAdsPersonalizationConsent', [granted.toJS]);

  @override
  Future<Map<Object?, Object?>> pushSubscriptionState() async => _map(_get(_pushSubscription, 'state'));

  @override
  Future<void> optIn() => _call(_pushSubscription, 'optIn');

  @override
  Future<void> optOut() => _call(_pushSubscription, 'optOut');

  @override
  Future<String> notificationPermission() async => _string(_get(_ns('Notifications'), 'permission')) ?? 'unsupported';

  @override
  Future<String> requestNotificationPermission() async =>
      _string(await _call(_ns('Notifications'), 'requestPermission')) ?? 'unsupported';

  @override
  Future<void> clearAllNotifications() => _call(_ns('Notifications'), 'clearAll');

  @override
  Future<bool> setBadgeCount(int count) async => _bool(await _call(_ns('Notifications'), 'setBadgeCount', [count.toJS]));

  @override
  Future<void> sendEvent(String name, Map<String, Object?> properties, double? value, {String? eventId}) =>
      _call(
        _ns('Session'),
        'sendEvent',
        [
          name.toJS,
          properties.jsify(),
          // `eventId` dördüncü argümandadır; değer yoksa yeri `undefined` ile korunur.
          if (value != null) value.toJS else if (eventId != null) null,
          if (eventId != null) {'eventId': eventId}.jsify(),
        ],
        {if (value == null && eventId != null) 2},
      );

  @override
  Future<void> setLogLevel(String level) => _call(_ns('Debug'), 'setLogLevel', [level.toJS]);

  @override
  Future<void> addTriggers(Map<String, String> triggers) => _call(_ns('InAppMessages'), 'addTriggers', [triggers.jsify()]);

  @override
  Future<void> removeTriggers(List<String> keys) => _call(_ns('InAppMessages'), 'removeTriggers', [keys.jsify()]);

  @override
  Future<void> clearTriggers() => _call(_ns('InAppMessages'), 'clearTriggers');

  @override
  Future<Map<Object?, Object?>> getTriggers() async => _map(await _call(_ns('InAppMessages'), 'getTriggers'));

  @override
  Future<void> setScreen(String? name) => _call(_ns('InAppMessages'), 'setScreen', [name?.toJS]);

  @override
  Future<bool> inAppPaused() async => _bool(_get(_ns('InAppMessages'), 'paused'));

  @override
  Future<void> setInAppPaused(bool paused) async => _ns('InAppMessages').setProperty('paused'.toJS, paused.toJS);

  @override
  Future<Map<Object?, Object?>> inboxList({int? limit, String? cursor}) async {
    final options = <String, Object?>{'limit': ?limit, 'cursor': ?cursor};
    return _map(await _call(_ns('Inbox'), 'list', [options.jsify()]));
  }

  @override
  Future<Map<Object?, Object?>> inboxMarkRead(String id) async => _map(await _call(_ns('Inbox'), 'markRead', [id.toJS]));

  @override
  Future<Map<Object?, Object?>> inboxMarkAllRead() async => _map(await _call(_ns('Inbox'), 'markAllRead'));

  @override
  Future<void> inboxArchive(String id) => _call(_ns('Inbox'), 'archive', [id.toJS]);

  @override
  Future<num> inboxUnreadCount() async {
    final value = await _call(_ns('Inbox'), 'unreadCount');
    return value != null && value.isA<JSNumber>() ? (value as JSNumber).toDartDouble : 0;
  }

  @override
  Future<Map<Object?, Object?>> contentCardsList({int? limit}) async =>
      _map(await _call(_ns('ContentCards'), 'list', [if (limit != null) limit.toJS]));

  @override
  Future<Map<Object?, Object?>> contentCardEvent(String id, String event) async {
    final method = switch (event) { 'impression' => 'logImpression', 'click' => 'logClick', _ => 'dismiss' };
    return _map(await _call(_ns('ContentCards'), method, [id.toJS]));
  }

  @override
  Future<void> setLocationShared(bool shared) => _call(_ns('Location'), 'setShared', [shared.toJS]);

  @override
  Future<bool> locationShared() async => _bool(_get(_ns('Location'), 'isShared'));

  @override
  Future<bool> requestLocationPermission(String? rationale) async =>
      _bool(await _call(_ns('Location'), 'requestPermission', [if (rationale != null) rationale.toJS]));

  @override
  Future<bool> locationPermissionGranted() async => _bool(_get(_ns('Location'), 'permissionGranted'));

  static num _num(JSAny? value) => value != null && value.isA<JSNumber>() ? (value as JSNumber).toDartDouble : 0;

  @override
  Future<Map<Object?, Object?>> chatConfig(bool refresh) async => _map(await _call(_ns('Chat'), 'getConfig', [refresh.toJS]));

  @override
  Future<Map<Object?, Object?>> chatConversation() async {
    final conversation = await _call(_ns('Chat'), 'getConversation');
    return {
      'conversation': conversation != null && conversation.isA<JSObject>() ? _map(conversation) : null,
      'unread_count': _num(_get(_ns('Chat'), 'unreadCount')),
    };
  }

  @override
  Future<num> chatUnreadCount() async => _num(_get(_ns('Chat'), 'unreadCount'));

  @override
  Future<num> chatRefreshUnreadCount() async => _num(await _call(_ns('Chat'), 'getUnreadCount'));

  @override
  Future<void> chatSetTyping(bool typing) => _call(_ns('Chat'), 'setTyping', [typing.toJS]);

  @override
  Future<String> chatAttachmentUrl(String attachmentId, bool download) async =>
      _string(await _call(_ns('Chat'), 'attachmentUrl', [attachmentId.toJS, download.toJS])) ?? '';

  @override
  Future<void> chatShow() => _call(_ns('Chat'), 'show', [{'open': true}.jsify()]);

  @override
  Future<void> chatHide() => _call(_ns('Chat'), 'hide');

  /// `JSON.stringify(value)`; Dart'a dönüşte sayı/nesne türleri sunucu JSON'u ile aynı kalır.
  static String _stringify(JSAny? value) =>
      globalContext.getProperty<JSObject>('JSON'.toJS).callMethod<JSString>('stringify'.toJS, value).toDart;

  @override
  Future<List<String>> placementsList(String key, int limit) async {
    final result = await _call(_ns('Placements'), 'list', [key.toJS, {'limit': limit}.jsify()]);
    if (result == null || !result.isA<JSArray>()) return const [];
    return [for (final message in (result as JSArray<JSAny?>).toDart) _stringify(message)];
  }

  @override
  Future<void> placementsReport(String method, String messageJson, String? buttonId) {
    final message = globalContext.getProperty<JSObject>('JSON'.toJS).callMethod<JSAny?>('parse'.toJS, messageJson.toJS);
    return _call(_ns('Placements'), method, [message, if (buttonId != null) buttonId.toJS]);
  }

  @override
  Future<bool> featureFlagsRefresh() async {
    // Web SDK `refresh` sonuç döndürmez; gözlemci yalnızca değerler başarıyla yazıldığında tetiklenir.
    var refreshed = false;
    final flags = _ns('FeatureFlags');
    final observer = (() {
      refreshed = true;
    }).toJS;
    final unsubscribe = flags.callMethod<JSAny?>('addObserver'.toJS, observer);
    try {
      await _call(flags, 'refresh');
    } finally {
      // Gözlemci `removeObserver` ile kaldırılır; eski Web SDK sürümlerinde `addObserver`'ın döndürdüğü işlevle.
      if (_hasMethod(flags, 'removeObserver')) {
        flags.callMethod<JSAny?>('removeObserver'.toJS, observer);
      } else if (unsubscribe != null && unsubscribe.isA<JSFunction>()) {
        (unsubscribe as JSFunction).callAsFunction();
      }
    }
    return refreshed;
  }

  @override
  Future<bool> featureFlagEnabled(String key, bool defaultValue) async =>
      _bool(await _call(_ns('FeatureFlags'), 'isEnabled', [key.toJS, defaultValue.toJS]));

  @override
  Future<String?> featureFlagValueJson(String key) async {
    final value = await _call(_ns('FeatureFlags'), 'getValue', [key.toJS]);
    if (value == null) return null;
    return _stringify(JSObject()..setProperty('value'.toJS, value));
  }

  @override
  void addClickListener(void Function(Map<Object?, Object?> event) listener) {
    _ns('Notifications').callMethod<JSAny?>('addClickListener'.toJS, ((JSAny? e) => listener(_map(e))).toJS);
  }

  @override
  void addForegroundListener(void Function(WebForegroundEvent event) listener) {
    _ns('Notifications').callMethod<JSAny?>(
      'addForegroundLifecycleListener'.toJS,
      ((JSObject e) => listener(_JsForegroundEvent(e))).toJS,
    );
  }

  @override
  void addSubscriptionObserver(void Function(Map<Object?, Object?> state) observer) {
    _pushSubscription.callMethod<JSAny?>('addObserver'.toJS, ((JSAny? s) => observer(_map(s))).toJS);
  }

  @override
  void addPermissionObserver(void Function(bool granted) observer) {
    _ns('Notifications').callMethod<JSAny?>(
      'addPermissionObserver'.toJS,
      ((JSAny? e) => observer(_map(e)['permission'] == true)).toJS,
    );
  }

  @override
  void addInAppClickListener(void Function(Map<Object?, Object?> event) listener) {
    _ns('InAppMessages').callMethod<JSAny?>('addClickListener'.toJS, ((JSAny? e) => listener(_map(e))).toJS);
  }

  @override
  void addInAppLifecycleListener(void Function(String event, String messageId) listener) {
    final callbacks = JSObject();
    for (final event in const ['willDisplay', 'didDisplay', 'willDismiss', 'didDismiss']) {
      callbacks.setProperty(
        event.toJS,
        ((JSAny? e) {
          final message = _map(e)['message'];
          final id = message is Map ? message['id'] : null;
          if (id is String) listener(event, id);
        }).toJS,
      );
    }
    _ns('InAppMessages').callMethod<JSAny?>('addLifecycleListener'.toJS, callbacks);
  }

  static bool _hasMethod(JSObject target, String name) {
    final fn = target.getProperty<JSAny?>(name.toJS);
    return fn != null && fn.isA<JSFunction>();
  }

  @override
  void addFeatureFlagObserver(void Function() observer) {
    _ns('FeatureFlags').callMethod<JSAny?>('addObserver'.toJS, (() => observer()).toJS);
  }

  @override
  void addInboxObserver(void Function(Map<Object?, Object?> event) observer) {
    // Eski PushizoSDK.js sürümlerinde kutu gözlemcisi yoktur; başlatma bu yüzden başarısız olmamalıdır.
    final inbox = _ns('Inbox');
    if (!_hasMethod(inbox, 'addObserver')) return;
    inbox.callMethod<JSAny?>('addObserver'.toJS, ((JSAny? e) => observer(_map(e))).toJS);
  }
}

/// Web SDK `ForegroundLifecycleEvent` sarmalayıcısı; `preventDefault` dinleyici içinde senkron çağrılır.
class _JsForegroundEvent implements WebForegroundEvent {
  _JsForegroundEvent(this._event);

  final JSObject _event;

  @override
  Map<Object?, Object?> get notification => JsWebSdkFacade._map(_event.getProperty<JSAny?>('notification'.toJS));

  @override
  void preventDefault() => _event.callMethod<JSAny?>('preventDefault'.toJS);

  @override
  Future<void> display() => JsWebSdkFacade._call(_event, 'display');
}
