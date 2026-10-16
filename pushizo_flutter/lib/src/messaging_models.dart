part of '../pushizo_flutter.dart';

// E-posta/SMS, in-app ve bildirim kutusu modelleri (Faz 10).

/// In-app mesaj düzeni.
enum PushizoInAppLayout { modal, bannerTop, bannerBottom, fullscreen }

/// In-app içerik biçimi: Flutter widget'larıyla çizilen bloklar veya yerel SDK'nın yalıtılmış WebView'ında çizilen
/// HTML (ADR-0027). HTML mesajlar Dart'a gönderilmez; yerel SDK kendisi gösterir.
enum PushizoInAppContentType { blocks, html }

/// In-app düğme aksiyonu türü. `pushPrompt` yerel bildirim izni istemini açar, `outcome` olay gönderir (ikisi de yerel SDK'da uygulanır).
enum PushizoInAppActionType { dismiss, url, deeplink, tags, pushPrompt, outcome }

String? _nonEmpty(Object? value) => value is String && value.isNotEmpty ? value : null;

/// In-app düğme aksiyonu.
class PushizoInAppAction {
  const PushizoInAppAction({required this.type, this.url, this.tags = const {}, this.outcomeName, this.outcomeValue});

  final PushizoInAppActionType type;

  /// `url` (http/https) veya `deeplink` (uygulama şeması) adresi.
  final String? url;

  /// `tags` aksiyonunun kullanıcıya yazdığı etiketler.
  final Map<String, String> tags;

  /// `outcome` aksiyonunun gönderdiği olay adı ve isteğe bağlı değeri.
  final String? outcomeName;
  final double? outcomeValue;

  /// Geçersiz aksiyon (ör. http dışı `url`) için null.
  static PushizoInAppAction? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const PushizoInAppAction(type: PushizoInAppActionType.dismiss);
    final url = _nonEmpty(map['url']);
    switch (map['type']) {
      case 'url':
        if (url == null || !(url.startsWith('http://') || url.startsWith('https://'))) return null;
        return PushizoInAppAction(type: PushizoInAppActionType.url, url: url);
      case 'deeplink':
        if (url == null) return null;
        return PushizoInAppAction(type: PushizoInAppActionType.deeplink, url: url);
      case 'tags':
        final tags = (map['tags'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const <String, String>{};
        return PushizoInAppAction(type: PushizoInAppActionType.tags, tags: tags);
      case 'push_prompt':
        return const PushizoInAppAction(type: PushizoInAppActionType.pushPrompt);
      case 'outcome':
        // Adsız outcome düğmesi geçersizdir (yerel SDK da atlar).
        final name = _nonEmpty(map['name']);
        if (name == null) return null;
        final value = map['value'];
        return PushizoInAppAction(
          type: PushizoInAppActionType.outcome,
          outcomeName: name,
          outcomeValue: value is num && value.isFinite ? value.toDouble() : null,
        );
      default:
        return const PushizoInAppAction(type: PushizoInAppActionType.dismiss);
    }
  }
}

/// In-app içerik bloğu; metinler sunucuda kullanıcının dilinde çözülmüş düz dizedir.
sealed class PushizoInAppBlock {
  const PushizoInAppBlock();

  /// Tanınmayan blok türü ve geçersiz düğme için null (ileri uyumluluk).
  static PushizoInAppBlock? fromMap(Map<Object?, Object?> map) {
    switch (map['type']) {
      case 'image':
        final url = _nonEmpty(map['url']);
        return url == null ? null : PushizoInAppImage(url: url, alt: _nonEmpty(map['alt']));
      case 'title':
        return PushizoInAppTitle(map['text'] as String? ?? '');
      case 'body':
        return PushizoInAppBody(map['text'] as String? ?? '');
      case 'button':
        final id = _nonEmpty(map['id']);
        final action = PushizoInAppAction.fromMap((map['action'] as Map?)?.cast<Object?, Object?>());
        if (id == null || action == null) return null;
        return PushizoInAppButton(
          id: id,
          text: map['text'] as String? ?? '',
          action: action,
          backgroundColor: _nonEmpty(map['background_color']),
          textColor: _nonEmpty(map['text_color']),
        );
      case 'carousel':
        return PushizoInAppCarousel._fromMap(map);
      default:
        return null;
    }
  }
}

class PushizoInAppImage extends PushizoInAppBlock {
  const PushizoInAppImage({required this.url, this.alt});
  final String url;
  final String? alt;
}

class PushizoInAppTitle extends PushizoInAppBlock {
  const PushizoInAppTitle(this.text);
  final String text;
}

class PushizoInAppBody extends PushizoInAppBlock {
  const PushizoInAppBody(this.text);
  final String text;
}

class PushizoInAppButton extends PushizoInAppBlock {
  const PushizoInAppButton({required this.id, required this.text, required this.action, this.backgroundColor, this.textColor});
  final String id;
  final String text;
  final PushizoInAppAction action;
  final String? backgroundColor;
  final String? textColor;
}

/// Carousel kartı; [button] geçersiz aksiyonlu ise null (kart yine gösterilir).
class PushizoInAppCarouselCard {
  const PushizoInAppCarouselCard({required this.id, required this.title, this.body, this.imageUrl, this.imageAlt, this.button});
  final String id;
  final String title;
  final String? body;
  final String? imageUrl;
  final String? imageAlt;
  final PushizoInAppButton? button;
}

/// Yatay kaydırmalı kartlar (v2 Faz 18); kart düğmeleri [PushizoInAppMessage.buttons] içinde yer alır.
class PushizoInAppCarousel extends PushizoInAppBlock {
  const PushizoInAppCarousel({required this.id, required this.cards});
  final String id;
  final List<PushizoInAppCarouselCard> cards;

  /// Kimliksiz veya kartsız carousel null; kimliksiz kart atlanır, geçersiz kart düğmesi yalnızca düğmeyi düşürür.
  static PushizoInAppCarousel? _fromMap(Map<Object?, Object?> map) {
    final id = _nonEmpty(map['id']);
    if (id == null) return null;
    final cards = <PushizoInAppCarouselCard>[];
    for (final raw in (map['cards'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final c = raw.cast<Object?, Object?>();
      final cardId = _nonEmpty(c['id']);
      if (cardId == null) continue;
      PushizoInAppButton? button;
      final b = (c['button'] as Map?)?.cast<Object?, Object?>();
      final buttonId = b == null ? null : _nonEmpty(b['id']);
      if (b != null && buttonId != null) {
        final action = PushizoInAppAction.fromMap((b['action'] as Map?)?.cast<Object?, Object?>());
        if (action != null) button = PushizoInAppButton(id: buttonId, text: b['text'] as String? ?? '', action: action);
      }
      cards.add(PushizoInAppCarouselCard(
        id: cardId,
        title: c['title'] as String? ?? '',
        body: _nonEmpty(c['body']),
        imageUrl: _nonEmpty(c['image_url']),
        imageAlt: _nonEmpty(c['image_alt']),
        button: button,
      ));
    }
    return cards.isEmpty ? null : PushizoInAppCarousel(id: id, cards: List.unmodifiable(cards));
  }
}

/// Yerel SDK'nın gösterim için seçtiği in-app mesaj (tetik ve sıklık yerel SDK'da değerlendirilir).
class PushizoInAppMessage {
  const PushizoInAppMessage({
    required this.id,
    required this.priority,
    required this.layout,
    required this.dismissible,
    required this.blocks,
    this.backgroundColor,
    this.textColor,
    this.autoDismissSeconds,
    this.variantId,
    this.contentType = PushizoInAppContentType.blocks,
    this.html,
    this.htmlHeight,
  });

  final String id;
  final int priority;

  /// Sunucunun seçtiği A/B görünüm varyantı (olay bildirimlerinde yerel SDK geri gönderir).
  final String? variantId;
  final PushizoInAppLayout layout;
  final String? backgroundColor;
  final String? textColor;
  final bool dismissible;
  final int? autoDismissSeconds;
  final List<PushizoInAppBlock> blocks;

  /// [PushizoInAppContentType.html] ise [blocks] boştur; içerik yerel SDK'nın WebView'ında çizilir.
  final PushizoInAppContentType contentType;

  /// Kullanıcının dilinde, kişiselleştirilmiş HTML (yalnızca HTML içerikte).
  final String? html;

  /// Banner/modal için ilk HTML yüksekliği (mantıksal piksel).
  final int? htmlHeight;

  /// Düğme blokları ve carousel kartlarının düğmeleri.
  List<PushizoInAppButton> get buttons => [
        for (final block in blocks)
          if (block is PushizoInAppButton)
            block
          else if (block is PushizoInAppCarousel)
            for (final card in block.cards)
              if (card.button != null) card.button!,
      ];

  /// Sunucu JSON'undan (`GET /sdk/v1/apps/{app}/in-app` öğesi).
  factory PushizoInAppMessage.fromMap(Map<Object?, Object?> map) {
    final display = (map['display'] as Map?)?.cast<Object?, Object?>() ?? const <Object?, Object?>{};
    final auto = display['auto_dismiss_seconds'];
    // Alan yoksa veya tanınmıyorsa bloklar (eski sunucu uyumu).
    final isHtml = display['content_type'] == 'html';
    final htmlHeight = display['html_height'];
    return PushizoInAppMessage(
      id: map['id'] as String,
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      variantId: _nonEmpty(map['variant_id']),
      layout: switch (display['layout']) {
        'banner_top' => PushizoInAppLayout.bannerTop,
        'banner_bottom' => PushizoInAppLayout.bannerBottom,
        'fullscreen' => PushizoInAppLayout.fullscreen,
        _ => PushizoInAppLayout.modal,
      },
      backgroundColor: _nonEmpty(display['background_color']),
      textColor: _nonEmpty(display['text_color']),
      dismissible: display['dismissible'] as bool? ?? true,
      autoDismissSeconds: auto is num && auto > 0 ? auto.toInt() : null,
      blocks: isHtml
          ? const []
          : ((display['blocks'] as List?) ?? const [])
              .whereType<Map>()
              .map((b) => PushizoInAppBlock.fromMap(b.cast<Object?, Object?>()))
              .whereType<PushizoInAppBlock>()
              .toList(),
      contentType: isHtml ? PushizoInAppContentType.html : PushizoInAppContentType.blocks,
      html: isHtml ? _nonEmpty(display['html']) : null,
      htmlHeight: isHtml && htmlHeight is num && htmlHeight > 0 ? htmlHeight.toInt() : null,
    );
  }
}

/// In-app düğme tıklaması: [actionId] düğme kimliği, [url] url/deeplink aksiyonunun adresi.
class PushizoInAppClickEvent {
  const PushizoInAppClickEvent({required this.messageId, required this.actionId, this.url});

  final String messageId;
  final String actionId;
  final String? url;

  factory PushizoInAppClickEvent.fromMap(Map<String, dynamic> map) => PushizoInAppClickEvent(
        messageId: map['messageId'] as String,
        actionId: map['actionId'] as String,
        url: map['url'] as String?,
      );
}

/// In-app düğme tıklaması dinleyicisi (`Pushizo.InAppMessages.addClickListener`).
typedef PushizoInAppClickListener = void Function(PushizoInAppClickEvent event);

/// In-app yaşam döngüsü dinleyicisi (`Pushizo.InAppMessages.addLifecycleListener`).
typedef PushizoInAppLifecycleListener = void Function(PushizoInAppLifecycleEvent event);

/// In-app yaşam döngüsü aşaması.
enum PushizoInAppLifecycle { willDisplay, didDisplay, willDismiss, didDismiss }

/// In-app yaşam döngüsü olayı.
class PushizoInAppLifecycleEvent {
  const PushizoInAppLifecycleEvent({required this.type, required this.messageId});

  final PushizoInAppLifecycle type;
  final String messageId;

  static PushizoInAppLifecycleEvent? fromMap(Map<String, dynamic> map) {
    final type = PushizoInAppLifecycle.values.where((v) => v.name == map['event']).firstOrNull;
    final id = map['messageId'];
    if (type == null || id is! String) return null;
    return PushizoInAppLifecycleEvent(type: type, messageId: id);
  }
}

DateTime? _epochMs(Object? value) => value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true) : null;

/// Bildirim kutusu öğesi.
class PushizoInboxItem {
  const PushizoInboxItem({
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
  factory PushizoInboxItem.fromMap(Map<Object?, Object?> map) => PushizoInboxItem(
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
class PushizoInboxPage {
  const PushizoInboxPage({required this.items, required this.unreadCount, required this.hasMore, this.nextCursor});

  final List<PushizoInboxItem> items;
  final int unreadCount;
  final String? nextCursor;
  final bool hasMore;

  factory PushizoInboxPage.fromMap(Map<Object?, Object?> map) => PushizoInboxPage(
        items: ((map['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => PushizoInboxItem.fromMap(m.cast<Object?, Object?>()))
            .toList(),
        unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
        nextCursor: map['nextCursor'] as String?,
        hasMore: map['hasMore'] == true,
      );
}

/// Kullanıcı tercihi (ADR-0019 §4): kategori × kanal (`null` = tüm kanallar) → opt-in. [explicit] false ise değer
/// kategori varsayılanından türetilmiştir; [source] kaydı yazan taraf (sdk, api, preference_center…).
class PushizoPreference {
  const PushizoPreference({
    required this.category,
    required this.optedIn,
    required this.explicit,
    this.channel,
    this.source,
    this.updatedAt,
  });

  final String category;

  /// `null` | `ios_push` | `android_push` | `web_push` | `email` | `sms`.
  final String? channel;
  final bool optedIn;
  final bool explicit;
  final String? source;
  final DateTime? updatedAt;

  factory PushizoPreference.fromMap(Map<Object?, Object?> map) => PushizoPreference(
        category: map['category'] as String,
        channel: map['channel'] as String?,
        optedIn: map['optedIn'] == true,
        explicit: map['explicit'] == true,
        source: map['source'] as String?,
        updatedAt: _epochMs(map['updatedAt']),
      );
}

/// Mesaj kategorisi: çok dilli ad/açıklama (`dil kodu → metin`), kanal kısıtı (`null` = tümü) ve varsayılan opt-in.
class PushizoMessageCategory {
  const PushizoMessageCategory({
    required this.key,
    required this.name,
    this.description = const {},
    this.channels,
    this.defaultOptedIn = true,
  });

  final String key;
  final Map<String, String> name;
  final Map<String, String> description;
  final List<String>? channels;
  final bool defaultOptedIn;

  /// Verilen dilde ad; yoksa İngilizce, o da yoksa ilk tanımlı dil.
  String localizedName(String language) => name[language] ?? name['en'] ?? (name.values.isEmpty ? key : name.values.first);

  factory PushizoMessageCategory.fromMap(Map<Object?, Object?> map) => PushizoMessageCategory(
        key: map['key'] as String,
        name: (map['name'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
        description: (map['description'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
        channels: (map['channels'] as List?)?.map((c) => c.toString()).toList(),
        defaultOptedIn: map['defaultOptedIn'] != false,
      );
}

/// `User.getPreferences` / `setPreferences` sonucu: kullanıcının tercihleri ve app'in kategorileri.
class PushizoPreferences {
  const PushizoPreferences({required this.preferences, required this.categories});

  final List<PushizoPreference> preferences;
  final List<PushizoMessageCategory> categories;

  factory PushizoPreferences.fromMap(Map<Object?, Object?> map) => PushizoPreferences(
        preferences: ((map['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => PushizoPreference.fromMap(m.cast<Object?, Object?>()))
            .toList(),
        categories: ((map['categories'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => PushizoMessageCategory.fromMap(m.cast<Object?, Object?>()))
            .toList(),
      );
}

/// `User.setPreferences` girdisi; [channel] null ise tüm kanallar.
class PushizoPreferenceInput {
  const PushizoPreferenceInput({required this.category, required this.optedIn, this.channel});

  final String category;
  final String? channel;
  final bool optedIn;

  Map<String, Object?> toMap() => {'category': category, 'channel': channel, 'optedIn': optedIn};
}
