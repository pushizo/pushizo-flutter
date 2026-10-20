import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pushizo_flutter/pushizo_flutter.dart';

/// Canlı sohbet köprüsü (kanal argümanları, yanıt ayrıştırma, olay akışları). EventChannel süreç başına bir kez açıldığından
/// olay testleri bu dosyada tutulur.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pushizo_flutter');
  final calls = <MethodCall>[];
  MockStreamHandlerEventSink? sink;

  final message = <String, Object?>{
    'id': 'cmsg_1',
    'seq': 12,
    'clientMessageId': 'm_abcdefgh',
    'sender': 'bot',
    'authorName': 'Asistan',
    'text': 'Seçin',
    'attachments': [
      {'id': 'att_1', 'name': 'a.png', 'type': 'image/png', 'size': 2048},
    ],
    'quickReplies': [
      {'id': 'o1', 'label': 'Satış'},
    ],
    'status': 'delivered',
    'createdAt': 1792490400000,
  };
  final conversation = <String, Object?>{
    'id': 'conv_1',
    'status': 'open',
    'lastSeq': 12,
    'agentLastReadSeq': 10,
    'visitorLastReadSeq': 11,
    'unreadCount': 1,
    'botActive': true,
    'assigneeName': null,
    'createdAt': 1792490340000,
  };

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('pushizo_flutter/events'),
      MockStreamHandler.inline(onListen: (arguments, events) => sink = events),
    );
  });

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'chatStart':
          return {'userId': 'usr_1', 'conversation': conversation};
        case 'chatGetConfig':
          return {
            'enabled': true,
            'online': false,
            'withinBusinessHours': false,
            'position': 'left',
            'theme': 'dark',
            'offlineMessage': 'Şu an çevrimdışıyız',
            'collectEmailOffline': true,
            'requireEmail': false,
            'attachmentsEnabled': true,
            'attachmentMaxBytes': 10485760,
            'attachmentTypes': ['image/png'],
            'language': 'tr',
          };
        case 'chatGetConversation':
          return {'conversation': null, 'unreadCount': 0};
        case 'chatGetMessages':
          return {
            'messages': [message],
            'hasMore': true,
          };
        case 'chatSendMessage':
        case 'chatSendAttachment':
        case 'chatLeaveOfflineMessage':
          return message;
        case 'chatMarkRead':
        case 'chatRefreshUnreadCount':
        case 'chatGetUnreadCount':
          return 3;
        case 'chatAttachmentUrl':
          return 'https://api.example.com/sdk/v1/apps/app_1/chat/attachments/att_1?visitor_id=v&token=t';
        default:
          return null;
      }
    });
  });

  test('başlatma, ayar ve konuşma yanıtları ayrıştırılır', () async {
    final started = await Pushizo.Chat.start(name: 'Ali', language: 'tr');
    expect(calls.last.arguments, {'name': 'Ali', 'language': 'tr'});
    expect(started.userId, 'usr_1');
    expect(started.conversation?.botActive, isTrue);
    expect(started.conversation?.createdAt, DateTime.fromMillisecondsSinceEpoch(1792490340000, isUtc: true));

    final config = await Pushizo.Chat.getConfig();
    expect(calls.last.arguments, <String, Object?>{});
    expect(config.online, isFalse);
    expect(config.offlineMessage, 'Şu an çevrimdışıyız');
    expect(config.attachmentMaxBytes, 10485760);

    final state = await Pushizo.Chat.getConversation();
    expect(state.conversation, isNull);
    expect(state.unreadCount, 0);
  });

  test('mesaj okuma ve gönderim argümanları', () async {
    final page = await Pushizo.Chat.getMessages(afterSeq: 5);
    expect(calls.last.arguments, {'afterSeq': 5, 'limit': 50});
    expect(page.hasMore, isTrue);
    final m = page.messages.single;
    expect(m.seq, 12);
    expect(m.attachments.single.size, 2048);
    expect(m.quickReplies?.single.label, 'Satış');
    expect(m.isFromVisitor, isFalse);
    expect(() => Pushizo.Chat.getMessages(limit: 101), throwsArgumentError);

    await Pushizo.Chat.sendMessage('Merhaba', optionId: 'o1');
    expect(calls.last.method, 'chatSendMessage');
    expect(calls.last.arguments, {'text': 'Merhaba', 'optionId': 'o1'});

    final bytes = Uint8List.fromList([1, 2, 3]);
    await Pushizo.Chat.sendAttachment(bytes, fileName: 'a.png', mimeType: 'image/png');
    expect(calls.last.arguments, {'bytes': bytes, 'fileName': 'a.png', 'mimeType': 'image/png'});

    await Pushizo.Chat.leaveOfflineMessage(email: 'ali@example.com', text: 'Arayın');
    expect(calls.last.arguments, {'email': 'ali@example.com', 'text': 'Arayın'});

    expect(await Pushizo.Chat.markRead(12), 3);
    expect(calls.last.arguments, {'seq': 12});
    expect(await Pushizo.Chat.refreshUnreadCount(), 3);
    expect(await Pushizo.Chat.unreadCount, 3);

    await Pushizo.Chat.setTyping(true);
    await Pushizo.Chat.startListening();
    await Pushizo.Chat.stopListening();
    expect(calls.reversed.take(3).map((c) => c.method).toList().reversed, ['chatSetTyping', 'chatStartListening', 'chatStopListening']);
    expect(await Pushizo.Chat.attachmentUrl('att_1'), contains('/chat/attachments/att_1'));
    expect(calls.last.arguments, {'attachmentId': 'att_1', 'download': false});
  });

  test('olay akışı türlerine göre ayrıştırılır, sohbet açma tıklaması bekletilir', () async {
    final events = <PushizoChatEvent>[];
    final sub = Pushizo.Chat.events.listen(events.add);
    final unread = <int>[];
    final unreadSub = Pushizo.Chat.unreadCountStream.listen(unread.add);
    await pumpEventQueue();

    sink!.success({'type': 'chat', 'event': 'message', 'message': message});
    sink!.success({'type': 'chat', 'event': 'typing', 'typing': true, 'name': 'Ayşe'});
    sink!.success({'type': 'chat', 'event': 'read', 'seq': 7});
    sink!.success({'type': 'chat', 'event': 'unread', 'count': 2});
    sink!.success({'type': 'chat', 'event': 'conversation', 'conversationId': 'conv_1', 'status': 'resolved', 'botActive': false});
    sink!.success({'type': 'chat', 'event': 'error', 'code': 'HS_PLAN_FEATURE_REQUIRED', 'message': null});
    // Dinleyici yokken gelen sohbet açma tıklaması kaybolmaz.
    sink!.success({'type': 'chatOpen', 'conversationId': 'conv_9', 'seq': 4});
    await pumpEventQueue();

    expect(events.map((e) => e.type).toList(), ['message', 'typing', 'read', 'unread', 'conversation', 'error']);
    expect(events[0].message?.text, 'Seçin');
    expect(events[1].typing, isTrue);
    expect(events[1].name, 'Ayşe');
    expect(events[2].seq, 7);
    expect(events[4].status, 'resolved');
    expect(events[5].code, 'HS_PLAN_FEATURE_REQUIRED');
    expect(unread, [2]);

    final opens = <PushizoChatOpenEvent>[];
    final openSub = Pushizo.Chat.openStream.listen(opens.add);
    await pumpEventQueue();
    expect(opens.single.conversationId, 'conv_9');
    expect(opens.single.seq, 4);

    await sub.cancel();
    await unreadSub.cancel();
    await openSub.cancel();
  });

  test('zaman çizelgesi birleştirme sıra numarasına göre tekilleştirir, bekleyen mesajı değiştirir', () {
    PushizoChatMessage m(int seq, {String? cmid, String status = 'sent'}) => PushizoChatMessage.fromMap({
          'id': seq > 0 ? 'msg_$seq' : null,
          'seq': seq,
          'clientMessageId': cmid,
          'sender': 'visitor',
          'attachments': const [],
          'status': status,
        });
    final merged = mergePushizoChatMessages([m(3), m(1), m(0, cmid: 'm_local001', status: 'pending')], [m(2), m(3, status: 'read')]);
    expect(merged.map((e) => e.seq).toList(), [1, 2, 3, 0]);
    expect(merged[2].status, 'read');
    final confirmed = mergePushizoChatMessages(merged, [m(4, cmid: 'm_local001')]);
    expect(confirmed.map((e) => e.seq).toList(), [1, 2, 3, 4]);
  });
}
