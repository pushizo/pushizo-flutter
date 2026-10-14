import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herosignal_flutter/herosignal_flutter.dart';

/// Olay akışı testleri ayrı dosyada: EventChannel akışı süreç başına bir kez açılır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('herosignal_flutter');
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  MockStreamHandlerEventSink? sink;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('herosignal_flutter/events'),
      MockStreamHandler.inline(onListen: (arguments, events) => sink = events),
    );
  });

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getSubscriptionState') {
        return {'id': 'sub_1', 'token': 'fcm_tok', 'optedIn': true, 'permission': true};
      }
      return null;
    });
  });

  Map<String, Object?> click(String deliveryId) => {
        'type': 'click',
        'notification': {'title': 'T', 'deliveryId': deliveryId, 'data': <String, String>{}},
        'actionId': null,
        'url': 'myapp://x',
      };

  test('clickStream dinlenmeden gelen tıklama ilk dinleyiciye teslim edilir', () async {
    // Akış önce başka bir dinleyiciyle açılır (ör. izin akışı); tıklama bu sırada gelir.
    final permission = HeroSignal.Notifications.permissionStream.listen((_) {});
    await pumpEventQueue();
    sink!.success(click('dlv_cold'));
    await pumpEventQueue();

    final seen = <String?>[];
    final subscription = HeroSignal.Notifications.clickStream.listen((e) => seen.add(e.notification.deliveryId));
    await pumpEventQueue();
    expect(seen, ['dlv_cold']);

    sink!.success(click('dlv_2'));
    await pumpEventQueue();
    expect(seen, ['dlv_cold', 'dlv_2'], reason: 'sonraki tıklamalar doğrudan iletilir, bekleyen tekrar gelmez');
    await subscription.cancel();
    await permission.cancel();
  });

  test('ön plan olayında display() yerel gösterimi tetikler', () async {
    HeroSignalForegroundEvent? captured;
    await HeroSignal.Notifications.setForegroundWillDisplayHandler((event) {
      event.preventDefault();
      captured = event;
    });
    final completer = Completer<Object?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'herosignal_flutter',
      codec.encodeMethodCall(const MethodCall('foregroundWillDisplay', {
        'notification': {'title': 'T', 'deliveryId': 'dlv_1'},
        'eventId': 'evt_1',
      })),
      (data) => completer.complete(data == null ? null : codec.decodeEnvelope(data)),
    );
    expect(await completer.future, isTrue, reason: 'preventDefault → yerel taraf göstermez');

    calls.clear();
    await captured!.display();
    await captured!.display();
    expect(calls.map((c) => c.method).toList(), ['displayForegroundNotification'], reason: 'yalnızca bir kez');
    expect(calls.single.arguments, {'eventId': 'evt_1'});

    // Yerel kimliği olmayan (elle oluşturulmuş) olayda display() çağrı yapmaz.
    calls.clear();
    await HeroSignalForegroundEvent(const HeroSignalNotification(title: 'x')).display();
    expect(calls, isEmpty);
    await HeroSignal.Notifications.setForegroundWillDisplayHandler(null);
  });

  test('pushSubscription.token durumdan okunur', () async {
    expect(await HeroSignal.User.pushSubscription.token, 'fcm_tok');
    expect(await HeroSignal.User.pushSubscription.id, 'sub_1');
  });

  test('iOS bildirimi istek kimliğiyle kaldırılır', () async {
    await HeroSignal.Notifications.removeNotificationByIdentifier('order-42');
    expect(calls.single.method, 'removeNotification');
    expect(calls.single.arguments, {'identifier': 'order-42'});
  });

  test('in-app tıklama ve yaşam döngüsü dinleyicileri eklenip kaldırılır', () async {
    final clicks = <String>[];
    final lifecycle = <HeroSignalInAppLifecycle>[];
    void onClick(HeroSignalInAppClickEvent e) => clicks.add(e.actionId);
    void onLifecycle(HeroSignalInAppLifecycleEvent e) => lifecycle.add(e.type);

    HeroSignal.InAppMessages.addClickListener(onClick);
    HeroSignal.InAppMessages.addClickListener(onClick);
    HeroSignal.InAppMessages.addLifecycleListener(onLifecycle);
    await pumpEventQueue();

    sink!.success({'type': 'inAppClick', 'messageId': 'm1', 'actionId': 'buy', 'url': null});
    sink!.success({'type': 'inAppLifecycle', 'event': 'didDisplay', 'messageId': 'm1'});
    await pumpEventQueue();
    expect(clicks, ['buy'], reason: 'aynı dinleyici bir kez eklenir');
    expect(lifecycle, [HeroSignalInAppLifecycle.didDisplay]);

    HeroSignal.InAppMessages.removeClickListener(onClick);
    HeroSignal.InAppMessages.removeLifecycleListener(onLifecycle);
    sink!.success({'type': 'inAppClick', 'messageId': 'm1', 'actionId': 'later', 'url': null});
    sink!.success({'type': 'inAppLifecycle', 'event': 'didDismiss', 'messageId': 'm1'});
    await pumpEventQueue();
    expect(clicks, ['buy']);
    expect(lifecycle, [HeroSignalInAppLifecycle.didDisplay]);
  });
}
