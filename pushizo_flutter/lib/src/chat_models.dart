part of '../pushizo_flutter.dart';

int _chatInt(Object? value) => value is num ? value.toInt() : 0;

DateTime? _chatTime(Object? value) => value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true) : null;

Map<Object?, Object?> _chatMap(Object? value) => value is Map ? Map<Object?, Object?>.from(value) : const {};

/// Sohbet mesajı eki ([_Chat.attachmentUrl] ile görüntülenir).
class PushizoChatAttachment {
  const PushizoChatAttachment({required this.id, required this.name, required this.type, required this.size});

  final String id;
  final String name;
  final String type;
  final int size;

  factory PushizoChatAttachment.fromMap(Map<Object?, Object?> map) => PushizoChatAttachment(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        type: map['type'] as String? ?? '',
        size: _chatInt(map['size']),
      );
}

/// Bot sorusunun hızlı yanıt seçeneği; seçildiğinde [_Chat.sendMessage] `optionId` ile gönderilir.
class PushizoChatQuickReply {
  const PushizoChatQuickReply({required this.id, required this.label});

  final String id;
  final String label;

  factory PushizoChatQuickReply.fromMap(Map<Object?, Object?> map) =>
      PushizoChatQuickReply(id: map['id'] as String? ?? '', label: map['label'] as String? ?? '');
}

/// Sohbet mesajı. [seq] konuşma içi sıra numarasıdır; çevrimdışı kuyrukta bekleyen yerel mesajda 0 ve [status] `pending`.
class PushizoChatMessage {
  const PushizoChatMessage({
    required this.id,
    required this.seq,
    required this.clientMessageId,
    required this.sender,
    required this.authorName,
    required this.text,
    required this.attachments,
    required this.quickReplies,
    required this.status,
    required this.createdAt,
  });

  /// Sunucu kimliği; bekleyen yerel mesajda null.
  final String? id;
  final int seq;
  final String? clientMessageId;

  /// `visitor`, `agent`, `bot` veya `system`.
  final String sender;
  final String? authorName;
  final String? text;
  final List<PushizoChatAttachment> attachments;

  /// Bot sorusunun seçenekleri (yoksa null).
  final List<PushizoChatQuickReply>? quickReplies;

  /// `pending` (yerel), `sent`, `delivered` veya `read`.
  final String status;
  final DateTime? createdAt;

  bool get isFromVisitor => sender == 'visitor';

  factory PushizoChatMessage.fromMap(Map<Object?, Object?> map) => PushizoChatMessage(
        id: map['id'] as String?,
        seq: _chatInt(map['seq']),
        clientMessageId: map['clientMessageId'] as String?,
        sender: map['sender'] as String? ?? 'system',
        authorName: map['authorName'] as String?,
        text: map['text'] as String?,
        attachments: ((map['attachments'] as List?) ?? const [])
            .map((e) => PushizoChatAttachment.fromMap(_chatMap(e)))
            .toList(growable: false),
        quickReplies: (map['quickReplies'] as List?)?.map((e) => PushizoChatQuickReply.fromMap(_chatMap(e))).toList(growable: false),
        status: map['status'] as String? ?? 'sent',
        createdAt: _chatTime(map['createdAt']),
      );

  @override
  String toString() => 'PushizoChatMessage(seq: $seq, sender: $sender, status: $status)';
}

/// Ziyaretçinin konuşması (`open`, `pending`, `resolved`).
class PushizoChatConversation {
  const PushizoChatConversation({
    required this.id,
    required this.status,
    required this.lastSeq,
    required this.agentLastReadSeq,
    required this.visitorLastReadSeq,
    required this.unreadCount,
    required this.botActive,
    required this.assigneeName,
    required this.createdAt,
  });

  final String id;
  final String status;
  final int lastSeq;

  /// Temsilcinin okuduğu son sıra (ziyaretçi mesajlarında "okundu").
  final int agentLastReadSeq;
  final int visitorLastReadSeq;
  final int unreadCount;
  final bool botActive;
  final String? assigneeName;
  final DateTime? createdAt;

  static PushizoChatConversation? fromMapOrNull(Object? value) {
    if (value is! Map) return null;
    final map = Map<Object?, Object?>.from(value);
    final id = map['id'] as String?;
    if (id == null) return null;
    return PushizoChatConversation(
      id: id,
      status: map['status'] as String? ?? 'open',
      lastSeq: _chatInt(map['lastSeq']),
      agentLastReadSeq: _chatInt(map['agentLastReadSeq']),
      visitorLastReadSeq: _chatInt(map['visitorLastReadSeq']),
      unreadCount: _chatInt(map['unreadCount']),
      botActive: map['botActive'] == true,
      assigneeName: map['assigneeName'] as String?,
      createdAt: _chatTime(map['createdAt']),
    );
  }
}

/// Konuşma (henüz yoksa null) ve okunmamış sayısı.
class PushizoChatConversationState {
  const PushizoChatConversationState({required this.conversation, required this.unreadCount});

  final PushizoChatConversation? conversation;
  final int unreadCount;

  factory PushizoChatConversationState.fromMap(Map<Object?, Object?> map) => PushizoChatConversationState(
        conversation: PushizoChatConversation.fromMapOrNull(map['conversation']),
        unreadCount: _chatInt(map['unreadCount']),
      );
}

/// Mesaj sayfası (kronolojik).
class PushizoChatMessagePage {
  const PushizoChatMessagePage({required this.messages, required this.hasMore});

  final List<PushizoChatMessage> messages;
  final bool hasMore;

  factory PushizoChatMessagePage.fromMap(Map<Object?, Object?> map) => PushizoChatMessagePage(
        messages: ((map['messages'] as List?) ?? const []).map((e) => PushizoChatMessage.fromMap(_chatMap(e))).toList(growable: false),
        hasMore: map['hasMore'] == true,
      );
}

/// [_Chat.start] sonucu.
class PushizoChatIdentifyResult {
  const PushizoChatIdentifyResult({required this.userId, required this.conversation});

  final String? userId;
  final PushizoChatConversation? conversation;

  factory PushizoChatIdentifyResult.fromMap(Map<Object?, Object?> map) => PushizoChatIdentifyResult(
        userId: map['userId'] as String?,
        conversation: PushizoChatConversation.fromMapOrNull(map['conversation']),
      );
}

/// Sohbet widget ayarları ve çevrimiçi durumu.
class PushizoChatConfig {
  const PushizoChatConfig({
    required this.enabled,
    required this.online,
    required this.withinBusinessHours,
    required this.color,
    required this.textColor,
    required this.position,
    required this.theme,
    required this.title,
    required this.greeting,
    required this.offlineMessage,
    required this.collectEmailOffline,
    required this.requireEmail,
    required this.attachmentsEnabled,
    required this.attachmentMaxBytes,
    required this.attachmentTypes,
    required this.language,
  });

  final bool enabled;

  /// Çalışma saatleri içinde ve en az bir temsilci (veya bot) çevrimiçi.
  final bool online;
  final bool withinBusinessHours;
  final String? color;
  final String? textColor;
  final String position;
  final String theme;
  final String? title;
  final String? greeting;

  /// Çevrimdışıyken gösterilecek metin; çevrimdışı mesaj için [_Chat.leaveOfflineMessage].
  final String? offlineMessage;
  final bool collectEmailOffline;
  final bool requireEmail;
  final bool attachmentsEnabled;
  final int attachmentMaxBytes;
  final List<String> attachmentTypes;
  final String language;

  factory PushizoChatConfig.fromMap(Map<Object?, Object?> map) => PushizoChatConfig(
        enabled: map['enabled'] == true,
        online: map['online'] == true,
        withinBusinessHours: map['withinBusinessHours'] == true,
        color: map['color'] as String?,
        textColor: map['textColor'] as String?,
        position: map['position'] as String? ?? 'right',
        theme: map['theme'] as String? ?? 'auto',
        title: map['title'] as String?,
        greeting: map['greeting'] as String?,
        offlineMessage: map['offlineMessage'] as String?,
        collectEmailOffline: map['collectEmailOffline'] == true,
        requireEmail: map['requireEmail'] == true,
        attachmentsEnabled: map['attachmentsEnabled'] == true,
        attachmentMaxBytes: _chatInt(map['attachmentMaxBytes']),
        attachmentTypes: ((map['attachmentTypes'] as List?) ?? const []).map((e) => e.toString()).toList(growable: false),
        language: map['language'] as String? ?? 'en',
      );
}

/// Sohbet bildirimine tıklama: açılacak konuşma ve yeni mesajın sıra numarası.
class PushizoChatOpenEvent {
  const PushizoChatOpenEvent({required this.conversationId, required this.seq});

  final String conversationId;
  final int seq;

  factory PushizoChatOpenEvent.fromMap(Map<Object?, Object?> map) =>
      PushizoChatOpenEvent(conversationId: map['conversationId'] as String? ?? '', seq: _chatInt(map['seq']));
}

/// Canlı sohbet olayı. [type]: `message`, `typing`, `read`, `unread`, `conversation`, `connection`, `error`.
class PushizoChatEvent {
  const PushizoChatEvent._(this.type, this._map);

  final String type;
  final Map<Object?, Object?> _map;

  factory PushizoChatEvent.fromMap(Map<Object?, Object?> map) => PushizoChatEvent._(map['event'] as String? ?? '', map);

  /// `message`: yeni mesaj (temsilci, bot, sistem veya bu cihazdan; bekleyen yerel mesaj `pending`).
  PushizoChatMessage? get message => type == 'message' ? PushizoChatMessage.fromMap(_chatMap(_map['message'])) : null;

  /// `typing`: temsilci yazıyor mu ve adı.
  bool get typing => _map['typing'] == true;
  String? get name => _map['name'] as String?;

  /// `read`: temsilcinin okuduğu son sıra numarası.
  int get seq => _chatInt(_map['seq']);

  /// `unread`: okunmamış (temsilci/bot) mesaj sayısı.
  int get count => _chatInt(_map['count']);

  /// `conversation`: konuşma kimliği, durumu ve bot etkin mi.
  String? get conversationId => _map['conversationId'] as String?;
  String? get status => _map['status'] as String?;
  bool get botActive => _map['botActive'] == true;

  /// `connection`: canlı akış bağlı mı (koparsa yerel SDK yeniden bağlanır).
  bool get connected => _map['connected'] == true;

  /// `error`: kalıcı hata kodu (ör. `HS_PLAN_FEATURE_REQUIRED`); dinleme durdu.
  String? get code => _map['code'] as String?;
  String? get errorMessage => _map['message'] is String ? _map['message'] as String : null;

  @override
  String toString() => 'PushizoChatEvent($type)';
}

/// Mesaj listesi birleştirme: sıra numarasına göre artan ve tekil; bekleyen yerel mesaj aynı `clientMessageId` ile
/// sunucu kopyası gelince kalkar (yerel SDK'lardaki `HsChatTimeline` ile aynı kural).
List<PushizoChatMessage> mergePushizoChatMessages(List<PushizoChatMessage> current, List<PushizoChatMessage> incoming) {
  final bySeq = <int, PushizoChatMessage>{};
  final pending = <String, PushizoChatMessage>{};
  for (final m in [...current, ...incoming]) {
    if (m.seq <= 0) {
      final key = m.clientMessageId;
      if (key != null) pending[key] = m;
      continue;
    }
    final key = m.clientMessageId;
    if (key != null) pending.remove(key);
    bySeq[m.seq] = m;
  }
  final confirmed = bySeq.values.map((m) => m.clientMessageId).whereType<String>().toSet();
  final sorted = bySeq.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  return [...sorted, ...pending.values.where((m) => !confirmed.contains(m.clientMessageId))];
}
