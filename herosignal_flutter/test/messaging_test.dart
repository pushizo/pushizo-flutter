import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herosignal_flutter/herosignal_flutter.dart';

/// E-posta/SMS, in-app ve bildirim kutusu: kanal sözleşmesi, modeller ve Dart çizimi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('herosignal_flutter');
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getTriggers':
          return {'level': 'gold'};
        case 'getInAppPaused':
          return true;
        case 'inboxList':
          return {
            'items': [
              {
                'id': 'ibx_1',
                'messageId': 'msg_1',
                'title': 'Kargo',
                'body': 'Siparişin yolda',
                'url': 'myapp://orders/1',
                'imageUrl': null,
                'data': {'order': '1'},
                'read': false,
                'readAt': null,
                'archivedAt': null,
                'expiresAt': null,
                'createdAt': 1759838400000,
              },
            ],
            'unreadCount': 1,
            'nextCursor': 'c2',
            'hasMore': true,
          };
        case 'inboxMarkRead':
          return {'id': 'ibx_1', 'read': true, 'readAt': 1759838460000, 'data': <String, String>{}};
        case 'inboxMarkAllRead':
          return 0;
        case 'inboxUnreadCount':
          return 3;
        case 'getPreferences':
        case 'setPreferences':
          return {
            'data': [
              {'category': 'promos', 'channel': null, 'optedIn': false, 'explicit': true, 'source': 'sdk', 'updatedAt': 1759838400000},
              {'category': 'orders', 'channel': 'android_push', 'optedIn': true, 'explicit': false, 'source': null, 'updatedAt': null},
            ],
            'categories': [
              {
                'key': 'promos',
                'name': {'tr': 'Kampanyalar', 'en': 'Promotions'},
                'description': {'tr': 'İndirimler'},
                'channels': ['android_push', 'email'],
                'defaultOptedIn': false,
              },
              {'key': 'orders', 'name': {'en': 'Orders'}, 'description': <String, String>{}, 'channels': null, 'defaultOptedIn': true},
            ],
          };
        default:
          return null;
      }
    });
  });

  /// Yerel SDK'dan Dart'a çağrı (in-app gösterim/kapatma).
  Future<Object?> native(String method, Map<String, Object?> args) async {
    final completer = Completer<Object?>();
    await messenger.handlePlatformMessage(
      'herosignal_flutter',
      codec.encodeMethodCall(MethodCall(method, args)),
      (data) => completer.complete(data == null ? null : codec.decodeEnvelope(data)),
    );
    return completer.future;
  }

  Map<String, Object?> message({String layout = 'modal', bool dismissible = true, int? autoDismiss, String? background}) => {
        'id': 'iam_1',
        'priority': 10,
        'triggers': [
          {'kind': 'event', 'name': 'cart_viewed'},
        ],
        'display': {
          'layout': layout,
          'background_color': background,
          'text_color': null,
          'dismissible': dismissible,
          'auto_dismiss_seconds': autoDismiss,
          'blocks': [
            {'type': 'title', 'text': 'Merhaba Ayşe'},
            {'type': 'body', 'text': 'Sepetin seni bekliyor'},
            {
              'type': 'button',
              'id': 'go',
              'text': 'Sepete git',
              'action': {'type': 'deeplink', 'url': 'myapp://cart'},
              'background_color': null,
              'text_color': null,
            },
            {
              'type': 'button',
              'id': 'bad',
              'text': 'Kötü',
              'action': {'type': 'url', 'url': 'javascript:alert(1)'},
              'background_color': null,
              'text_color': null,
            },
            {'type': 'video', 'url': 'https://cdn.example.com/x.mp4'},
          ],
        },
        'remaining_impressions': 1,
        'min_interval_seconds': 0,
        'last_impression_at': null,
        'end_at': null,
      };

  test('e-posta/SMS çağrıları platforma iletilir', () async {
    await HeroSignal.User.addEmail('Ali@Example.com');
    await HeroSignal.User.removeEmail('ali@example.com');
    await HeroSignal.User.addSms('+90 532 123 45 67');
    await HeroSignal.User.removeSms('+905321234567');
    expect(calls.map((c) => c.method).toList(), ['addEmail', 'removeEmail', 'addSms', 'removeSms']);
    expect(calls[0].arguments, {'email': 'Ali@Example.com'});
    expect(calls[2].arguments, {'phoneNumber': '+90 532 123 45 67'});
  });

  test('in-app trigger, ekran ve duraklatma çağrıları', () async {
    await HeroSignal.InAppMessages.addTrigger('level', 'gold');
    await HeroSignal.InAppMessages.removeTriggers(['a']);
    await HeroSignal.InAppMessages.clearTriggers();
    expect(await HeroSignal.InAppMessages.getTriggers(), {'level': 'gold'});
    await HeroSignal.InAppMessages.setScreen('cart');
    await HeroSignal.InAppMessages.setPaused(true);
    expect(await HeroSignal.InAppMessages.paused, isTrue);
    expect(calls.map((c) => c.method).toList(),
        ['addTriggers', 'removeTriggers', 'clearTriggers', 'getTriggers', 'setScreen', 'setInAppPaused', 'getInAppPaused']);
    expect(calls[0].arguments, {'triggers': {'level': 'gold'}});
    expect(calls[4].arguments, {'name': 'cart'});
    expect(calls[5].arguments, {'paused': true});
  });

  test('bildirim kutusu çağrıları ve modelleri', () async {
    final page = await HeroSignal.Inbox.list(limit: 20, cursor: 'c1');
    expect(calls.last.arguments, {'limit': 20, 'cursor': 'c1'});
    expect(page.unreadCount, 1);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'c2');
    final item = page.items.single;
    expect(item.title, 'Kargo');
    expect(item.data, {'order': '1'});
    expect(item.read, isFalse);
    expect(item.createdAt, DateTime.utc(2025, 10, 7, 12));
    final read = await HeroSignal.Inbox.markRead('ibx_1');
    expect(read.read, isTrue);
    expect(calls.last.arguments, {'id': 'ibx_1'});
    expect(await HeroSignal.Inbox.markAllRead(), 0);
    await HeroSignal.Inbox.archive('ibx_1');
    expect(calls.last.method, 'inboxArchive');
    expect(await HeroSignal.Inbox.unreadCount(), 3);
  });

  test('tercih çağrıları ve modelleri', () async {
    final prefs = await HeroSignal.User.getPreferences();
    expect(calls.last.method, 'getPreferences');
    expect(prefs.preferences.length, 2);
    final promos = prefs.preferences.first;
    expect(promos.channel, isNull);
    expect(promos.optedIn, isFalse);
    expect(promos.explicit, isTrue);
    expect(promos.source, 'sdk');
    expect(promos.updatedAt, DateTime.utc(2025, 10, 7, 12));
    expect(prefs.preferences[1].channel, 'android_push');
    expect(prefs.preferences[1].updatedAt, isNull);
    final cat = prefs.categories.first;
    expect(cat.localizedName('tr'), 'Kampanyalar');
    expect(cat.localizedName('de'), 'Promotions');
    expect(cat.channels, ['android_push', 'email']);
    expect(cat.defaultOptedIn, isFalse);
    expect(prefs.categories[1].channels, isNull);
    expect(prefs.categories[1].localizedName('tr'), 'Orders');

    final updated = await HeroSignal.User.setPreferences([
      const HeroSignalPreferenceInput(category: 'promos', optedIn: false),
      const HeroSignalPreferenceInput(category: 'orders', channel: 'email', optedIn: true),
    ]);
    expect(calls.last.method, 'setPreferences');
    expect(calls.last.arguments, {
      'preferences': [
        {'category': 'promos', 'channel': null, 'optedIn': false},
        {'category': 'orders', 'channel': 'email', 'optedIn': true},
      ],
    });
    expect(updated.categories.map((c) => c.key).toList(), ['promos', 'orders']);
  });

  test('in-app mesaj modeli: varyant, push_prompt ve outcome aksiyonları', () {
    final json = message();
    json['variant_id'] = 'var_b';
    (json['display'] as Map)['blocks'] = [
      {'type': 'button', 'id': 'allow', 'text': 'İzin ver', 'action': {'type': 'push_prompt'}},
      {'type': 'button', 'id': 'buy', 'text': 'Satın al', 'action': {'type': 'outcome', 'name': 'purchase', 'value': 49.9}},
      {'type': 'button', 'id': 'later', 'text': 'Sonra', 'action': {'type': 'outcome', 'name': 'remind_later'}},
      {'type': 'button', 'id': 'noname', 'text': 'Bozuk', 'action': {'type': 'outcome'}},
    ];
    final m = HeroSignalInAppMessage.fromMap(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
    expect(m.variantId, 'var_b');
    expect(m.buttons.map((b) => b.id).toList(), ['allow', 'buy', 'later']); // adsız outcome düğmesi atlanır
    expect(m.buttons[0].action.type, HeroSignalInAppActionType.pushPrompt);
    expect(m.buttons[1].action.type, HeroSignalInAppActionType.outcome);
    expect(m.buttons[1].action.outcomeName, 'purchase');
    expect(m.buttons[1].action.outcomeValue, 49.9);
    expect(m.buttons[2].action.outcomeValue, isNull);
    expect(HeroSignalInAppMessage.fromMap(message()).variantId, isNull);
  });

  test('in-app mesaj modeli: geçersiz düğme ve tanınmayan blok atlanır', () {
    final m = HeroSignalInAppMessage.fromMap(jsonDecode(jsonEncode(message(layout: 'banner_top', autoDismiss: 5))) as Map<String, dynamic>);
    expect(m.layout, HeroSignalInAppLayout.bannerTop);
    expect(m.autoDismissSeconds, 5);
    expect(m.blocks.length, 3);
    expect(m.buttons.single.id, 'go');
    expect(m.buttons.single.action.type, HeroSignalInAppActionType.deeplink);
    expect(m.buttons.single.action.url, 'myapp://cart');
    final unknown = HeroSignalInAppMessage.fromMap({'id': 'x', 'display': {'layout': 'carousel', 'blocks': []}});
    expect(unknown.layout, HeroSignalInAppLayout.modal);
    expect(unknown.dismissible, isTrue);
  });

  test('renk vektörleri yerel SDK ile aynı (sdk/testdata)', () {
    final vectors = jsonDecode(File('../../testdata/messaging-vectors.json').readAsStringSync()) as Map<String, dynamic>;
    String hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    for (final c in (vectors['colors'] as List).cast<Map<String, dynamic>>()) {
      final parsed = HeroSignalInAppColors.parse(c['input'] as String);
      expect(parsed == null ? null : hex(parsed), c['expected'], reason: c['input'] as String);
    }
    for (final c in (vectors['contrast'] as List).cast<Map<String, dynamic>>()) {
      expect(hex(HeroSignalInAppColors.contrastingText(HeroSignalInAppColors.parse(c['background'] as String)!)), c['expected']);
    }
  });

  test('olay akışından in-app tıklama ve yaşam döngüsü modelleri', () {
    final click = HeroSignalInAppClickEvent.fromMap({'type': 'inAppClick', 'messageId': 'iam_1', 'actionId': 'go', 'url': 'myapp://cart'});
    expect(click.actionId, 'go');
    expect(click.url, 'myapp://cart');
    final life = HeroSignalInAppLifecycleEvent.fromMap({'type': 'inAppLifecycle', 'event': 'didDisplay', 'messageId': 'iam_1'});
    expect(life?.type, HeroSignalInAppLifecycle.didDisplay);
    expect(HeroSignalInAppLifecycleEvent.fromMap({'event': 'other', 'messageId': 'x'}), isNull);
  });

  group('Dart in-app çizimi', () {
    Future<void> pumpApp(WidgetTester tester, {ThemeMode mode = ThemeMode.light}) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: mode,
        home: const Scaffold(body: Text('Ana ekran')),
      ));
      HeroSignal.InAppMessages.setNavigatorKey(null);
    }

    List<String> reported() => calls.where((c) => c.method.startsWith('inApp')).map((c) => c.method).toList();

    testWidgets('modal: gösterim, düğme tıklaması ve SDK kapatması', (tester) async {
      await pumpApp(tester);
      final shown = await native('inAppShow', {'json': jsonEncode(message())});
      expect(shown, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Merhaba Ayşe'), findsOneWidget);
      expect(find.text('Sepetin seni bekliyor'), findsOneWidget);
      expect(find.text('Kötü'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
      // Başlık erişilebilirlikte başlık olarak işaretlenir.
      expect(tester.getSemantics(find.text('Merhaba Ayşe')).flagsCollection.isHeader, isTrue);
      expect(reported(), ['inAppDisplayed']);

      // Aynı anda ikinci mesaj gösterilmez.
      expect(await native('inAppShow', {'json': jsonEncode(message())}), isFalse);

      await tester.tap(find.text('Sepete git'));
      await tester.pump();
      expect(calls.last.method, 'inAppButtonClicked');
      expect(calls.last.arguments, {'messageId': 'iam_1', 'buttonId': 'go'});

      // İkinci etkileşim yok sayılır.
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      expect(reported(), ['inAppDisplayed', 'inAppButtonClicked']);

      await native('inAppClose', {'messageId': 'iam_1'});
      await tester.pumpAndSettle();
      expect(find.text('Merhaba Ayşe'), findsNothing);
      expect(find.text('Ana ekran'), findsOneWidget);
      expect(reported().last, 'inAppClosed');
    });

    testWidgets('modal: geri tuşu kapatma bildirir, kapatılamaz mesajda yok sayılır', (tester) async {
      await pumpApp(tester);
      await native('inAppShow', {'json': jsonEncode(message())});
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls.last.method, 'inAppDismissed');
      expect(find.text('Merhaba Ayşe'), findsOneWidget); // kapanış SDK'dan gelir
      await native('inAppClose', {'messageId': 'iam_1'});
      await tester.pumpAndSettle();
      expect(find.text('Merhaba Ayşe'), findsNothing);

      calls.clear();
      await native('inAppShow', {'json': jsonEncode(message(dismissible: false))});
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing); // düğmesi olan kapatılamaz mesaj
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(reported(), ['inAppDisplayed']);
      await native('inAppClose', {'messageId': 'iam_1'});
      await tester.pumpAndSettle();
    });

    testWidgets('banner: otomatik kapanma ve koyu tema varsayılan renkleri', (tester) async {
      await pumpApp(tester, mode: ThemeMode.dark);
      await native('inAppShow', {'json': jsonEncode(message(layout: 'banner_bottom', autoDismiss: 3))});
      await tester.pumpAndSettle();
      expect(find.text('Merhaba Ayşe'), findsOneWidget);
      final material = tester.widget<Material>(find.ancestor(of: find.text('Merhaba Ayşe'), matching: find.byType(Material)).first);
      expect(material.color, HeroSignalInAppColors.darkBackground);
      final title = tester.widget<Text>(find.text('Merhaba Ayşe'));
      expect(title.style?.color, HeroSignalInAppColors.darkText);
      // Banner arkasındaki ekran kullanılabilir kalır.
      expect(find.text('Ana ekran'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(calls.last.method, 'inAppDismissed');
      await native('inAppClose', {'messageId': 'iam_1'});
      await tester.pumpAndSettle();
      expect(find.text('Merhaba Ayşe'), findsNothing);
    });

    testWidgets('özel arka planda metin kontrasta göre seçilir', (tester) async {
      await pumpApp(tester);
      await native('inAppShow', {'json': jsonEncode(message(layout: 'fullscreen', background: '#18181b'))});
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Sepetin seni bekliyor')).style?.color, HeroSignalInAppColors.darkText);
      await native('inAppClose', {'messageId': 'iam_1'});
      await tester.pumpAndSettle();
    });
  });
}
