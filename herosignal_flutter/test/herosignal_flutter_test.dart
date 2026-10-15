import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herosignal_flutter/herosignal_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('herosignal_flutter');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getTags':
          return {'plan': 'pro'};
        case 'getSubscriptionState':
          return {'id': 'sub_1', 'token': 't', 'optedIn': true, 'permission': true};
        case 'requestPermission':
          return true;
        default:
          return null;
      }
    });
  });

  test('initialize argümanları platforma iletilir', () async {
    await HeroSignal.initialize('app_1', apiUrl: 'http://10.0.2.2:4000', logLevel: HeroSignalLogLevel.debug);
    expect(calls.single.method, 'initialize');
    expect(calls.single.arguments, {'appId': 'app_1', 'apiUrl': 'http://10.0.2.2:4000', 'requiresPrivacyConsent': false, 'logLevel': 'debug'});
  });

  test('kullanıcı ve abonelik çağrıları', () async {
    await HeroSignal.login('u1', identityHash: 'h');
    await HeroSignal.User.addTag('plan', 'pro');
    await HeroSignal.User.removeTags(['a', 'b']);
    expect(await HeroSignal.User.getTags(), {'plan': 'pro'});
    final state = await HeroSignal.User.pushSubscription.state;
    expect(state.id, 'sub_1');
    expect(state.optedIn, isTrue);
    expect(await HeroSignal.Notifications.requestPermission(), isTrue);
    await HeroSignal.Session.sendEvent('purchase', properties: {'sku': 'A1'}, value: 49.9);
    expect(calls.map((c) => c.method).toList(), ['login', 'addTags', 'removeTags', 'getTags', 'getSubscriptionState', 'requestPermission', 'sendEvent']);
    expect(calls[0].arguments, {'externalId': 'u1', 'identityHash': 'h'});
    expect(calls[1].arguments, {'tags': {'plan': 'pro'}});
    expect(calls.last.arguments, {'name': 'purchase', 'properties': {'sku': 'A1'}, 'value': 49.9});
  });

  group('JWT ile kimlik doğrulama', () {
    test('login JWT\'yi yalnızca yöntem argümanı olarak yerel SDK\'ya iletir', () async {
      await HeroSignal.login('u1', jwt: 'h.p.s');
      await HeroSignal.login('u2', identityHash: 'h', jwt: 'h.p.s2');
      expect(calls.map((c) => c.method).toList(), ['login', 'login']);
      expect(calls[0].arguments, {'externalId': 'u1', 'identityHash': null, 'jwt': 'h.p.s'});
      expect(calls[1].arguments, {'externalId': 'u2', 'identityHash': 'h', 'jwt': 'h.p.s2'});
    });

    test('JWT verilmezse argümanlar eski sözleşmeyle aynıdır', () async {
      await HeroSignal.login('u1');
      expect(calls.single.arguments, {'externalId': 'u1', 'identityHash': null});
    });

    test('updateUserJwt ve logout platforma iletilir', () async {
      await HeroSignal.updateUserJwt('h.p.s3');
      await HeroSignal.logout();
      expect(calls.map((c) => c.method).toList(), ['updateUserJwt', 'logout']);
      expect(calls[0].arguments, {'jwt': 'h.p.s3'});
      expect(calls[1].arguments, isNull);
    });

    test('yerel SDK hatası (giriş yok / kanıt eksik) PlatformException olarak döner', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'updateUserJwt') {
          throw PlatformException(code: 'HS_ERROR', message: 'Önce login ile kullanıcı kimliklendirilmeli');
        }
        if (call.method == 'login') {
          throw PlatformException(code: 'HS_ERROR', message: "Bu app için kimlik JWT'si zorunlu");
        }
        return null;
      });
      await expectLater(HeroSignal.updateUserJwt('h.p.s'), throwsA(isA<PlatformException>()));
      await expectLater(HeroSignal.login('u1', identityHash: 'h'), throwsA(isA<PlatformException>()));
    });
  });

  group('Live Activities (iOS)', () {
    test('setup ve start çağrıları argümanlarıyla platforma iletilir', () async {
      await HeroSignal.LiveActivities.setupDefaultLiveActivity();
      await HeroSignal.LiveActivities.startDefaultLiveActivity(
        'order_42:a-b.c',
        {'title': 'Sipariş #42', 'count': 2},
        {'status': 'Yolda', 'eta': 12.5, 'late': false},
      );
      expect(calls.map((c) => c.method).toList(), ['setupDefaultLiveActivity', 'startDefaultLiveActivity']);
      expect(calls[0].arguments, isNull);
      expect(calls[1].arguments, {
        'activityId': 'order_42:a-b.c',
        'attributes': {'title': 'Sipariş #42', 'count': 2},
        'contentState': {'status': 'Yolda', 'eta': 12.5, 'late': false},
      });
    });

    test('geçersiz kimlik, anahtar ve değerler platforma gitmeden ArgumentError fırlatır', () {
      final live = HeroSignal.LiveActivities;
      expect(() => live.startDefaultLiveActivity('', {}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('a' * 101, {}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order 42', {}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order_42', {'herosignal': 'x'}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order_42', {'k' * 65: 'x'}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order_42', {'': 'x'}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order_42', {}, {'eta': double.nan}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order_42', {}, {'eta': double.infinity}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order_42', {'nested': <String, Object>{'a': 1}}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order_42', {'list': <Object>[1]}, {}), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('yerel hata kodu (Android PLATFORM_NOT_SUPPORTED, iOS LIVE_ACTIVITY_FAILED) PlatformException olarak döner', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'setupDefaultLiveActivity') {
          throw PlatformException(code: 'PLATFORM_NOT_SUPPORTED', message: "Live Activities yalnızca iOS'ta desteklenir");
        }
        throw PlatformException(code: 'LIVE_ACTIVITY_FAILED', message: 'Live Activities bu cihazda kapalı');
      });
      await expectLater(
        HeroSignal.LiveActivities.setupDefaultLiveActivity(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'PLATFORM_NOT_SUPPORTED')),
      );
      await expectLater(
        HeroSignal.LiveActivities.startDefaultLiveActivity('order_42', {'title': 'x'}, {'status': 'y'}),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'LIVE_ACTIVITY_FAILED')),
      );
    });

    test('yerel köprüler: iOS SDK çağrıları ve Android PLATFORM_NOT_SUPPORTED', () {
      // Yerel kod bu ortamda derlenemediğinden sözleşme kaynak metni üzerinden doğrulanır (CRLF normalize edilir).
      String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final swift = read('ios/Classes/HerosignalFlutterPlugin.swift');
      expect(swift, contains('case "setupDefaultLiveActivity":'));
      expect(swift, contains('try HeroSignal.LiveActivities.setupDefaultLiveActivity()'));
      expect(swift, contains('try HeroSignal.LiveActivities.startDefaultLiveActivity(activityId:'));
      expect(swift, contains('catch let error as HSLiveActivityError'));
      expect(swift, contains('FlutterError(code: error.code, message: error.message, details: nil)'));
      expect(swift, contains('"LIVE_ACTIVITY_FAILED"'));
      final kt = read('android/src/main/kotlin/com/herosignal/herosignal_flutter/HerosignalFlutterPlugin.kt');
      expect(kt, contains('"setupDefaultLiveActivity", "startDefaultLiveActivity" ->'));
      expect(kt, contains('result.error(LIVE_ACTIVITY_UNSUPPORTED_CODE, LIVE_ACTIVITY_UNSUPPORTED_MESSAGE, null)'));
      expect(kt, contains('LIVE_ACTIVITY_UNSUPPORTED_CODE = "PLATFORM_NOT_SUPPORTED"'));
    });
  });

  test('web başlatma seçenekleri yalnızca verildiğinde iletilir', () async {
    await HeroSignal.initialize(
      'app_1',
      web: const HeroSignalWebOptions(serviceWorkerPath: '/sw/HeroSignalSDKWorker.js', allowLocalhostAsSecureOrigin: true),
    );
    expect(calls.single.arguments, {
      'appId': 'app_1',
      'apiUrl': 'https://api.herosignal.dev',
      'requiresPrivacyConsent': false,
      'logLevel': 'warn',
      'web': {'serviceWorkerPath': '/sw/HeroSignalSDKWorker.js', 'allowLocalhostAsSecureOrigin': true},
    });
  });

  group('Konum', () {
    test('setShared, isShared ve requestPermission platforma iletilir', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'getLocationShared' => true,
          'requestLocationPermission' => true,
          _ => null,
        };
      });
      await HeroSignal.Location.setShared(true);
      expect(await HeroSignal.Location.isShared, isTrue);
      expect(await HeroSignal.Location.requestPermission(rationale: 'Yakındaki mağazalar için'), isTrue);
      await HeroSignal.Location.requestPermission();
      await HeroSignal.Location.setShared(false);
      expect(calls.map((c) => c.method).toList(), [
        'setLocationShared',
        'getLocationShared',
        'requestLocationPermission',
        'requestLocationPermission',
        'setLocationShared',
      ]);
      expect(calls[0].arguments, {'shared': true});
      expect(calls[1].arguments, isNull);
      expect(calls[2].arguments, {'rationale': 'Yakındaki mağazalar için'});
      expect(calls[3].arguments, {'rationale': null});
      expect(calls[4].arguments, {'shared': false});
    });

    test('yerel sonuç yoksa false döner; yerel hata PlatformException olarak iletilir', () async {
      expect(await HeroSignal.Location.isShared, isFalse);
      expect(await HeroSignal.Location.requestPermission(), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'HS_ERROR', message: 'Konum izni isteği zaten sürüyor');
      });
      await expectLater(
        HeroSignal.Location.requestPermission(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'HS_ERROR')),
      );
    });

    test('yerel köprüler: Android izin akışı ve iOS SDK çağrıları', () {
      // Yerel kod bu ortamda derlenemediğinden sözleşme kaynak metni üzerinden doğrulanır (CRLF normalize edilir).
      String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final kt = read('android/src/main/kotlin/com/herosignal/herosignal_flutter/HerosignalFlutterPlugin.kt');
      expect(kt, contains('"setLocationShared" -> { HeroSignal.Location.setShared(call.argument<Boolean>("shared") ?: false)'));
      expect(kt, contains('"getLocationShared" -> result.success(HeroSignal.Location.isShared)'));
      expect(kt, contains('"requestLocationPermission" -> requestLocationPermission(call.argument<String>("rationale"), result)'));
      // 1) izin varsa onPermissionResult + true; 2) manifest izinleri; 3) Activity yoksa false.
      expect(kt, contains('if (HeroSignal.Location.permissionGranted) {\n            HeroSignal.Location.onPermissionResult()\n            result.success(true)'));
      expect(kt, contains('PackageManager.GET_PERMISSIONS'));
      expect(kt, contains('listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)'));
      expect(kt, contains('val act = activity ?: return result.success(false)'));
      // 4) SDK string kaynaklarıyla açıklama diyaloğu; vazgeçme false.
      expect(kt, contains('AlertDialog.Builder(act)'));
      expect(kt, contains('com.herosignal.sdk.R.string.hs_location_rationale_title'));
      expect(kt, contains('rationale?.takeIf { it.isNotBlank() } ?: act.getString(com.herosignal.sdk.R.string.hs_location_rationale_message)'));
      expect(kt, contains('com.herosignal.sdk.R.string.hs_location_rationale_continue'));
      expect(kt, contains('com.herosignal.sdk.R.string.hs_location_rationale_not_now'));
      expect(kt, contains('.setOnDismissListener { if (!proceeded) result.success(false) }'));
      // 5) sistem izni SDK istek koduyla; sonuçta onPermissionResult ve permissionGranted.
      expect(kt, contains('act.requestPermissions(permissions.toTypedArray(), HeroSignal.Location.PERMISSION_REQUEST_CODE)'));
      expect(kt, contains('binding.addRequestPermissionsResultListener(this)'));
      expect(kt, contains(
        'if (requestCode == HeroSignal.Location.PERMISSION_REQUEST_CODE) {\n'
        '            HeroSignal.Location.onPermissionResult()\n'
        '            pendingLocationPermission?.success(HeroSignal.Location.permissionGranted)',
      ));
      final swift = read('ios/Classes/HerosignalFlutterPlugin.swift');
      expect(swift, contains('case "setLocationShared": HeroSignal.Location.setShared(args["shared"] as? Bool ?? false); result(nil)'));
      expect(swift, contains('case "getLocationShared": result(HeroSignal.Location.isShared)'));
      expect(swift, contains('HeroSignal.Location.requestPermission(rationale: args["rationale"] as? String) { granted in result(granted) }'));
    });
  });

  test('alias çağrıları platforma iletilir', () async {
    await HeroSignal.User.addAlias('crm_id', '42');
    await HeroSignal.User.addAliases({'shop_id': '7', 'erp_id': 'x'});
    await HeroSignal.User.removeAlias('crm_id');
    expect(calls.map((c) => c.method).toList(), ['addAliases', 'addAliases', 'removeAlias']);
    expect(calls[0].arguments, {'aliases': {'crm_id': '42'}});
    expect(calls[1].arguments, {'aliases': {'shop_id': '7', 'erp_id': 'x'}});
    expect(calls[2].arguments, {'label': 'crm_id'});
  });

  group('ön plan gösterim işleyicisi', () {
    const codec = StandardMethodCodec();

    Future<Object?> nativeAsks(Map<String, Object?> notification) async {
      final completer = Completer<Object?>();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'herosignal_flutter',
        codec.encodeMethodCall(MethodCall('foregroundWillDisplay', {'notification': notification})),
        (data) => completer.complete(data == null ? null : codec.decodeEnvelope(data)),
      );
      return completer.future;
    }

    tearDown(() => HeroSignal.Notifications.setForegroundWillDisplayHandler(null));

    test('preventDefault gösterimi engeller, işleyici bildirimi alır', () async {
      HeroSignalNotification? seen;
      await HeroSignal.Notifications.setForegroundWillDisplayHandler((event) {
        seen = event.notification;
        if (event.notification.data['in_app'] == '1') event.preventDefault();
      });
      expect(calls.last.method, 'setForegroundHandlerEnabled');
      expect(calls.last.arguments, {'enabled': true});

      expect(await nativeAsks({'title': 'T', 'deliveryId': 'dlv_1', 'data': {'in_app': '1'}}), isTrue);
      expect(seen?.deliveryId, 'dlv_1');
      expect(await nativeAsks({'title': 'T2', 'data': <String, String>{}}), isFalse);
    });

    test('asenkron işleyici beklenir; hata gösterimi engellemez', () async {
      await HeroSignal.Notifications.setForegroundWillDisplayHandler((event) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        event.preventDefault();
      });
      expect(await nativeAsks({'title': 'T'}), isTrue);

      await HeroSignal.Notifications.setForegroundWillDisplayHandler((event) => throw StateError('x'));
      expect(await nativeAsks({'title': 'T'}), isFalse);
    });

    test('işleyici kaldırılınca yerel tarafa bildirilir', () async {
      await HeroSignal.Notifications.setForegroundWillDisplayHandler((event) {});
      await HeroSignal.Notifications.setForegroundWillDisplayHandler(null);
      expect(calls.last.arguments, {'enabled': false});
    });
  });

  test('bildirim tepsisi çağrıları platforma iletilir', () async {
    await HeroSignal.Notifications.clearAll();
    await HeroSignal.Notifications.removeNotification(42);
    await HeroSignal.Notifications.removeGroupedNotifications('orders');
    expect(calls.map((c) => c.method).toList(), ['clearAll', 'removeNotification', 'removeGroupedNotifications']);
    expect(calls[1].arguments, {'id': 42});
    expect(calls[2].arguments, {'group': 'orders'});
    final n = HeroSignalNotification.fromMap({'title': 'T', 'androidNotificationId': 7});
    expect(n.androidNotificationId, 7);
    expect(HeroSignalNotification.fromMap({'title': 'T'}).androidNotificationId, isNull);
  });

  test('izin değişiklikleri akışa ve gözlemcilere iletilir', () async {
    MockStreamHandlerEventSink? sink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('herosignal_flutter/events'),
      MockStreamHandler.inline(onListen: (arguments, events) => sink = events),
    );
    final streamed = <bool>[];
    final seen = <bool>[];
    void observer(bool granted) {
      seen.add(granted);
    }
    final subscription = HeroSignal.Notifications.permissionStream.listen(streamed.add);
    HeroSignal.Notifications.addPermissionObserver(observer);
    HeroSignal.Notifications.addPermissionObserver(observer);
    await pumpEventQueue();

    sink!.success({'type': 'subscription', 'state': {'id': 'sub_1', 'optedIn': true, 'permission': true}});
    sink!.success({'type': 'permission', 'permission': true});
    sink!.success({'type': 'permission', 'permission': false});
    await pumpEventQueue();
    expect(streamed, [true, false]);
    expect(seen, [true, false], reason: 'aynı gözlemci bir kez eklenir');

    HeroSignal.Notifications.removePermissionObserver(observer);
    sink!.success({'type': 'permission', 'permission': true});
    await pumpEventQueue();
    expect(seen, [true, false]);
    expect(streamed, [true, false, true]);
    await subscription.cancel();
  });

  test('modeller haritadan oluşur', () {
    final click = HeroSignalClickEvent.fromMap({
      'notification': {'title': 'T', 'body': 'B', 'url': 'myapp://x', 'deliveryId': 'dlv_1', 'data': {'k': 'v'}},
      'actionId': 'open',
      'url': 'https://x',
    });
    expect(click.notification.deliveryId, 'dlv_1');
    expect(click.notification.data, {'k': 'v'});
    expect(click.url, 'https://x');
  });
}
