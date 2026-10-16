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
    constructor() { super('Geçersiz e-posta adresi (ör. ad@ornek.com).'); this.name = 'ContactValidationError'; }
  }
  const calls = [];
  const arg = (v) => (v === undefined ? 'undefined' : v);
  const sdk = {
    calls,
    inited: false,
    init(options) { calls.push(['init', options]); sdk.inited = true; return Promise.resolve(); },
    login(externalId, proof) {
      calls.push(['login', externalId, arg(proof)]);
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
    },
    Session: { sendEvent(name, properties, value) { calls.push(['sendEvent', name, properties, arg(value)]); } },
    InAppMessages: {
      paused: false,
      addClickListener(cb) { sdk.inAppClick = cb; },
      addLifecycleListener(listener) { sdk.lifecycle = listener; },
    },
    Inbox: { unreadCount() { return Promise.resolve(7); } },
    Location: {
      shared: false,
      setShared(shared) {
        if (!sdk.inited) throw new Error('Pushizo.init önce çağrılmalı.');
        this.shared = shared;
      },
      get isShared() { return this.shared; },
      requestPermission(rationale) { calls.push(['requestPermission', arg(rationale)]); return Promise.resolve(true); },
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
    await expectLater(empty.logout(), throwsA(isA<WebSdkError>().having((e) => e.code, 'code', 'NOT_READY')));
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
