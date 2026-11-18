@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pushizo_flutter/src/web/js_web_sdk.dart';
import 'package:pushizo_flutter/src/web/web_bridge.dart';

/// `dart:js_interop` katmanı (`JsWebSdkFacade`) gerçek bir tarayıcıda, Web SDK global API'sini taklit eden sahte bir
/// `Pushizo` nesnesine karşı sınanır: `flutter test --platform chrome test/web_js_facade_test.dart`.
const _fakeSdk = r'''
(function () {
  class ContactValidationError extends Error {
    constructor() { super('Geçersiz e-posta adresi (ör. ad@pushizo.com).'); this.name = 'ContactValidationError'; }
  }
  const calls = [];
  const arg = (v) => (v === undefined ? 'undefined' : v);
  const sdk = {
    calls,
    inited: false,
    init(options) { calls.push(['init', options]); sdk.inited = true; return Promise.resolve(); },
    login(externalId, proof, profile) {
      calls.push(profile === undefined ? ['login', externalId, arg(proof)] : ['login', externalId, arg(proof), profile]);
      if (externalId === 'forbidden') {
        const error = new Error('Bu işlem için yetki yok');
        error.name = 'ApiError';
        error.code = 'HS_FORBIDDEN';
        return Promise.reject(error);
      }
      return Promise.resolve();
    },
    User: {
      addEmail(email) { throw new ContactValidationError(); },
      getTags() { return { plan: 'pro', n: 3 }; },
      setAdsPersonalizationConsent(granted) { calls.push(['setAdsPersonalizationConsent', granted]); },
      setProperty(key, value) { calls.push(['setProperty', key, value === null ? 'null' : arg(value)]); },
      get externalId() { return 'u1'; },
      id: null,
      pushSubscription: {
        get state() { return { id: 'sub_1', token: null, optedIn: true, permission: 'granted' }; },
        addObserver(cb) { sdk.subscription = cb; },
      },
    },
    Notifications: {
      permission: 'default',
      requestPermission() { return Promise.resolve('granted'); },
      addClickListener(cb) { sdk.click = cb; },
      addForegroundLifecycleListener(cb) { sdk.foreground = cb; },
      addPermissionObserver(cb) { sdk.permission = cb; },
      setBadgeCount(count) { calls.push(['setBadgeCount', count]); return Promise.resolve(count < 100); },
    },
    Session: {
      sendEvent(name, properties, value, options) {
        calls.push(options === undefined ? ['sendEvent', name, properties, arg(value)] : ['sendEvent', name, properties, arg(value), options]);
      },
    },
    InAppMessages: {
      paused: false,
      addClickListener(cb) { sdk.inAppClick = cb; },
      addLifecycleListener(listener) { sdk.lifecycle = listener; },
    },
    Inbox: { unreadCount() { return Promise.resolve(7); }, addObserver(cb) { sdk.inbox = cb; } },
    Chat: {
      unread: 2,
      get unreadCount() { return this.unread; },
      getUnreadCount() { this.unread = 5; return Promise.resolve(5); },
      getConfig(refresh) { calls.push(['chatGetConfig', arg(refresh)]); return Promise.resolve({ enabled: true, attachments: { enabled: true, max_bytes: 1024, types: ['image/png'] } }); },
      getConversation() { return Promise.resolve(sdk.conversation === undefined ? null : sdk.conversation); },
      setTyping(typing) { calls.push(['chatSetTyping', typing]); },
      attachmentUrl(id, download) { return 'https://api.pushizo.com/chat/attachments/' + id + (download ? '?download=true' : ''); },
      show(options) { calls.push(['chatShow', arg(options)]); return Promise.resolve(); },
      hide() { calls.push(['chatHide']); },
    },
    Location: {
      shared: false,
      setShared(shared) {
        if (!sdk.inited) throw new Error('Pushizo.init önce çağrılmalı.');
        this.shared = shared;
      },
      get isShared() { return this.shared; },
      granted: false,
      get permissionGranted() { return this.granted; },
      requestPermission(rationale) { calls.push(['requestPermission', arg(rationale)]); return Promise.resolve(true); },
    },
    Placements: {
      list(key, options) {
        calls.push(['placementsList', key, arg(options)]);
        return Promise.resolve([{ id: 'm1', priority: 1, variant_id: 'var_b', display: { layout: 'modal', blocks: [] } }]);
      },
      reportImpression(message) { calls.push(['reportImpression', message.id, arg(message.variant_id)]); },
      reportClick(message, buttonId) { calls.push(['reportClick', message.id, buttonId]); },
      reportDismiss(message) { calls.push(['reportDismiss', message.id]); },
    },
    FeatureFlags: {
      listeners: new Set(),
      refreshOk: true,
      refresh() {
        calls.push(['flagsRefresh']);
        if (this.refreshOk) this.listeners.forEach((l) => l());
        return Promise.resolve();
      },
      isEnabled(key, defaultValue) { calls.push(['isEnabled', key, arg(defaultValue)]); return key === 'on'; },
      getValue(key, defaultValue) {
        calls.push(['getValue', key, arg(defaultValue)]);
        return { n: 3, obj: { max: 3, tags: ['a', 2.5] }, s: 'Yeni', f: false }[key];
      },
      removed: 0,
      addObserver(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener); },
      removeObserver(listener) { this.removed += 1; this.listeners.delete(listener); },
    },
  };
  return sdk;
})()
''';

void main() {
  late JSObject root;
  late JSObject fake;
  late JsWebSdkFacade facade;

  setUp(() {
    fake = globalContext.callMethod<JSObject>('eval'.toJS, _fakeSdk.toJS);
    root = JSObject()..setProperty('Pushizo'.toJS, fake);
    facade = JsWebSdkFacade(root);
  });

  List<Object?> calls() => (fake.getProperty<JSAny?>('calls'.toJS).dartify()! as List).toList();

  test('Pushizo global yoksa yüklenmemiş sayılır', () async {
    final empty = JsWebSdkFacade(JSObject());
    expect(empty.isLoaded, isFalse);
    expect(facade.isLoaded, isTrue);
    // `window.Pushizo` erişimi senkron hata verir (köprü çağrıdan önce `isLoaded` denetler).
    expect(() => empty.logout(), throwsA(isA<WebSdkError>().having((e) => e.code, 'code', 'NOT_READY')));
  });

  test('init ve login argümanları; kanıt yoksa ikinci argüman verilmez', () async {
    await facade.init({'appId': 'app_1', 'requiresPrivacyConsent': false});
    await facade.login('u1');
    await facade.login('u2', jwt: 'h.p.s');
    final recorded = calls();
    expect(recorded[0], ['init', {'appId': 'app_1', 'requiresPrivacyConsent': false}]);
    expect(recorded[1], ['login', 'u1', 'undefined']);
    expect(recorded[2], ['login', 'u2', {'jwt': 'h.p.s'}]);
  });

  test('Promise reddi ve senkron hata name/code/message ile WebSdkError olur', () async {
    await expectLater(
      facade.login('forbidden'),
      throwsA(isA<WebSdkError>()
          .having((e) => e.code, 'code', 'HS_FORBIDDEN')
          .having((e) => e.name, 'name', 'ApiError')
          .having((e) => e.message, 'message', 'Bu işlem için yetki yok')),
    );
    await expectLater(
      facade.addEmail('x'),
      throwsA(isA<WebSdkError>().having((e) => e.name, 'name', 'ContactValidationError')),
    );
    await expectLater(
      facade.setLocationShared(true),
      throwsA(isA<WebSdkError>().having((e) => webErrorCode(e), 'kod', 'NOT_READY')),
    );
  });

  test('reklam kişiselleştirme rızası User.setAdsPersonalizationConsent ile yazılır', () async {
    await facade.setAdsPersonalizationConsent(true);
    await facade.setAdsPersonalizationConsent(false);
    expect(calls(), [
      ['setAdsPersonalizationConsent', true],
      ['setAdsPersonalizationConsent', false],
    ]);
  });

  test('getter ve dönüş değerleri Dart değerlerine çevrilir', () async {
    expect(await facade.getTags(), {'plan': 'pro', 'n': 3});
    expect(await facade.externalId(), 'u1');
    expect(await facade.userId(), isNull);
    expect(await facade.pushSubscriptionState(), {'id': 'sub_1', 'token': null, 'optedIn': true, 'permission': 'granted'});
    expect(await facade.notificationPermission(), 'default');
    expect(await facade.requestNotificationPermission(), 'granted');
    expect(await facade.inboxUnreadCount(), 7);
    expect(await facade.inAppPaused(), isFalse);
    await facade.setInAppPaused(true);
    expect(await facade.inAppPaused(), isTrue);
    await facade.sendEvent('purchase', {'sku': 'A1'}, null);
    expect(calls().last, ['sendEvent', 'purchase', {'sku': 'A1'}, 'undefined']);
  });

  test('konum: setShared, isShared ve requestPermission', () async {
    await facade.init({'appId': 'app_1'});
    await facade.setLocationShared(true);
    expect(await facade.locationShared(), isTrue);
    expect(await facade.requestLocationPermission(null), isTrue);
    expect(await facade.requestLocationPermission('Yakındaki mağazalar'), isTrue);
    expect(calls().sublist(1), [
      ['requestPermission', 'undefined'],
      ['requestPermission', 'Yakındaki mağazalar'],
    ]);
  });

  test('özellik bayrakları: refresh gözlemciyle doğrulanır, değerler JSON metni olarak döner', () async {
    expect(await facade.featureFlagsRefresh(), isTrue);
    final flags = fake.getProperty<JSObject>('FeatureFlags'.toJS);
    flags.setProperty('refreshOk'.toJS, false.toJS);
    expect(await facade.featureFlagsRefresh(), isFalse);
    expect(flags.getProperty<JSObject>('listeners'.toJS).getProperty<JSNumber>('size'.toJS).toDartInt, 0, reason: 'gözlemci kaldırılır');
    expect(flags.getProperty<JSNumber>('removed'.toJS).toDartInt, 2, reason: 'FeatureFlags.removeObserver kullanılır');
    // Eski Web SDK (removeObserver yok): addObserver'ın döndürdüğü işlevle kaldırılır.
    flags.setProperty('removeObserver'.toJS, null);
    flags.setProperty('refreshOk'.toJS, true.toJS);
    expect(await facade.featureFlagsRefresh(), isTrue);
    expect(flags.getProperty<JSObject>('listeners'.toJS).getProperty<JSNumber>('size'.toJS).toDartInt, 0);
    flags.setProperty('refreshOk'.toJS, false.toJS);
    expect(await facade.featureFlagsRefresh(), isFalse);
    expect(await facade.featureFlagEnabled('on', false), isTrue);
    expect(await facade.featureFlagEnabled('off', true), isFalse);
    expect(await facade.featureFlagValueJson('n'), '{"value":3}');
    expect(await facade.featureFlagValueJson('obj'), '{"value":{"max":3,"tags":["a",2.5]}}');
    expect(await facade.featureFlagValueJson('s'), '{"value":"Yeni"}');
    expect(await facade.featureFlagValueJson('f'), '{"value":false}');
    expect(await facade.featureFlagValueJson('missing'), isNull);
    expect(calls().sublist(0, 6), [
      ['flagsRefresh'],
      ['flagsRefresh'],
      ['flagsRefresh'],
      ['flagsRefresh'],
      ['isEnabled', 'on', false],
      ['isEnabled', 'off', true],
    ]);
  });

  test('yerleşimler: liste JSON metinleri, rapor çağrıları JSON\'dan nesneye', () async {
    final messages = await facade.placementsList('home_top', 2);
    expect(messages, ['{"id":"m1","priority":1,"variant_id":"var_b","display":{"layout":"modal","blocks":[]}}']);
    await facade.placementsReport('reportImpression', messages.single, null);
    await facade.placementsReport('reportClick', messages.single, 'go');
    await facade.placementsReport('reportDismiss', messages.single, null);
    expect(calls(), [
      ['placementsList', 'home_top', {'limit': 2}],
      ['reportImpression', 'm1', 'var_b'],
      ['reportClick', 'm1', 'go'],
      ['reportDismiss', 'm1'],
    ]);
  });

  test('dinleyiciler: tıklama, ön plan (senkron preventDefault), izin ve in-app yaşam döngüsü', () async {
    final clicks = <Map<Object?, Object?>>[];
    final permissions = <bool>[];
    final lifecycle = <String>[];
    facade.addClickListener(clicks.add);
    facade.addPermissionObserver(permissions.add);
    facade.addInAppLifecycleListener((event, id) => lifecycle.add('$event:$id'));
    facade.addForegroundListener((event) {
      expect(event.notification['title'], 'Ön plan');
      event.preventDefault();
    });

    fake.callMethod<JSAny?>('click'.toJS, {
      'notification': {'title': 'T', 'body': 'B', 'data': {'k': 'v'}},
      'result': {'actionId': 'open'},
    }.jsify());
    fake.callMethod<JSAny?>('permission'.toJS, {'permission': true, 'state': 'granted'}.jsify());
    fake.getProperty<JSObject>('lifecycle'.toJS).callMethod<JSAny?>('didDisplay'.toJS, {'message': {'id': 'm1'}}.jsify());
    final event = globalContext.callMethod<JSObject>(
      'eval'.toJS,
      "({ prevented: false, notification: { title: 'Ön plan', body: '', data: {} }, preventDefault() { this.prevented = true; }, display() { return Promise.resolve(); } })"
          .toJS,
    );
    fake.callMethod<JSAny?>('foreground'.toJS, event);

    expect(clicks.single['result'], {'actionId': 'open'});
    expect(permissions, [true]);
    expect(lifecycle, ['didDisplay:m1']);
    expect(event.getProperty<JSBoolean>('prevented'.toJS).toDart, isTrue);
  });

  test('profille login: profil üçüncü argümandır; kanıt yoksa boş nesne gider', () async {
    await facade.login('u1', profile: {'email': 'ali@pushizo.com', 'tags': {'plan': 'pro'}});
    await facade.login('u2', identityHash: 'h', jwt: 'h.p.s', profile: {'sms': '+905321234567'});
    await facade.login('u3', profile: const {});
    expect(calls(), [
      ['login', 'u1', <Object?, Object?>{}, {'email': 'ali@pushizo.com', 'tags': {'plan': 'pro'}}],
      ['login', 'u2', {'identityHash': 'h', 'jwt': 'h.p.s'}, {'sms': '+905321234567'}],
      ['login', 'u3', 'undefined'],
    ]);
  });

  test('setProperty: değer türüyle gider; null JavaScript null olur', () async {
    await facade.setProperty('plan', 'pro');
    await facade.setProperty('level', 7);
    await facade.setProperty('prefs', {'dark': true, 'tags': ['a', 2.5]});
    await facade.setProperty('plan', null);
    expect(calls(), [
      ['setProperty', 'plan', 'pro'],
      ['setProperty', 'level', 7],
      ['setProperty', 'prefs', {'dark': true, 'tags': ['a', 2.5]}],
      ['setProperty', 'plan', 'null'],
    ]);
  });

  test('rozet ve konum izni durumu Web SDK değerleridir', () async {
    expect(await facade.setBadgeCount(3), isTrue);
    expect(await facade.setBadgeCount(100), isFalse);
    expect(calls(), [
      ['setBadgeCount', 3],
      ['setBadgeCount', 100],
    ]);
    expect(await facade.locationPermissionGranted(), isFalse);
    fake.getProperty<JSObject>('Location'.toJS).setProperty('granted'.toJS, true.toJS);
    expect(await facade.locationPermissionGranted(), isTrue);
  });

  test('sendEvent eventId dördüncü argümandadır; değer yoksa yeri undefined ile korunur', () async {
    await facade.sendEvent('purchase', {'sku': 'A1'}, 49.9, eventId: 'order-1042');
    await facade.sendEvent('viewed', const {}, null, eventId: 'view-0001');
    await facade.sendEvent('plain', const {}, 2);
    expect(calls(), [
      ['sendEvent', 'purchase', {'sku': 'A1'}, 49.9, {'eventId': 'order-1042'}],
      ['sendEvent', 'viewed', <Object?, Object?>{}, 'undefined', {'eventId': 'view-0001'}],
      ['sendEvent', 'plain', <Object?, Object?>{}, 2],
    ]);
  });

  test('bayrak ve kutu gözlemcileri; eski Web SDK\'da kutu gözlemcisi yoksa hata vermez', () async {
    var flagChanges = 0;
    final inbox = <Map<Object?, Object?>>[];
    facade.addFeatureFlagObserver(() => flagChanges++);
    facade.addInboxObserver(inbox.add);
    await facade.featureFlagsRefresh();
    fake.callMethod<JSAny?>('inbox'.toJS, {'type': 'read', 'itemId': 'i1', 'unreadCount': 2}.jsify());
    expect(flagChanges, 1);
    expect(inbox.single, {'type': 'read', 'itemId': 'i1', 'unreadCount': 2});
    fake.getProperty<JSObject>('Inbox'.toJS).setProperty('addObserver'.toJS, null);
    facade.addInboxObserver(inbox.add);
  });

  test('sohbet: ayarlar, konuşma, okunmamış sayısı, yazıyor, ek adresi ve hazır widget', () async {
    final config = await facade.chatConfig(true);
    expect(config['enabled'], isTrue);
    expect(config['attachments'], {'enabled': true, 'max_bytes': 1024, 'types': ['image/png']});
    expect(await facade.chatConversation(), {'conversation': null, 'unread_count': 2});
    fake.setProperty('conversation'.toJS, {'id': 'cnv_1', 'status': 'open', 'last_seq': 9}.jsify());
    expect(await facade.chatConversation(), {
      'conversation': {'id': 'cnv_1', 'status': 'open', 'last_seq': 9},
      'unread_count': 2,
    });
    expect(await facade.chatUnreadCount(), 2);
    expect(await facade.chatRefreshUnreadCount(), 5);
    expect(await facade.chatUnreadCount(), 5);
    await facade.chatSetTyping(true);
    expect(await facade.chatAttachmentUrl('att_1', true), 'https://api.pushizo.com/chat/attachments/att_1?download=true');
    await facade.chatShow();
    await facade.chatHide();
    expect(calls(), [
      ['chatGetConfig', true],
      ['chatSetTyping', true],
      ['chatShow', {'open': true}],
      ['chatHide'],
    ]);
  });

  test('köprü + JS cephesi: Web SDK hatası PlatformException koduna çevrilir', () async {
    final bridge = PushizoWebBridge(facade, invokeDart: (method, arguments) async => null);
    await expectLater(
      bridge.handle(const MethodCall('addEmail', {'email': 'x'})),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'INVALID_ARGUMENT')),
    );
    await expectLater(
      bridge.handle(const MethodCall('login', {'externalId': 'forbidden'})),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'HS_FORBIDDEN')),
    );
    expect(await bridge.handle(const MethodCall('getTags')), {'plan': 'pro', 'n': '3'});
  });
}
