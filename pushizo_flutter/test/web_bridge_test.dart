import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pushizo_flutter/pushizo_flutter.dart';
import 'package:pushizo_flutter/src/web/web_bridge.dart';

/// Flutter web köprüsünün saf Dart katmanı: kanal çağrısı → Web SDK eşlemesi, argüman doğrulama, hata çevirisi ve
/// olaylar sahte bir Web SDK cephesiyle VM'de sınanır (JavaScript katmanı `web_js_facade_test.dart`, tarayıcıda).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWebSdk sdk;
  late PushizoWebBridge bridge;
  late List<MethodCall> dartCalls;
  Object? dartReply;

  setUp(() {
    sdk = FakeWebSdk();
    dartCalls = [];
    dartReply = null;
    bridge = PushizoWebBridge(
      sdk,
      invokeDart: (method, arguments) async {
        dartCalls.add(MethodCall(method, arguments));
        final reply = dartReply;
        if (reply is Exception) throw reply;
        return reply;
      },
      clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    );
  });

  Future<Object?> call(String method, [Object? arguments]) => bridge.handle(MethodCall(method, arguments));

  Matcher platformError(String code) => throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

  group('yöntem kapsamı', () {
    test('Android köprüsünün her kanal yöntemi web\'de ya desteklenir ya da PLATFORM_NOT_SUPPORTED ile reddedilir', () {
      final source = File('android/src/main/kotlin/com/pushizo/pushizo_flutter/PushizoFlutterPlugin.kt').readAsStringSync();
      final start = source.indexOf('when (call.method) {');
      final kt = source.substring(start, source.indexOf('else -> result.notImplemented()', start));
      final methods = RegExp(r'^\s+((?:"[A-Za-z]+"(?:, )?)+) ->', multiLine: true)
          .allMatches(kt)
          .expand((m) => RegExp('"([A-Za-z]+)"').allMatches(m.group(1)!).map((x) => x.group(1)!))
          .toSet();
      expect(methods, containsAll(['initialize', 'requestLocationPermission', 'startDefaultLiveActivity', 'inboxList']));
      final covered = {...PushizoWebBridge.supportedMethods, ...PushizoWebBridge.unsupportedMethods.keys};
      expect(methods.difference(covered), isEmpty);
      expect(PushizoWebBridge.supportedMethods.intersection(PushizoWebBridge.unsupportedMethods.keys.toSet()), isEmpty);
    });

    test('web\'e özgü olmayan yöntemler Web SDK\'ya gitmeden PLATFORM_NOT_SUPPORTED döner', () async {
      sdk.loaded = false;
      for (final method in PushizoWebBridge.unsupportedMethods.keys) {
        await expectLater(call(method, const {}), platformError('PLATFORM_NOT_SUPPORTED'), reason: method);
      }
      await expectLater(call('setupDefaultLiveActivity'), throwsA(isA<PlatformException>()
          .having((e) => e.message, 'message', "Live Activities yalnızca iOS'ta desteklenir")));
      expect(sdk.calls, isEmpty);
    });

    test('Web SDK yüklenmemişse NOT_READY; bilinmeyen yöntem MissingPluginException', () async {
      sdk.loaded = false;
      await expectLater(
        call('initialize', {'appId': 'app_1'}),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'NOT_READY')
            .having((e) => e.message, 'message', contains('PushizoSDK.js'))),
      );
      await expectLater(call('getPlatformVersion'), throwsA(isA<MissingPluginException>()));
    });
  });

  group('başlatma ve kimlik', () {
    test('initialize seçenekleri Web SDK init seçeneklerine eşlenir; dinleyiciler bir kez eklenir', () async {
      await call('initialize', {
        'appId': 'app_1',
        'apiUrl': 'https://api.example.com',
        'requiresPrivacyConsent': true,
        'logLevel': 'none',
        'web': {'serviceWorkerPath': '/push/PushizoSDKWorker.js', 'serviceWorkerScope': '/push/'},
      });
      await call('initialize', {'appId': 'app_1', 'apiUrl': 'https://api.example.com', 'logLevel': 'debug'});
      expect(sdk.calls.first, ['init', {
        'appId': 'app_1',
        'apiUrl': 'https://api.example.com',
        'requiresPrivacyConsent': true,
        'logLevel': 'silent',
        'serviceWorkerPath': '/push/PushizoSDKWorker.js',
        'serviceWorkerScope': '/push/',
      }]);
      expect(sdk.calls[1][1], {'appId': 'app_1', 'apiUrl': 'https://api.example.com', 'requiresPrivacyConsent': false, 'logLevel': 'debug'});
      expect(sdk.listenerCount, 6);
      await expectLater(call('initialize', {'appId': ''}), platformError('INVALID_ARGUMENT'));
    });

    test('login kanıtı, updateUserJwt ve logout', () async {
      await call('login', {'externalId': 'u1', 'identityHash': 'h'});
      await call('login', {'externalId': 'u2', 'identityHash': null, 'jwt': 'h.p.s'});
      await call('updateUserJwt', {'jwt': 'h.p.s2'});
      await call('logout');
      expect(sdk.calls, [
        ['login', 'u1', 'h', null],
        ['login', 'u2', null, 'h.p.s'],
        ['updateUserJwt', 'h.p.s2'],
        ['logout'],
      ]);
      await expectLater(call('login', {'externalId': ''}), platformError('INVALID_ARGUMENT'));
      await expectLater(call('updateUserJwt', {'jwt': ''}), platformError('INVALID_ARGUMENT'));
      expect(sdk.calls, hasLength(4));
    });

    test('Web SDK hataları köprü kodlarına çevrilir', () async {
      sdk.failures['login'] = const WebSdkError("Bu app için kimlik JWT'si (login(id, { jwt })) zorunlu.");
      await expectLater(call('login', {'externalId': 'u1'}), platformError('HS_ERROR'));
      sdk.failures['updateUserJwt'] = const WebSdkError('Pushizo.init önce çağrılmalı.');
      await expectLater(call('updateUserJwt', {'jwt': 'x'}), platformError('NOT_READY'));
      sdk.failures['addEmail'] = const WebSdkError('Geçersiz e-posta adresi (ör. ad@ornek.com).', name: 'ContactValidationError');
      await expectLater(call('addEmail', {'email': 'x'}), platformError('INVALID_ARGUMENT'));
      sdk.failures['addAliases'] = const WebSdkError('Geçersiz alias etiketi "A"');
      await expectLater(call('addAliases', {'aliases': {'A': '1'}}), platformError('INVALID_ARGUMENT'));
      sdk.failures['inboxList'] = const WebSdkError('Pushizo.Inbox: kullanıcı veya abonelik yok.');
      await expectLater(call('inboxList', {'limit': 20}), platformError('NOT_READY'));
      sdk.failures['inboxMarkRead'] = const WebSdkError('Yasak', name: 'ApiError', code: 'HS_FORBIDDEN');
      await expectLater(call('inboxMarkRead', {'id': 'i1'}), platformError('HS_FORBIDDEN'));
      sdk.failures['setConsentGiven'] = const WebSdkError('Gizlilik onayı verilmedi (setConsentGiven).');
      await expectLater(call('setConsentGiven', {'given': true}), platformError('NOT_READY'));
    });
  });

  group('kullanıcı, bildirim ve in-app', () {
    test('tag, alias, e-posta/SMS, dil ve kimlik okuma', () async {
      sdk.values['getTags'] = {'plan': 'pro', 'score': 3.0, 'vip': true};
      sdk.values['externalId'] = 'u1';
      await call('addTags', {'tags': {'plan': 'pro'}});
      await call('removeTags', {'keys': ['a', 'b']});
      expect(await call('getTags'), {'plan': 'pro', 'score': '3', 'vip': 'true'});
      await call('addAliases', {'aliases': {'crm_id': '42'}});
      await call('removeAlias', {'label': 'crm_id'});
      await call('addEmail', {'email': 'ali@example.com'});
      await call('removeSms', {'phoneNumber': '+905321234567'});
      await call('setLanguage', {'code': 'tr'});
      expect(await call('getExternalId'), 'u1');
      expect(await call('getUserId'), isNull);
      expect(sdk.calls.map((c) => c.first), [
        'addTags', 'removeTags', 'getTags', 'addAliases', 'removeAlias', 'addEmail', 'removeSms', 'setLanguage',
        'externalId', 'userId',
      ]);
      expect(sdk.calls[1], ['removeTags', ['a', 'b']]);
    });

    test('abonelik durumu, izin ve olay gönderimi', () async {
      sdk.values['pushSubscriptionState'] = {'id': 'sub_1', 'token': 'https://push.example/ep', 'optedIn': true, 'permission': 'granted'};
      sdk.values['notificationPermission'] = 'denied';
      sdk.values['requestNotificationPermission'] = 'granted';
      expect(await call('getSubscriptionState'), {'id': 'sub_1', 'token': 'https://push.example/ep', 'optedIn': true, 'permission': true});
      expect(await call('getPermission'), isFalse);
      expect(await call('requestPermission'), isTrue);
      await call('optIn');
      await call('optOut');
      await call('clearAll');
      await call('sendEvent', {'name': 'purchase', 'properties': {'sku': 'A1'}, 'value': 49.9});
      await call('sendEvent', {'name': 'viewed', 'properties': <String, Object?>{}, 'value': null});
      await call('setLogLevel', {'level': 'none'});
      expect(sdk.calls.sublist(3), [
        ['optIn'],
        ['optOut'],
        ['clearAllNotifications'],
        ['sendEvent', 'purchase', {'sku': 'A1'}, 49.9],
        ['sendEvent', 'viewed', <String, Object?>{}, null],
        ['setLogLevel', 'silent'],
      ]);
    });

    test('in-app tetikleri, ekran ve duraklatma', () async {
      sdk.values['getTriggers'] = {'level': 'gold', 'count': 2.0};
      sdk.values['inAppPaused'] = true;
      await call('addTriggers', {'triggers': {'level': 'gold'}});
      await call('removeTriggers', {'keys': ['level']});
      await call('clearTriggers');
      expect(await call('getTriggers'), {'level': 'gold', 'count': '2'});
      await call('setScreen', {'name': null});
      await call('setInAppPaused', {'paused': true});
      expect(await call('getInAppPaused'), isTrue);
      expect(sdk.calls[4], ['setScreen', null]);
      expect(sdk.calls[5], ['setInAppPaused', true]);
    });
  });

  group('bildirim kutusu ve tercihler', () {
    test('inbox ISO zamanları epoch ms\'ye çevrilir', () async {
      final item = {
        'id': 'i1',
        'messageId': 'm1',
        'title': 'T',
        'body': null,
        'url': null,
        'imageUrl': null,
        'data': {'k': 'v'},
        'read': false,
        'readAt': null,
        'archivedAt': null,
        'expiresAt': '2026-10-20T00:00:00.000Z',
        'createdAt': '2026-10-15T10:00:00.000Z',
      };
      sdk.values['inboxList'] = {'items': [item], 'unreadCount': 3.0, 'nextCursor': 'c2', 'hasMore': true};
      sdk.values['inboxMarkRead'] = {...item, 'read': true, 'readAt': '2026-10-15T11:00:00.000Z'};
      sdk.values['inboxMarkAllRead'] = {'updated': 2.0, 'unreadCount': 0.0};
      sdk.values['inboxUnreadCount'] = 5.0;
      final page = PushizoInboxPage.fromMap((await call('inboxList', {'limit': 20, 'cursor': null}) as Map).cast());
      expect(page.items.single.createdAt, DateTime.utc(2026, 10, 15, 10));
      expect(page.items.single.expiresAt, DateTime.utc(2026, 10, 20));
      expect(page.unreadCount, 3);
      expect(page.nextCursor, 'c2');
      final read = PushizoInboxItem.fromMap((await call('inboxMarkRead', {'id': 'i1'}) as Map).cast());
      expect(read.read, isTrue);
      expect(read.readAt, DateTime.utc(2026, 10, 15, 11));
      expect(await call('inboxMarkAllRead'), 0);
      expect(await call('inboxUnreadCount'), 5);
      await call('inboxArchive', {'id': 'i1'});
      expect(sdk.calls.first, ['inboxList', 20, null]);
      expect(sdk.calls.last, ['inboxArchive', 'i1']);
    });

    Map<String, Object?> webPreferences() => {
          'preferences': [
            {'category': 'orders', 'channel': null, 'optedIn': true, 'explicit': false, 'source': null, 'updatedAt': null},
            {'category': 'promos', 'channel': null, 'optedIn': true, 'explicit': true, 'source': 'api', 'updatedAt': '2026-10-01T00:00:00.000Z'},
          ],
          'categories': [
            {'key': 'orders', 'name': {'tr': 'Siparişler'}, 'description': <String, String>{}, 'channels': ['web_push', 'email'], 'defaultOptedIn': true},
            {'key': 'promos', 'name': {'tr': 'Kampanyalar'}, 'description': <String, String>{}, 'channels': null, 'defaultOptedIn': true},
          ],
        };

    test('getPreferences köprü biçimine eşlenir', () async {
      sdk.values['getPreferences'] = webPreferences();
      final prefs = PushizoPreferences.fromMap((await call('getPreferences') as Map).cast());
      expect(prefs.preferences.map((p) => p.category), ['orders', 'promos']);
      expect(prefs.preferences[1].updatedAt, DateTime.utc(2026, 10));
      expect(prefs.categories.first.channels, ['web_push', 'email']);
      expect(prefs.categories.first.localizedName('tr'), 'Siparişler');
    });

    test('setPreferences kuyruğa yazar ve sunucunun döndüreceği listeyi üretir', () async {
      sdk.values['getPreferences'] = webPreferences();
      final result = await call('setPreferences', {
        'preferences': [
          {'category': 'promos', 'channel': null, 'optedIn': false},
          {'category': 'orders', 'channel': 'email', 'optedIn': false},
        ],
      });
      expect(sdk.calls.last, ['setPreferences', [
        {'category': 'promos', 'optedIn': false, 'channel': null},
        {'category': 'orders', 'optedIn': false, 'channel': 'email'},
      ]]);
      final prefs = PushizoPreferences.fromMap((result as Map).cast());
      expect(prefs.preferences.map((p) => '${p.category}/${p.channel}/${p.optedIn}'), [
        'orders/null/true',
        'orders/email/false',
        'promos/null/false',
      ]);
      expect(prefs.preferences[1].explicit, isTrue);
      expect(prefs.preferences[1].updatedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
    });

    test('setPreferences doğrulaması: geçersiz girdi, bilinmeyen kategori, kapsanmayan kanal, abonelik yok', () async {
      sdk.values['getPreferences'] = webPreferences();
      await expectLater(call('setPreferences', {'preferences': []}), platformError('INVALID_ARGUMENT'));
      await expectLater(call('setPreferences', {'preferences': [{'category': ' ', 'optedIn': true}]}), platformError('INVALID_ARGUMENT'));
      await expectLater(call('setPreferences', {'preferences': [{'category': 'news', 'optedIn': true}]}), platformError('HS_NOT_FOUND'));
      await expectLater(
        call('setPreferences', {'preferences': [{'category': 'orders', 'channel': 'sms', 'optedIn': true}]}),
        platformError('HS_VALIDATION_ERROR'),
      );
      sdk.failures['getPreferences'] = const WebSdkError('Tercihler için abonelik gerekli (push, e-posta veya SMS).');
      await expectLater(call('setPreferences', {'preferences': [{'category': 'orders', 'optedIn': true}]}), platformError('NOT_READY'));
      expect(sdk.calls.where((c) => c.first == 'setPreferences'), isEmpty);
    });
  });

  test('konum çağrıları Web SDK Location API\'sine iletilir', () async {
    sdk.values['locationShared'] = true;
    sdk.values['requestLocationPermission'] = true;
    await call('setLocationShared', {'shared': true});
    expect(await call('getLocationShared'), isTrue);
    expect(await call('requestLocationPermission', {'rationale': 'Yakındaki mağazalar'}), isTrue);
    await call('requestLocationPermission', {'rationale': '  '});
    expect(sdk.calls, [
      ['setLocationShared', true],
      ['locationShared'],
      ['requestLocationPermission', 'Yakındaki mağazalar'],
      ['requestLocationPermission', null],
    ]);
    sdk.failures['setLocationShared'] = const WebSdkError('Pushizo.init önce çağrılmalı.');
    await expectLater(call('setLocationShared', {'shared': true}), platformError('NOT_READY'));
  });

  group('olaylar', () {
    Future<void> init() => call('initialize', {'appId': 'app_1', 'logLevel': 'warn'});

    test('tıklama akış dinlenene kadar bekletilir; diğer olaylar Android/iOS biçiminde iletilir', () async {
      await init();
      sdk.click({
        'notification': {'title': 'T', 'body': '', 'deliveryId': 'dlv_1', 'data': {'k': 'v', 'n': 1.0}},
        'result': {'actionId': 'open', 'url': 'https://x'},
      });
      final events = <Map<String, Object?>>[];
      final sub = bridge.eventController.stream.listen(events.add);
      await pumpEventQueue();
      sdk.subscription({'id': 'sub_1', 'token': 't', 'optedIn': true, 'permission': 'granted'});
      sdk.permission(false);
      sdk.inAppClick({'message': {'id': 'm1'}, 'result': {'actionId': 'b1'}});
      sdk.inAppLifecycle('didDisplay', 'm1');
      await pumpEventQueue();
      expect(events, [
        {
          'type': 'click',
          'notification': {
            'title': 'T', 'body': null, 'url': null, 'deliveryId': 'dlv_1', 'messageId': null,
            'data': {'k': 'v', 'n': '1'}, 'androidNotificationId': null,
          },
          'actionId': 'open',
          'url': 'https://x',
        },
        {'type': 'subscription', 'state': {'id': 'sub_1', 'token': 't', 'optedIn': true, 'permission': true}},
        {'type': 'permission', 'permission': false},
        {'type': 'inAppClick', 'messageId': 'm1', 'actionId': 'b1', 'url': null},
        {'type': 'inAppLifecycle', 'event': 'didDisplay', 'messageId': 'm1'},
      ]);
      final click = PushizoClickEvent.fromMap(Map<String, dynamic>.from(events.first));
      expect(click.notification.deliveryId, 'dlv_1');
      await sub.cancel();
    });

    test('ön plan: işleyici yoksa yalnızca bilgi olayı; varsa engellenir ve karar Dart\'a sorulur', () async {
      await init();
      final events = <Map<String, Object?>>[];
      final sub = bridge.eventController.stream.listen(events.add);
      final plain = FakeForegroundEvent({'title': 'T', 'data': <String, Object?>{}});
      sdk.foreground(plain);
      expect(plain.prevented, isFalse);
      expect(dartCalls, isEmpty);

      await call('setForegroundHandlerEnabled', {'enabled': true});
      // Dart preventDefault çağırmadı (false) → gösterilir.
      dartReply = false;
      final shown = FakeForegroundEvent({'title': 'A', 'deliveryId': 'dlv_a'});
      sdk.foreground(shown);
      expect(shown.prevented, isTrue, reason: 'Web SDK kararı senkron ister');
      await pumpEventQueue();
      expect(shown.displayed, 1);
      expect(dartCalls.single.method, 'foregroundWillDisplay');
      expect((dartCalls.single.arguments as Map)['notification'], containsPair('deliveryId', 'dlv_a'));

      // Dart engelledi (true) → gösterilmez; sonradan display() ile gösterilir.
      dartReply = true;
      final held = FakeForegroundEvent({'title': 'B'});
      sdk.foreground(held);
      await pumpEventQueue();
      expect(held.displayed, 0);
      final eventId = (dartCalls.last.arguments as Map)['eventId'];
      await call('displayForegroundNotification', {'eventId': eventId});
      await call('displayForegroundNotification', {'eventId': eventId});
      expect(held.displayed, 1);

      // Dart çağrısı başarısız → gösterilir.
      dartReply = PlatformException(code: 'x');
      final failed = FakeForegroundEvent({'title': 'C'});
      sdk.foreground(failed);
      await pumpEventQueue();
      expect(failed.displayed, 1);
      expect(events.where((e) => e['type'] == 'foreground'), hasLength(4));
      await sub.cancel();
    });
  });

  test('Dart genel API\'si web köprüsüyle uçtan uca çalışır', () async {
    const channel = MethodChannel('pushizo_flutter');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, bridge.handle);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    sdk.values['locationShared'] = false;
    sdk.values['requestLocationPermission'] = true;
    sdk.values['getTags'] = {'plan': 'pro'};
    await Pushizo.initialize('app_1', apiUrl: 'https://api.example.com', web: const PushizoWebOptions(allowLocalhostAsSecureOrigin: true));
    await Pushizo.login('u1', jwt: 'h.p.s');
    await Pushizo.User.addTag('plan', 'pro');
    expect(await Pushizo.User.getTags(), {'plan': 'pro'});
    expect(await Pushizo.Location.isShared, isFalse);
    expect(await Pushizo.Location.requestPermission(rationale: 'Yakındaki mağazalar'), isTrue);
    await Pushizo.Location.setShared(true);
    await expectLater(Pushizo.LiveActivities.setupDefaultLiveActivity(), platformError('PLATFORM_NOT_SUPPORTED'));
    await expectLater(Pushizo.Notifications.removeNotification(1), platformError('PLATFORM_NOT_SUPPORTED'));
    expect(sdk.calls.first, ['init', {
      'appId': 'app_1',
      'apiUrl': 'https://api.example.com',
      'requiresPrivacyConsent': false,
      'logLevel': 'warn',
      'allowLocalhostAsSecureOrigin': true,
    }]);
    expect(sdk.calls[1], ['login', 'u1', null, 'h.p.s']);
    expect(sdk.calls.last, ['setLocationShared', true]);
  });

  test('webErrorCode ve webLogLevel', () {
    expect(webErrorCode(const WebSdkError('x', code: 'NO_CONSENT')), 'NO_CONSENT');
    expect(webErrorCode(const WebSdkError('x', code: '')), 'HS_ERROR');
    expect(webErrorCode(const WebSdkError('x'), fallback: 'NOT_READY'), 'NOT_READY');
    expect(webLogLevel('none'), 'silent');
    expect(webLogLevel('info'), 'info');
    expect(webLogLevel('verbose'), 'warn');
  });
}

/// Çağrıları `[yöntem, argümanlar…]` olarak kaydeden sahte Web SDK cephesi.
class FakeWebSdk implements WebSdkFacade {
  bool loaded = true;
  final List<List<Object?>> calls = [];
  final Map<String, Object?> values = {};
  final Map<String, WebSdkError> failures = {};

  void Function(Map<Object?, Object?>)? _click;
  void Function(WebForegroundEvent)? _foreground;
  void Function(Map<Object?, Object?>)? _subscription;
  void Function(bool)? _permission;
  void Function(Map<Object?, Object?>)? _inAppClick;
  void Function(String, String)? _inAppLifecycle;

  int get listenerCount => [_click, _foreground, _subscription, _permission, _inAppClick, _inAppLifecycle].nonNulls.length;

  Future<T> _record<T>(String method, [List<Object?> args = const []]) async {
    calls.add([method, ...args]);
    final failure = failures[method];
    if (failure != null) throw failure;
    return values[method] as T;
  }

  void click(Map<Object?, Object?> e) => _click!(e);
  void foreground(WebForegroundEvent e) => _foreground!(e);
  void subscription(Map<Object?, Object?> s) => _subscription!(s);
  void permission(bool granted) => _permission!(granted);
  void inAppClick(Map<Object?, Object?> e) => _inAppClick!(e);
  void inAppLifecycle(String event, String id) => _inAppLifecycle!(event, id);

  @override
  bool get isLoaded => loaded;
  @override
  Future<void> init(Map<String, Object?> options) => _record('init', [options]);
  @override
  Future<void> setConsentGiven(bool given) => _record('setConsentGiven', [given]);
  @override
  Future<void> login(String externalId, {String? identityHash, String? jwt}) => _record('login', [externalId, identityHash, jwt]);
  @override
  Future<void> updateUserJwt(String jwt) => _record('updateUserJwt', [jwt]);
  @override
  Future<void> logout() => _record('logout');
  @override
  Future<void> addTags(Map<String, String> tags) => _record('addTags', [tags]);
  @override
  Future<void> removeTags(List<String> keys) => _record('removeTags', [keys]);
  @override
  Future<Map<Object?, Object?>> getTags() async => (await _record<Map<Object?, Object?>?>('getTags')) ?? {};
  @override
  Future<void> addAliases(Map<String, String> aliases) => _record('addAliases', [aliases]);
  @override
  Future<void> removeAlias(String label) => _record('removeAlias', [label]);
  @override
  Future<void> addEmail(String email) => _record('addEmail', [email]);
  @override
  Future<void> removeEmail(String email) => _record('removeEmail', [email]);
  @override
  Future<void> addSms(String phoneNumber) => _record('addSms', [phoneNumber]);
  @override
  Future<void> removeSms(String phoneNumber) => _record('removeSms', [phoneNumber]);
  @override
  Future<void> setLanguage(String code) => _record('setLanguage', [code]);
  @override
  Future<String?> externalId() => _record('externalId');
  @override
  Future<String?> userId() => _record('userId');
  @override
  Future<Map<Object?, Object?>> getPreferences() async => (await _record<Map<Object?, Object?>?>('getPreferences')) ?? {};
  @override
  Future<void> setPreferences(List<Map<String, Object?>> preferences) => _record('setPreferences', [preferences]);
  @override
  Future<Map<Object?, Object?>> pushSubscriptionState() async =>
      (await _record<Map<Object?, Object?>?>('pushSubscriptionState')) ?? {};
  @override
  Future<void> optIn() => _record('optIn');
  @override
  Future<void> optOut() => _record('optOut');
  @override
  Future<String> notificationPermission() async => (await _record<String?>('notificationPermission')) ?? 'default';
  @override
  Future<String> requestNotificationPermission() async => (await _record<String?>('requestNotificationPermission')) ?? 'default';
  @override
  Future<void> clearAllNotifications() => _record('clearAllNotifications');
  @override
  Future<void> sendEvent(String name, Map<String, Object?> properties, double? value) => _record('sendEvent', [name, properties, value]);
  @override
  Future<void> setLogLevel(String level) => _record('setLogLevel', [level]);
  @override
  Future<void> addTriggers(Map<String, String> triggers) => _record('addTriggers', [triggers]);
  @override
  Future<void> removeTriggers(List<String> keys) => _record('removeTriggers', [keys]);
  @override
  Future<void> clearTriggers() => _record('clearTriggers');
  @override
  Future<Map<Object?, Object?>> getTriggers() async => (await _record<Map<Object?, Object?>?>('getTriggers')) ?? {};
  @override
  Future<void> setScreen(String? name) => _record('setScreen', [name]);
  @override
  Future<bool> inAppPaused() async => (await _record<bool?>('inAppPaused')) ?? false;
  @override
  Future<void> setInAppPaused(bool paused) => _record('setInAppPaused', [paused]);
  @override
  Future<Map<Object?, Object?>> inboxList({int? limit, String? cursor}) async =>
      (await _record<Map<Object?, Object?>?>('inboxList', [limit, cursor])) ?? {};
  @override
  Future<Map<Object?, Object?>> inboxMarkRead(String id) async => (await _record<Map<Object?, Object?>?>('inboxMarkRead', [id])) ?? {};
  @override
  Future<Map<Object?, Object?>> inboxMarkAllRead() async => (await _record<Map<Object?, Object?>?>('inboxMarkAllRead')) ?? {};
  @override
  Future<void> inboxArchive(String id) => _record('inboxArchive', [id]);
  @override
  Future<num> inboxUnreadCount() async => (await _record<num?>('inboxUnreadCount')) ?? 0;
  @override
  Future<void> setLocationShared(bool shared) => _record('setLocationShared', [shared]);
  @override
  Future<bool> locationShared() async => (await _record<bool?>('locationShared')) ?? false;
  @override
  Future<bool> requestLocationPermission(String? rationale) async =>
      (await _record<bool?>('requestLocationPermission', [rationale])) ?? false;
  @override
  void addClickListener(void Function(Map<Object?, Object?> event) listener) => _click = listener;
  @override
  void addForegroundListener(void Function(WebForegroundEvent event) listener) => _foreground = listener;
  @override
  void addSubscriptionObserver(void Function(Map<Object?, Object?> state) observer) => _subscription = observer;
  @override
  void addPermissionObserver(void Function(bool granted) observer) => _permission = observer;
  @override
  void addInAppClickListener(void Function(Map<Object?, Object?> event) listener) => _inAppClick = listener;
  @override
  void addInAppLifecycleListener(void Function(String event, String messageId) listener) => _inAppLifecycle = listener;
}

class FakeForegroundEvent implements WebForegroundEvent {
  FakeForegroundEvent(this.notification);

  @override
  final Map<Object?, Object?> notification;
  bool prevented = false;
  int displayed = 0;

  @override
  void preventDefault() => prevented = true;

  @override
  Future<void> display() async => displayed++;
}
