import 'dart:async';

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
