part of '../herosignal_flutter.dart';

// E-posta/SMS, in-app ve bildirim kutusu modelleri (Faz 10).

/// In-app mesaj düzeni.
enum HeroSignalInAppLayout { modal, bannerTop, bannerBottom, fullscreen }

/// In-app düğme aksiyonu türü.
enum HeroSignalInAppActionType { dismiss, url, deeplink, tags }

String? _nonEmpty(Object? value) => value is String && value.isNotEmpty ? value : null;

/// In-app düğme aksiyonu.
class HeroSignalInAppAction {
  const HeroSignalInAppAction({required this.type, this.url, this.tags = const {}});

  final HeroSignalInAppActionType type;

  /// `url` (http/https) veya `deeplink` (uygulama şeması) adresi.
  final String? url;

  /// `tags` aksiyonunun kullanıcıya yazdığı etiketler.
  final Map<String, String> tags;

  /// Geçersiz aksiyon (ör. http dışı `url`) için null.
  static HeroSignalInAppAction? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const HeroSignalInAppAction(type: HeroSignalInAppActionType.dismiss);
    final url = _nonEmpty(map['url']);
    switch (map['type']) {
      case 'url':
        if (url == null || !(url.startsWith('http://') || url.startsWith('https://'))) return null;
        return HeroSignalInAppAction(type: HeroSignalInAppActionType.url, url: url);
      case 'deeplink':
        if (url == null) return null;
        return HeroSignalInAppAction(type: HeroSignalInAppActionType.deeplink, url: url);
      case 'tags':
        final tags = (map['tags'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const <String, String>{};
        return HeroSignalInAppAction(type: HeroSignalInAppActionType.tags, tags: tags);
      default:
        return const HeroSignalInAppAction(type: HeroSignalInAppActionType.dismiss);
    }
  }
}

/// In-app içerik bloğu; metinler sunucuda kullanıcının dilinde çözülmüş düz dizedir.
sealed class HeroSignalInAppBlock {
  const HeroSignalInAppBlock();

  /// Tanınmayan blok türü ve geçersiz düğme için null (ileri uyumluluk).
  static HeroSignalInAppBlock? fromMap(Map<Object?, Object?> map) {
    switch (map['type']) {
      case 'image':
        final url = _nonEmpty(map['url']);
        return url == null ? null : HeroSignalInAppImage(url: url, alt: _nonEmpty(map['alt']));
      case 'title':
        return HeroSignalInAppTitle(map['text'] as String? ?? '');
      case 'body':
        return HeroSignalInAppBody(map['text'] as String? ?? '');
      case 'button':
        final id = _nonEmpty(map['id']);
        final action = HeroSignalInAppAction.fromMap((map['action'] as Map?)?.cast<Object?, Object?>());
        if (id == null || action == null) return null;
        return HeroSignalInAppButton(
          id: id,
          text: map['text'] as String? ?? '',
          action: action,
          backgroundColor: _nonEmpty(map['background_color']),
          textColor: _nonEmpty(map['text_color']),
        );
      default:
        return null;
    }
  }
}

class HeroSignalInAppImage extends HeroSignalInAppBlock {
  const HeroSignalInAppImage({required this.url, this.alt});
  final String url;
  final String? alt;
}

class HeroSignalInAppTitle extends HeroSignalInAppBlock {
  const HeroSignalInAppTitle(this.text);
  final String text;
}

class HeroSignalInAppBody extends HeroSignalInAppBlock {
  const HeroSignalInAppBody(this.text);
  final String text;
}

class HeroSignalInAppButton extends HeroSignalInAppBlock {
  const HeroSignalInAppButton({required this.id, required this.text, required this.action, this.backgroundColor, this.textColor});
  final String id;
  final String text;
  final HeroSignalInAppAction action;
  final String? backgroundColor;
  final String? textColor;
}

/// Yerel SDK'nın gösterim için seçtiği in-app mesaj (tetik ve sıklık yerel SDK'da değerlendirilir).
class HeroSignalInAppMessage {
  const HeroSignalInAppMessage({
    required this.id,
    required this.priority,
    required this.layout,
    required this.dismissible,
    required this.blocks,
    this.backgroundColor,
    this.textColor,
    this.autoDismissSeconds,
  });

  final String id;
  final int priority;
  final HeroSignalInAppLayout layout;
  final String? backgroundColor;
  final String? textColor;
  final bool dismissible;
  final int? autoDismissSeconds;
  final List<HeroSignalInAppBlock> blocks;

  List<HeroSignalInAppButton> get buttons => blocks.whereType<HeroSignalInAppButton>().toList();

  /// Sunucu JSON'undan (`GET /sdk/v1/apps/{app}/in-app` öğesi).
  factory HeroSignalInAppMessage.fromMap(Map<Object?, Object?> map) {
    final display = (map['display'] as Map?)?.cast<Object?, Object?>() ?? const <Object?, Object?>{};
    final auto = display['auto_dismiss_seconds'];
    return HeroSignalInAppMessage(
      id: map['id'] as String,
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      layout: switch (display['layout']) {
        'banner_top' => HeroSignalInAppLayout.bannerTop,
        'banner_bottom' => HeroSignalInAppLayout.bannerBottom,
        'fullscreen' => HeroSignalInAppLayout.fullscreen,
        _ => HeroSignalInAppLayout.modal,
      },
      backgroundColor: _nonEmpty(display['background_color']),
      textColor: _nonEmpty(display['text_color']),
      dismissible: display['dismissible'] as bool? ?? true,
      autoDismissSeconds: auto is num && auto > 0 ? auto.toInt() : null,
      blocks: ((display['blocks'] as List?) ?? const [])
          .whereType<Map>()
          .map((b) => HeroSignalInAppBlock.fromMap(b.cast<Object?, Object?>()))
          .whereType<HeroSignalInAppBlock>()
          .toList(),
    );
  }
}

/// In-app düğme tıklaması: [actionId] düğme kimliği, [url] url/deeplink aksiyonunun adresi.
class HeroSignalInAppClickEvent {
  const HeroSignalInAppClickEvent({required this.messageId, required this.actionId, this.url});

  final String messageId;
  final String actionId;
  final String? url;

  factory HeroSignalInAppClickEvent.fromMap(Map<String, dynamic> map) => HeroSignalInAppClickEvent(
        messageId: map['messageId'] as String,
        actionId: map['actionId'] as String,
        url: map['url'] as String?,
      );
}

/// In-app yaşam döngüsü aşaması.
enum HeroSignalInAppLifecycle { willDisplay, didDisplay, willDismiss, didDismiss }

/// In-app yaşam döngüsü olayı.
class HeroSignalInAppLifecycleEvent {
  const HeroSignalInAppLifecycleEvent({required this.type, required this.messageId});

  final HeroSignalInAppLifecycle type;
  final String messageId;

  static HeroSignalInAppLifecycleEvent? fromMap(Map<String, dynamic> map) {
    final type = HeroSignalInAppLifecycle.values.where((v) => v.name == map['event']).firstOrNull;
    final id = map['messageId'];
    if (type == null || id is! String) return null;
    return HeroSignalInAppLifecycleEvent(type: type, messageId: id);
  }
}

DateTime? _epochMs(Object? value) => value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true) : null;

/// Bildirim kutusu öğesi.
class HeroSignalInboxItem {
  const HeroSignalInboxItem({
    required this.id,
    required this.read,
    this.messageId,
    this.title,
    this.body,
    this.url,
    this.imageUrl,
    this.data = const {},
    this.readAt,
    this.archivedAt,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String? messageId;
  final String? title;
  final String? body;
  final String? url;
  final String? imageUrl;
  final Map<String, String> data;
  final bool read;
  final DateTime? readAt;
  final DateTime? archivedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  /// Platform kanalı haritasından (zamanlar epoch milisaniye, UTC).
  factory HeroSignalInboxItem.fromMap(Map<Object?, Object?> map) => HeroSignalInboxItem(
        id: map['id'] as String,
        messageId: map['messageId'] as String?,
        title: map['title'] as String?,
        body: map['body'] as String?,
        url: map['url'] as String?,
        imageUrl: map['imageUrl'] as String?,
        data: (map['data'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
        read: map['read'] == true,
        readAt: _epochMs(map['readAt']),
        archivedAt: _epochMs(map['archivedAt']),
        expiresAt: _epochMs(map['expiresAt']),
        createdAt: _epochMs(map['createdAt']),
      );
}

/// Bildirim kutusu sayfası (yeniden eskiye).
class HeroSignalInboxPage {
  const HeroSignalInboxPage({required this.items, required this.unreadCount, required this.hasMore, this.nextCursor});

  final List<HeroSignalInboxItem> items;
  final int unreadCount;
  final String? nextCursor;
  final bool hasMore;

  factory HeroSignalInboxPage.fromMap(Map<Object?, Object?> map) => HeroSignalInboxPage(
        items: ((map['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => HeroSignalInboxItem.fromMap(m.cast<Object?, Object?>()))
            .toList(),
        unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
        nextCursor: map['nextCursor'] as String?,
        hasMore: map['hasMore'] == true,
      );
}
