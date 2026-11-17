import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pushizo_flutter/pushizo_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pushizo_flutter');
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
    await Pushizo.initialize('app_1', apiUrl: 'http://10.0.2.2:4000', logLevel: PushizoLogLevel.debug);
    expect(calls.single.method, 'initialize');
    expect(calls.single.arguments, {'appId': 'app_1', 'apiUrl': 'http://10.0.2.2:4000', 'requiresPrivacyConsent': false, 'logLevel': 'debug'});
  });

  test('kullanıcı ve abonelik çağrıları', () async {
    await Pushizo.login('u1', identityHash: 'h');
    await Pushizo.User.addTag('plan', 'pro');
    await Pushizo.User.removeTags(['a', 'b']);
    expect(await Pushizo.User.getTags(), {'plan': 'pro'});
    final state = await Pushizo.User.pushSubscription.state;
    expect(state.id, 'sub_1');
    expect(state.optedIn, isTrue);
    expect(await Pushizo.Notifications.requestPermission(), isTrue);
    await Pushizo.Session.sendEvent('purchase', properties: {'sku': 'A1'}, value: 49.9);
    expect(calls.map((c) => c.method).toList(), ['login', 'addTags', 'removeTags', 'getTags', 'getSubscriptionState', 'requestPermission', 'sendEvent']);
    expect(calls[0].arguments, {'externalId': 'u1', 'identityHash': 'h'});
    expect(calls[1].arguments, {'tags': {'plan': 'pro'}});
    expect(calls.last.arguments, {'name': 'purchase', 'properties': {'sku': 'A1'}, 'value': 49.9});
  });

  group('JWT ile kimlik doğrulama', () {
    test('login JWT\'yi yalnızca yöntem argümanı olarak yerel SDK\'ya iletir', () async {
      await Pushizo.login('u1', jwt: 'h.p.s');
      await Pushizo.login('u2', identityHash: 'h', jwt: 'h.p.s2');
      expect(calls.map((c) => c.method).toList(), ['login', 'login']);
      expect(calls[0].arguments, {'externalId': 'u1', 'identityHash': null, 'jwt': 'h.p.s'});
      expect(calls[1].arguments, {'externalId': 'u2', 'identityHash': 'h', 'jwt': 'h.p.s2'});
    });

    test('JWT verilmezse argümanlar eski sözleşmeyle aynıdır', () async {
      await Pushizo.login('u1');
      expect(calls.single.arguments, {'externalId': 'u1', 'identityHash': null});
    });

    test('updateUserJwt ve logout platforma iletilir', () async {
      await Pushizo.updateUserJwt('h.p.s3');
      await Pushizo.logout();
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
      await expectLater(Pushizo.updateUserJwt('h.p.s'), throwsA(isA<PlatformException>()));
      await expectLater(Pushizo.login('u1', identityHash: 'h'), throwsA(isA<PlatformException>()));
    });
  });

  group('Live Activities (iOS)', () {
    test('setup ve start çağrıları argümanlarıyla platforma iletilir', () async {
      await Pushizo.LiveActivities.setupDefaultLiveActivity();
      await Pushizo.LiveActivities.startDefaultLiveActivity(
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
      final live = Pushizo.LiveActivities;
      expect(() => live.startDefaultLiveActivity('', {}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('a' * 101, {}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order 42', {}, {}), throwsArgumentError);
      expect(() => live.startDefaultLiveActivity('order_42', {'pushizo': 'x'}, {}), throwsArgumentError);
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
        Pushizo.LiveActivities.setupDefaultLiveActivity(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'PLATFORM_NOT_SUPPORTED')),
      );
      await expectLater(
        Pushizo.LiveActivities.startDefaultLiveActivity('order_42', {'title': 'x'}, {'status': 'y'}),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'LIVE_ACTIVITY_FAILED')),
      );
    });

    test('yerel köprüler: iOS SDK çağrıları ve Android PLATFORM_NOT_SUPPORTED', () {
      // Yerel kod bu ortamda derlenemediğinden sözleşme kaynak metni üzerinden doğrulanır (CRLF normalize edilir).
      String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final swift = read('ios/Classes/PushizoFlutterPlugin.swift');
      expect(swift, contains('case "setupDefaultLiveActivity":'));
      expect(swift, contains('try Pushizo.LiveActivities.setupDefaultLiveActivity()'));
      expect(swift, contains('try Pushizo.LiveActivities.startDefaultLiveActivity(activityId:'));
      expect(swift, contains('catch let error as HSLiveActivityError'));
      expect(swift, contains('FlutterError(code: error.code, message: error.message, details: nil)'));
      expect(swift, contains('"LIVE_ACTIVITY_FAILED"'));
      final kt = read('android/src/main/kotlin/com/pushizo/pushizo_flutter/PushizoFlutterPlugin.kt');
      expect(kt, contains('"setupDefaultLiveActivity", "startDefaultLiveActivity" ->'));
      expect(kt, contains('result.error(LIVE_ACTIVITY_UNSUPPORTED_CODE, LIVE_ACTIVITY_UNSUPPORTED_MESSAGE, null)'));
      expect(kt, contains('LIVE_ACTIVITY_UNSUPPORTED_CODE = "PLATFORM_NOT_SUPPORTED"'));
    });
  });

  test('web başlatma seçenekleri yalnızca verildiğinde iletilir', () async {
    await Pushizo.initialize(
      'app_1',
      web: const PushizoWebOptions(serviceWorkerPath: '/sw/PushizoSDKWorker.js', allowLocalhostAsSecureOrigin: true),
    );
    expect(calls.single.arguments, {
      'appId': 'app_1',
      'apiUrl': 'https://api.pushizo.com',
      'requiresPrivacyConsent': false,
      'logLevel': 'warn',
      'web': {'serviceWorkerPath': '/sw/PushizoSDKWorker.js', 'allowLocalhostAsSecureOrigin': true},
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
      await Pushizo.Location.setShared(true);
      expect(await Pushizo.Location.isShared, isTrue);
      expect(await Pushizo.Location.requestPermission(rationale: 'Yakındaki mağazalar için'), isTrue);
      await Pushizo.Location.requestPermission();
      await Pushizo.Location.setShared(false);
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
      expect(await Pushizo.Location.isShared, isFalse);
      expect(await Pushizo.Location.requestPermission(), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'HS_ERROR', message: 'Konum izni isteği zaten sürüyor');
      });
      await expectLater(
        Pushizo.Location.requestPermission(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'HS_ERROR')),
      );
    });

    test('yerel köprüler: Android izin akışı ve iOS SDK çağrıları', () {
      // Yerel kod bu ortamda derlenemediğinden sözleşme kaynak metni üzerinden doğrulanır (CRLF normalize edilir).
      String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final kt = read('android/src/main/kotlin/com/pushizo/pushizo_flutter/PushizoFlutterPlugin.kt');
      expect(kt, contains('"setLocationShared" -> { Pushizo.Location.setShared(call.argument<Boolean>("shared") ?: false)'));
      expect(kt, contains('"getLocationShared" -> result.success(Pushizo.Location.isShared)'));
      expect(kt, contains('"requestLocationPermission" -> requestLocationPermission(call.argument<String>("rationale"), result)'));
      // 1) izin varsa onPermissionResult + true; 2) manifest izinleri; 3) Activity yoksa false.
      expect(kt, contains('if (Pushizo.Location.permissionGranted) {\n            Pushizo.Location.onPermissionResult()\n            result.success(true)'));
      expect(kt, contains('PackageManager.GET_PERMISSIONS'));
      expect(kt, contains('listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)'));
      expect(kt, contains('val act = activity ?: return result.success(false)'));
      // 4) SDK string kaynaklarıyla açıklama diyaloğu; vazgeçme false.
      expect(kt, contains('AlertDialog.Builder(act)'));
      expect(kt, contains('com.pushizo.sdk.R.string.hs_location_rationale_title'));
      expect(kt, contains('rationale?.takeIf { it.isNotBlank() } ?: act.getString(com.pushizo.sdk.R.string.hs_location_rationale_message)'));
      expect(kt, contains('com.pushizo.sdk.R.string.hs_location_rationale_continue'));
      expect(kt, contains('com.pushizo.sdk.R.string.hs_location_rationale_not_now'));
      expect(kt, contains('.setOnDismissListener { if (!proceeded) result.success(false) }'));
      // 5) sistem izni SDK istek koduyla; sonuçta onPermissionResult ve permissionGranted.
      expect(kt, contains('act.requestPermissions(permissions.toTypedArray(), Pushizo.Location.PERMISSION_REQUEST_CODE)'));
      expect(kt, contains('binding.addRequestPermissionsResultListener(this)'));
      expect(kt, contains(
        'if (requestCode == Pushizo.Location.PERMISSION_REQUEST_CODE) {\n'
        '            Pushizo.Location.onPermissionResult()\n'
        '            pendingLocationPermission?.success(Pushizo.Location.permissionGranted)',
      ));
      final swift = read('ios/Classes/PushizoFlutterPlugin.swift');
      expect(swift, contains('case "setLocationShared": Pushizo.Location.setShared(args["shared"] as? Bool ?? false); result(nil)'));
      expect(swift, contains('case "getLocationShared": result(Pushizo.Location.isShared)'));
      expect(swift, contains('Pushizo.Location.requestPermission(rationale: args["rationale"] as? String) { granted in result(granted) }'));
    });
  });

  group('Bölge izleme', () {
    test('setGeofencingEnabled ve isGeofencingEnabled platforma iletilir; varsayılan kapalı', () async {
      expect(await Pushizo.Location.isGeofencingEnabled, isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'getGeofencingEnabled' ? true : null;
      });
      await Pushizo.Location.setGeofencingEnabled(true);
      expect(await Pushizo.Location.isGeofencingEnabled, isTrue);
      await Pushizo.Location.setGeofencingEnabled(false);
      expect(calls.map((c) => c.method).toList(), ['getGeofencingEnabled', 'setGeofencingEnabled', 'getGeofencingEnabled', 'setGeofencingEnabled']);
      expect(calls[1].arguments, {'enabled': true});
      expect(calls[2].arguments, isNull);
      expect(calls[3].arguments, {'enabled': false});
    });

    test('yerel köprüler: Android ve iOS SDK çağrıları; izin yalnızca açık çağrıyla istenir, manifest\'e izin eklenmez', () {
      String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final kt = read('android/src/main/kotlin/com/pushizo/pushizo_flutter/PushizoFlutterPlugin.kt');
      expect(kt, contains('"setGeofencingEnabled" -> { Pushizo.Location.setGeofencingEnabled(call.argument<Boolean>("enabled") ?: false); result.success(null) }'));
      expect(kt, contains('"getGeofencingEnabled" -> result.success(Pushizo.Location.isGeofencingEnabled)'));
      // Arka plan izni yalnızca `requestLocationBackgroundPermission` ile istenir; izlemeyi açmak izin istemi açmaz.
      expect(RegExp('ACCESS_BACKGROUND_LOCATION').allMatches(kt.substring(0, kt.indexOf('* Arka plan konum izni (bölge izleme)'))), isEmpty);
      expect(read('android/src/main/AndroidManifest.xml'), isNot(contains('uses-permission')));
      final swift = read('ios/Classes/PushizoFlutterPlugin.swift');
      expect(swift, contains('case "setGeofencingEnabled": Pushizo.Location.setGeofencingEnabled(args["enabled"] as? Bool ?? false); result(nil)'));
      expect(swift, contains('case "getGeofencingEnabled": result(Pushizo.Location.isGeofencingEnabled)'));
      expect(RegExp('requestAlwaysPermission').allMatches(swift), hasLength(1));
      expect(swift, contains('case "requestLocationBackgroundPermission":\n            Pushizo.Location.requestAlwaysPermission'));
    });
  });

  group('Özellik bayrakları', () {
    test('refresh, isEnabled ve getValue platforma iletilir; JSON değer çözülür', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'featureFlagsRefresh' => true,
          'featureFlagsIsEnabled' => true,
          'featureFlagsGetValue' => switch ((call.arguments as Map)['key']) {
              'limit' => '{"value":3}',
              'theme' => '{"value":{"color":"#112233","sizes":[1,2.5]}}',
              'label' => '{"value":"Yeni"}',
              _ => null,
            },
          _ => null,
        };
      });
      expect(await Pushizo.FeatureFlags.refresh(), isTrue);
      expect(await Pushizo.FeatureFlags.isEnabled('new_checkout'), isTrue);
      expect(await Pushizo.FeatureFlags.isEnabled('beta', defaultValue: true), isTrue);
      expect(await Pushizo.FeatureFlags.getValue('limit'), 3);
      expect(await Pushizo.FeatureFlags.getValue('theme'), {'color': '#112233', 'sizes': [1, 2.5]});
      expect(await Pushizo.FeatureFlags.getValue('label'), 'Yeni');
      expect(await Pushizo.FeatureFlags.getValue('missing'), isNull);
      expect(await Pushizo.FeatureFlags.getValue('missing', defaultValue: 'x'), 'x');
      expect(calls.map((c) => c.method).toList(), [
        'featureFlagsRefresh', 'featureFlagsIsEnabled', 'featureFlagsIsEnabled',
        'featureFlagsGetValue', 'featureFlagsGetValue', 'featureFlagsGetValue', 'featureFlagsGetValue', 'featureFlagsGetValue',
      ]);
      expect(calls[0].arguments, isNull);
      expect(calls[1].arguments, {'key': 'new_checkout', 'defaultValue': false});
      expect(calls[2].arguments, {'key': 'beta', 'defaultValue': true});
      expect(calls[3].arguments, {'key': 'limit'});
    });

    test('yerel sonuç yoksa varsayılanlar döner', () async {
      expect(await Pushizo.FeatureFlags.refresh(), isFalse);
      expect(await Pushizo.FeatureFlags.isEnabled('x'), isFalse);
      expect(await Pushizo.FeatureFlags.isEnabled('x', defaultValue: true), isTrue);
      expect(await Pushizo.FeatureFlags.getValue('x', defaultValue: 7), 7);
    });

    test('yerel köprüler: Android ve iOS SDK çağrıları ve JSON taşıma', () {
      String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final kt = read('android/src/main/kotlin/com/pushizo/pushizo_flutter/PushizoFlutterPlugin.kt');
      expect(kt, contains('"featureFlagsRefresh" -> Pushizo.FeatureFlags.refresh { ok -> main.post { result.success(ok) } }'));
      expect(kt, contains('Pushizo.FeatureFlags.isEnabled(call.argument<String>("key").orEmpty(), call.argument<Boolean>("defaultValue") ?: false)'));
      expect(kt, contains('Pushizo.FeatureFlags.getValue(call.argument<String>("key").orEmpty())?.let { JSONObject().put("value", it).toString() }'));
      final swift = read('ios/Classes/PushizoFlutterPlugin.swift');
      expect(swift, contains('Task { let ok = await Pushizo.FeatureFlags.refresh(); DispatchQueue.main.async { result(ok) } }'));
      expect(swift, contains('Pushizo.FeatureFlags.isEnabled(args["key"] as? String ?? "", default: args["defaultValue"] as? Bool ?? false)'));
      expect(swift, contains('Self.flagValueJson(Pushizo.FeatureFlags.value(args["key"] as? String ?? ""))'));
      expect(swift, contains('let wrapped: [String: Any] = ["value": value]'));
    });
  });

  group('Yerleşimler', () {
    Map<String, Object?> message(String id, {String? variant}) => {
          'id': id,
          'priority': 1,
          'variant_id': ?variant,
          'display': {
            'layout': 'banner_top',
            'blocks': [
              {'type': 'title', 'text': 'Kampanya'},
              {'type': 'button', 'id': 'go', 'text': 'İncele', 'action': {'type': 'url', 'url': 'https://pushizo.com'}},
            ],
          },
        };

    test('list anahtar ve limit ile platforma gider; JSON mesajlar modele çözülür', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method != 'placementsList') return null;
        return [jsonEncode(message('m1', variant: 'var_b')), jsonEncode(message('m2'))];
      });
      final messages = await Pushizo.Placements.list('home_top', limit: 2);
      expect(calls.single.arguments, {'key': 'home_top', 'limit': 2});
      expect(messages.map((m) => m.id).toList(), ['m1', 'm2']);
      expect(messages.first.variantId, 'var_b');
      expect(messages.first.layout, PushizoInAppLayout.bannerTop);
      expect(messages.first.buttons.single.id, 'go');
      expect(messages.first.buttons.single.action.url, 'https://pushizo.com');

      await Pushizo.Placements.reportImpression(messages.first);
      await Pushizo.Placements.reportClick(messages.first, 'go');
      await Pushizo.Placements.reportDismiss(messages[1]);
      expect(calls.map((c) => c.method).toList(), [
        'placementsList', 'placementsReportImpression', 'placementsReportClick', 'placementsReportDismiss',
      ]);
      expect(calls[1].arguments, {'messageId': 'm1'});
      expect(calls[2].arguments, {'messageId': 'm1', 'buttonId': 'go'});
      expect(calls[3].arguments, {'messageId': 'm2'});
    });

    test('varsayılan limit 1; yerel sonuç yoksa boş liste', () async {
      expect(await Pushizo.Placements.list('home_top'), isEmpty);
      expect(calls.single.arguments, {'key': 'home_top', 'limit': 1});
    });

    test('geçersiz anahtar ve limit platforma gitmeden ArgumentError fırlatır', () async {
      for (final key in ['', 'Home', '1abc', 'a' * 65, 'home top', 'home/top']) {
        await expectLater(Pushizo.Placements.list(key), throwsArgumentError, reason: key);
      }
      await expectLater(Pushizo.Placements.list('home_top', limit: 0), throwsArgumentError);
      await expectLater(Pushizo.Placements.list('home_top', limit: 11), throwsArgumentError);
      expect(calls, isEmpty);
      await Pushizo.Placements.list('a');
      await Pushizo.Placements.list('a.b-c_d9', limit: 10);
      expect(calls, hasLength(2));
    });

    test('yerel hata PlatformException olarak iletilir', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'HS_FORBIDDEN', message: 'Yasak');
      });
      await expectLater(
        Pushizo.Placements.list('home_top'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'HS_FORBIDDEN')),
      );
    });

    test('yerel köprüler: SDK çağrıları, kimliğe göre sınırlı önbellek ve bulunamayan mesajın yok sayılması', () {
      String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final kt = read('android/src/main/kotlin/com/pushizo/pushizo_flutter/PushizoFlutterPlugin.kt');
      expect(kt, contains('"placementsList" -> Pushizo.Placements.list(call.argument<String>("key").orEmpty(), call.argument<Int>("limit") ?: 1) { messages ->'));
      expect(kt, contains('rememberPlacementMessages(messages)\n                        result.success(messages.map { it.toJson() })'));
      expect(kt, contains('placementMessage(call)?.let { Pushizo.Placements.reportImpression(it) }'));
      expect(kt, contains('placementMessage(call)?.let { Pushizo.Placements.reportClick(it, call.argument<String>("buttonId").orEmpty()) }'));
      expect(kt, contains('placementMessage(call)?.let { Pushizo.Placements.reportDismiss(it) }'));
      expect(kt, contains('const val MAX_PLACEMENT_MESSAGES = 50'));
      expect(kt, contains('while (placementMessages.size > MAX_PLACEMENT_MESSAGES) placementMessages.remove(placementMessages.keys.first())'));
      expect(kt, contains('return placementMessages[id] ?: run { HsLog.d('));
      final swift = read('ios/Classes/PushizoFlutterPlugin.swift');
      expect(swift, contains('let messages = try await Pushizo.Placements.list(key, limit: limit)'));
      expect(swift, contains('await MainActor.run { self.rememberPlacementMessages(messages) }'));
      expect(swift, contains('return messages.compactMap { Self.json(\$0) }'));
      expect(swift, contains('if let message = placementMessage(args) { Pushizo.Placements.reportImpression(message) }'));
      expect(swift, contains('if let message = placementMessage(args) { Pushizo.Placements.reportClick(message, buttonId: args["buttonId"] as? String ?? "") }'));
      expect(swift, contains('if let message = placementMessage(args) { Pushizo.Placements.reportDismiss(message) }'));
      expect(swift, contains('private static let maxPlacementMessages = 50'));
      // Yerel SDK'nın geçersiz anahtar/limit hatası INVALID_ARGUMENT olarak döner.
      expect(swift, contains('} catch HSError.invalidArgument(let message) {\n                DispatchQueue.main.async { result(FlutterError(code: "INVALID_ARGUMENT"'));
    });
  });

  test('alias çağrıları platforma iletilir', () async {
    await Pushizo.User.addAlias('crm_id', '42');
    await Pushizo.User.addAliases({'shop_id': '7', 'erp_id': 'x'});
    await Pushizo.User.removeAlias('crm_id');
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
        'pushizo_flutter',
        codec.encodeMethodCall(MethodCall('foregroundWillDisplay', {'notification': notification})),
        (data) => completer.complete(data == null ? null : codec.decodeEnvelope(data)),
      );
      return completer.future;
    }

    tearDown(() => Pushizo.Notifications.setForegroundWillDisplayHandler(null));

    test('preventDefault gösterimi engeller, işleyici bildirimi alır', () async {
      PushizoNotification? seen;
      await Pushizo.Notifications.setForegroundWillDisplayHandler((event) {
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
      await Pushizo.Notifications.setForegroundWillDisplayHandler((event) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        event.preventDefault();
      });
      expect(await nativeAsks({'title': 'T'}), isTrue);

      await Pushizo.Notifications.setForegroundWillDisplayHandler((event) => throw StateError('x'));
      expect(await nativeAsks({'title': 'T'}), isFalse);
    });

    test('işleyici kaldırılınca yerel tarafa bildirilir', () async {
      await Pushizo.Notifications.setForegroundWillDisplayHandler((event) {});
      await Pushizo.Notifications.setForegroundWillDisplayHandler(null);
      expect(calls.last.arguments, {'enabled': false});
    });
  });

  test('bildirim tepsisi çağrıları platforma iletilir', () async {
    await Pushizo.Notifications.clearAll();
    await Pushizo.Notifications.removeNotification(42);
    await Pushizo.Notifications.removeGroupedNotifications('orders');
    expect(calls.map((c) => c.method).toList(), ['clearAll', 'removeNotification', 'removeGroupedNotifications']);
    expect(calls[1].arguments, {'id': 42});
    expect(calls[2].arguments, {'group': 'orders'});
    final n = PushizoNotification.fromMap({'title': 'T', 'androidNotificationId': 7});
    expect(n.androidNotificationId, 7);
    expect(PushizoNotification.fromMap({'title': 'T'}).androidNotificationId, isNull);
  });

  test('izin değişiklikleri akışa ve gözlemcilere iletilir', () async {
    MockStreamHandlerEventSink? sink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('pushizo_flutter/events'),
      MockStreamHandler.inline(onListen: (arguments, events) => sink = events),
    );
    final streamed = <bool>[];
    final seen = <bool>[];
    void observer(bool granted) {
      seen.add(granted);
    }
    final subscription = Pushizo.Notifications.permissionStream.listen(streamed.add);
    Pushizo.Notifications.addPermissionObserver(observer);
    Pushizo.Notifications.addPermissionObserver(observer);
    await pumpEventQueue();

    sink!.success({'type': 'subscription', 'state': {'id': 'sub_1', 'optedIn': true, 'permission': true}});
    sink!.success({'type': 'permission', 'permission': true});
    sink!.success({'type': 'permission', 'permission': false});
    await pumpEventQueue();
    expect(streamed, [true, false]);
    expect(seen, [true, false], reason: 'aynı gözlemci bir kez eklenir');

    Pushizo.Notifications.removePermissionObserver(observer);
    sink!.success({'type': 'permission', 'permission': true});
    await pumpEventQueue();
    expect(seen, [true, false]);
    expect(streamed, [true, false, true]);
    await subscription.cancel();
  });

  test('modeller haritadan oluşur', () {
    final click = PushizoClickEvent.fromMap({
      'notification': {'title': 'T', 'body': 'B', 'url': 'myapp://x', 'deliveryId': 'dlv_1', 'data': {'k': 'v'}},
      'actionId': 'open',
      'url': 'https://x',
    });
    expect(click.notification.deliveryId, 'dlv_1');
    expect(click.notification.data, {'k': 'v'});
    expect(click.url, 'https://x');
  });

  group('Android teslimat güçlendirme (ADR-0092)', () {
    void mock(Object? Function(MethodCall call) reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply(call);
      });
    }

    test('status yerel durumu modele çevirir', () async {
      mock((call) => {
            'supported': true,
            'manufacturer': 'xiaomi',
            'brand': 'redmi',
            'vendor': 'xiaomi',
            'aggressiveVendor': true,
            'rom': 'hyperos',
            'romVersion': '1.0.2.0',
            'notificationsEnabled': true,
            'channelBlocked': false,
            'batteryOptimizationExempt': false,
            'backgroundRestricted': false,
            'standbyBucket': 'rare',
            'powerSaveMode': true,
            'dataSaverEnabled': false,
            'restricted': true,
            'risk': 'elevated',
            'recommendedSettings': ['auto_start', 'battery_optimization', 'gelecek_ekran'],
          });
      final status = await Pushizo.Delivery.status();
      expect(calls.single.method, 'deliveryStatus');
      expect(status.supported, isTrue);
      expect(status.manufacturer, 'xiaomi');
      expect(status.brand, 'redmi');
      expect(status.vendor, 'xiaomi');
      expect(status.aggressiveVendor, isTrue);
      expect(status.rom, 'hyperos');
      expect(status.romVersion, '1.0.2.0');
      expect(status.notificationsEnabled, isTrue);
      expect(status.batteryOptimizationExempt, isFalse);
      expect(status.standbyBucket, 'rare');
      expect(status.powerSaveMode, isTrue);
      expect(status.restricted, isTrue);
      expect(status.risk, PushizoDeliveryRisk.elevated);
      // Bu sürümün tanımadığı ekran atlanır.
      expect(status.recommendedSettings, [PushizoDeliverySetting.autoStart, PushizoDeliverySetting.batteryOptimization]);
    });

    test('yerel durum yoksa (iOS, web, başlatılmamış SDK) desteklenmiyor ve risk yok', () async {
      mock((call) => null);
      final status = await Pushizo.Delivery.status();
      expect(status.supported, isFalse);
      expect(status.risk, PushizoDeliveryRisk.none);
      expect(status.restricted, isFalse);
      expect(status.recommendedSettings, isEmpty);
      expect(status.vendor, 'other');
      expect(identical(status, PushizoDeliveryStatus.unsupported), isTrue);
      // Platform `false` yerine boş yanıt verse de çağrılar `false` döner.
      expect(await Pushizo.Delivery.shouldShowGuidance(), isFalse);
      expect(await Pushizo.Delivery.openSettings(), isFalse);
      expect(await Pushizo.Delivery.showGuidance(), isFalse);
    });

    test('openSettings, showGuidance ve shouldShowGuidance argümanları kanal değerleriyle iletilir', () async {
      mock((call) => true);
      expect(await Pushizo.Delivery.shouldShowGuidance(), isTrue);
      expect(await Pushizo.Delivery.shouldShowGuidance(minIntervalDays: 30), isTrue);
      expect(await Pushizo.Delivery.openSettings(), isTrue);
      expect(await Pushizo.Delivery.openSettings(setting: PushizoDeliverySetting.autoStart), isTrue);
      expect(await Pushizo.Delivery.showGuidance(), isTrue);
      expect(
        await Pushizo.Delivery.showGuidance(setting: PushizoDeliverySetting.batteryOptimization, message: 'Bildirimleri kaçırmayın'),
        isTrue,
      );
      expect(calls.map((c) => c.method).toList(), [
        'deliveryShouldShowGuidance',
        'deliveryShouldShowGuidance',
        'deliveryOpenSettings',
        'deliveryOpenSettings',
        'deliveryShowGuidance',
        'deliveryShowGuidance',
      ]);
      expect(calls[0].arguments, {'minIntervalDays': null});
      expect(calls[1].arguments, {'minIntervalDays': 30});
      expect(calls[2].arguments, {'setting': 'auto'});
      expect(calls[3].arguments, {'setting': 'auto_start'});
      expect(calls[4].arguments, {'setting': 'auto', 'message': null});
      expect(calls[5].arguments, {'setting': 'battery_optimization', 'message': 'Bildirimleri kaçırmayın'});
    });

    test('ayar ekranı kanal değerleri yerel HsDeliverySetting adlarıyla eşleşir', () {
      expect(PushizoDeliverySetting.values.map((s) => s.wire).toList(),
          ['auto', 'notifications', 'auto_start', 'battery_optimization', 'app_details']);
    });
  });

  group('Yerel API eşitliği', () {
    void respond(Object? Function(MethodCall call) reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply(call);
      });
    }

    String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

    test('profille login: profil alanları yalnızca verildiğinde iletilir', () async {
      await Pushizo.login(
        'u1',
        jwt: 'tok',
        profile: const PushizoUserProfile(email: 'ali@pushizo.com', sms: '+905321234567', tags: {'plan': 'pro'}, aliases: {'crm_id': '42'}),
      );
      await Pushizo.login('u2', profile: const PushizoUserProfile(email: 'a@b.co'));
      await Pushizo.login('u3');
      expect(calls[0].arguments, {
        'externalId': 'u1',
        'identityHash': null,
        'jwt': 'tok',
        'profile': {'email': 'ali@pushizo.com', 'sms': '+905321234567', 'tags': {'plan': 'pro'}, 'aliases': {'crm_id': '42'}},
      });
      expect(calls[1].arguments, {'externalId': 'u2', 'identityHash': null, 'profile': {'email': 'a@b.co'}});
      expect(calls[2].arguments, {'externalId': 'u3', 'identityHash': null});
    });

    test('isInitialized, emails, smsNumbers ve registerAdm', () async {
      respond((call) => switch (call.method) {
            'isInitialized' => true,
            'getEmails' => ['ali@pushizo.com'],
            'getSmsNumbers' => ['+905321234567'],
            _ => null,
          });
      expect(await Pushizo.isInitialized, isTrue);
      expect(await Pushizo.User.emails, ['ali@pushizo.com']);
      expect(await Pushizo.User.smsNumbers, ['+905321234567']);
      await Pushizo.User.registerAdm('amzn1.adm-registration.v3.X');
      expect(calls.map((c) => c.method).toList(), ['isInitialized', 'getEmails', 'getSmsNumbers', 'registerAdm']);
      expect(calls.last.arguments, {'token': 'amzn1.adm-registration.v3.X'});
    });

    test('yerel sonuç yoksa güvenli varsayılanlar döner', () async {
      expect(await Pushizo.isInitialized, isFalse);
      expect(await Pushizo.User.emails, isEmpty);
      expect(await Pushizo.User.smsNumbers, isEmpty);
      expect(await Pushizo.User.getConsents(), isEmpty);
      expect(await Pushizo.Location.permissionGranted, isFalse);
      expect(await Pushizo.Location.backgroundPermissionGranted, isFalse);
      expect(await Pushizo.Location.requestBackgroundPermission(), isFalse);
      expect(await Pushizo.Location.requestAlwaysPermission(), isFalse);
      expect(await Pushizo.Chat.isListening, isFalse);
    });

    test('reklam rızası, rıza kayıtları ve reklam kimliği', () async {
      respond((call) => switch (call.method) {
            'setAdsPersonalizationConsent' => {
                'data': [
                  {'category': 'promos', 'channel': null, 'optedIn': true, 'explicit': true, 'source': 'sdk', 'updatedAt': 1700000000000},
                ],
                'categories': <Object?>[],
              },
            'getConsents' => [
                {'purpose': 'ads_personalization', 'granted': true, 'source': 'sdk', 'updatedAt': 1700000000000},
                {'purpose': 'other', 'granted': false, 'source': null, 'updatedAt': null},
              ],
            _ => null,
          });
      final prefs = await Pushizo.User.setAdsPersonalizationConsent(true);
      expect(prefs.preferences.single.category, 'promos');
      final consents = await Pushizo.User.getConsents();
      expect(consents.map((c) => '${c.purpose}/${c.granted}/${c.source}'), ['ads_personalization/true/sdk', 'other/false/null']);
      expect(consents.first.updatedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
      expect(consents.last.updatedAt, isNull);
      await Pushizo.Ads.setAdvertisingId('38400000-8cf0-11bd-b23e-10b96e40000d');
      await Pushizo.Ads.setAdvertisingId(null);
      expect(calls.map((c) => c.method).toList(), ['setAdsPersonalizationConsent', 'getConsents', 'setAdvertisingId', 'setAdvertisingId']);
      expect(calls[0].arguments, {'granted': true});
      expect(calls[2].arguments, {'id': '38400000-8cf0-11bd-b23e-10b96e40000d'});
      expect(calls[3].arguments, {'id': null});
    });

    test('rozet: setBadgeCount ve clearBadge; negatif değer platforma gitmeden reddedilir', () async {
      await Pushizo.Notifications.setBadgeCount(3);
      await Pushizo.Notifications.clearBadge();
      expect(() => Pushizo.Notifications.setBadgeCount(-1), throwsArgumentError);
      expect(calls.map((c) => c.method).toList(), ['setBadgeCount', 'setBadgeCount']);
      expect(calls[0].arguments, {'count': 3});
      expect(calls[1].arguments, {'count': 0});
    });

    test('konum izni durumu ve arka plan izni isteği; sohbet akışı durumu', () async {
      respond((call) => switch (call.method) {
            'getLocationPermissionGranted' || 'getLocationBackgroundPermissionGranted' => true,
            'requestLocationBackgroundPermission' => true,
            'chatIsListening' => true,
            _ => null,
          });
      expect(await Pushizo.Location.permissionGranted, isTrue);
      expect(await Pushizo.Location.backgroundPermissionGranted, isTrue);
      expect(await Pushizo.Location.requestBackgroundPermission(rationale: 'Mağazaya yaklaşınca haber veririz'), isTrue);
      expect(await Pushizo.Location.requestAlwaysPermission(), isTrue);
      expect(await Pushizo.Chat.isListening, isTrue);
      expect(calls.map((c) => c.method).toList(), [
        'getLocationPermissionGranted',
        'getLocationBackgroundPermissionGranted',
        'requestLocationBackgroundPermission',
        'requestLocationBackgroundPermission',
        'chatIsListening',
      ]);
      expect(calls[2].arguments, {'rationale': 'Mağazaya yaklaşınca haber veririz'});
      expect(calls[3].arguments, {'rationale': null});
    });

    test('yerel köprü Android: yerel SDK çağrıları, etkisiz rozet ve arka plan izni akışı', () {
      final kt = read('android/src/main/kotlin/com/pushizo/pushizo_flutter/PushizoFlutterPlugin.kt');
      expect(kt, contains('"isInitialized" -> result.success(Pushizo.isInitialized)'));
      expect(kt, contains('else Pushizo.login(externalId, userProfile(profile), call.argument<String>("identityHash"), call.argument<String>("jwt"))'));
      expect(kt, contains('HsUserProfile(\n        email = map["email"] as? String,\n        sms = map["sms"] as? String,'));
      expect(kt, contains('"getEmails" -> result.success(Pushizo.User.emails)'));
      expect(kt, contains('"getSmsNumbers" -> result.success(Pushizo.User.smsNumbers)'));
      expect(kt, contains('"registerAdm" -> { Pushizo.User.registerAdm(call.argument<String>("token").orEmpty()); result.success(null) }'));
      expect(kt, contains('Pushizo.User.setAdsPersonalizationConsent(call.argument<Boolean>("granted") ?: false, reply(result) { it.toMap() })'));
      expect(kt, contains('Pushizo.User.getConsents(reply<List<HsConsent>>(result) { list -> list.map { it.toMap() } })'));
      expect(kt, contains('"setAdvertisingId" -> { Pushizo.Ads.setAdvertisingId(call.argument<String>("id")); result.success(null) }'));
      expect(kt, contains('"setBadgeCount" -> result.success(null)'));
      expect(kt, contains('"getLocationPermissionGranted" -> result.success(Pushizo.Location.permissionGranted)'));
      expect(kt, contains('"getLocationBackgroundPermissionGranted" -> result.success(Pushizo.Location.backgroundPermissionGranted)'));
      expect(kt, contains('"chatIsListening" -> result.success(Pushizo.Chat.isListening)'));
      // Arka plan izni: verilmişse true; Android 10 öncesi normal akış; manifest'te yoksa false; diyalog ve sistem izni.
      expect(kt, contains('if (Pushizo.Location.backgroundPermissionGranted) {\n            Pushizo.Location.onPermissionResult()\n            result.success(true)'));
      expect(kt, contains('if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {\n            requestLocationPermission(rationale, result)'));
      expect(kt, contains('if (Manifest.permission.ACCESS_BACKGROUND_LOCATION !in requestedPermissions(act)) {'));
      expect(kt, contains('com.pushizo.sdk.R.string.hs_geofence_rationale_title'));
      expect(kt, contains('rationale?.takeIf { it.isNotBlank() } ?: act.getString(com.pushizo.sdk.R.string.hs_geofence_rationale_message)'));
      expect(kt, contains('act.requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), Pushizo.Location.PERMISSION_REQUEST_CODE)'));
      expect(kt, contains('pendingLocationPermission?.success(Pushizo.Location.backgroundPermissionGranted)'));
    });

    test('yerel köprü iOS: yerel SDK çağrıları, profil doğrulaması ve CoreLocation izin durumu', () {
      final swift = read('ios/Classes/PushizoFlutterPlugin.swift');
      expect(swift, contains('case "isInitialized": result(Pushizo.isInitialized)'));
      // Profil: doğrulama girişten önce, alanlar girişten sonra.
      final invalid = swift.indexOf('if let email, HSContacts.normalizeEmail(email) == nil {');
      final login = swift.indexOf('Pushizo.login(args["externalId"] as? String ?? "", identityHash: identityHash, jwt: jwt)');
      final addEmail = swift.indexOf('if let email { Pushizo.User.addEmail(email) }');
      expect(invalid, greaterThan(0));
      expect(login, greaterThan(invalid));
      expect(addEmail, greaterThan(login));
      expect(swift, contains('if let sms, HSContacts.normalizePhone(sms) == nil {'));
      expect(swift, contains('if let sms { Pushizo.User.addSms(sms) }'));
      expect(swift, contains('Pushizo.User.addTags(tags)'));
      expect(swift, contains('Pushizo.User.addAliases(aliases)'));
      expect(swift, contains('case "getEmails": result(Pushizo.User.emails)'));
      expect(swift, contains('case "getSmsNumbers": result(Pushizo.User.smsNumbers)'));
      expect(swift, contains('case "registerAdm": result(nil)'));
      expect(swift, contains('Self.map(try await Pushizo.User.setAdsPersonalizationConsent(granted))'));
      expect(swift, contains(r'try await Pushizo.User.getConsents().map { Self.map($0) }'));
      expect(swift, contains('case "setAdvertisingId": Pushizo.Ads.setAdvertisingId(args["id"] as? String); result(nil)'));
      expect(swift, contains('Pushizo.Notifications.setBadgeCount(max(0, (args["count"] as? NSNumber)?.intValue ?? 0))'));
      expect(swift, contains('case "getLocationPermissionGranted": result(Self.locationPermission(background: false))'));
      expect(swift, contains('case "getLocationBackgroundPermissionGranted": result(Self.locationPermission(background: true))'));
      expect(swift, contains('return status == .authorizedAlways || (!background && status == .authorizedWhenInUse)'));
      expect(swift, contains('Pushizo.Location.requestAlwaysPermission { granted in result(granted) }'));
      expect(swift, contains('case "chatIsListening": result(Pushizo.Chat.isListening)'));
    });
  });
}
