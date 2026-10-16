part of '../pushizo_flutter.dart';

/// In-app renk kuralları (Android/iOS SDK'larıyla aynı; ortak vektörler `sdk/testdata/messaging-vectors.json`).
class PushizoInAppColors {
  PushizoInAppColors._();

  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF18181B);
  static const Color darkBackground = Color(0xFF18181B);
  static const Color darkText = Color(0xFFFAFAFA);
  static const Color lightButton = Color(0xFF2563EB);
  static const Color darkButton = Color(0xFF3B82F6);
  static final RegExp _hex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

  /// CSS biçimli renk: `#RGB`, `#RRGGBB`, `#RRGGBBAA` (alfa sonda); geçersizse null.
  static Color? parse(String? value) {
    final v = value?.trim();
    if (v == null || !_hex.hasMatch(v)) return null;
    var digits = v.substring(1);
    if (digits.length == 3) digits = digits.split('').map((c) => '$c$c').join();
    final rgb = int.parse(digits.substring(0, 6), radix: 16);
    final alpha = digits.length == 8 ? int.parse(digits.substring(6, 8), radix: 16) : 0xFF;
    return Color((alpha << 24) | rgb);
  }

  /// Arka plana okunur metin rengi (YIQ parlaklığı ≥ 150 → koyu metin).
  static Color contrastingText(Color background) {
    final argb = background.toARGB32();
    final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    return (r * 299 + g * 587 + b * 114) ~/ 1000 >= 150 ? lightText : darkText;
  }
}

/// Gösterilen mesajın Dart tarafı (rota veya overlay girdisi).
class _InAppPresentation {
  _InAppPresentation(this.message);

  final PushizoInAppMessage message;
  Route<void>? route;
  OverlayEntry? entry;
  Timer? autoDismiss;
  bool interacted = false;
  bool closed = false;
}

/// Yerel SDK'nın seçtiği in-app mesajı Flutter widget'larıyla çizer: modal/tam ekran → rota, banner → overlay.
/// Etkileşimler yerel SDK'ya bildirilir; olay kaydı, aksiyonlar ve dinleyiciler yerel SDK'dadır.
class _InAppPresenter {
  _InAppPresenter._();

  static final _InAppPresenter instance = _InAppPresenter._();
  _InAppPresentation? _current;

  NavigatorState? _navigator() {
    final key = Pushizo._navigatorKey;
    if (key?.currentState != null) return key!.currentState;
    NavigatorState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        found = element.state as NavigatorState;
        return;
      }
      element.visitChildElements(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    return found;
  }

  Future<void> _report(String method, String messageId, [Map<String, Object?> extra = const {}]) async {
    try {
      await Pushizo._channel.invokeMethod<void>(method, {'messageId': messageId, ...extra});
    } on PlatformException catch (e) {
      debugPrint('Pushizo: $method bildirilemedi: ${e.message}');
    }
  }

  /// false → gösterilemedi (navigator yok, başka mesaj açık veya HTML içerik).
  bool show(PushizoInAppMessage message) {
    // HTML mesajlar güvenlik yalıtımı (ADR-0027) için yerel SDK'nın WebView'ında çizilir ve Dart'a gelmez; eski bir
    // yerel SDK gönderirse Flutter widget'larıyla çizilmez (mesaj gösterilemedi sayılır).
    if (message.contentType == PushizoInAppContentType.html) {
      debugPrint('Pushizo: HTML in-app mesajı yerel SDK tarafından çizilmeli; Dart çizimi atlandı.');
      return false;
    }
    if (_current != null) return false;
    final navigator = _navigator();
    if (navigator == null) return false;
    final p = _InAppPresentation(message);
    _current = p;

    void onButton(String id) {
      if (p.interacted || p.closed) return;
      p.interacted = true;
      _report('inAppButtonClicked', message.id, {'buttonId': id});
    }

    void onDismiss() {
      if (p.interacted || p.closed) return;
      p.interacted = true;
      _report('inAppDismissed', message.id);
    }

    final banner = message.layout == PushizoInAppLayout.bannerTop || message.layout == PushizoInAppLayout.bannerBottom;
    if (banner) {
      final overlay = navigator.overlay;
      if (overlay == null) {
        _current = null;
        return false;
      }
      p.entry = OverlayEntry(builder: (_) => _InAppBanner(message: message, onButton: onButton, onDismiss: onDismiss));
      overlay.insert(p.entry!);
    } else {
      final fullscreen = message.layout == PushizoInAppLayout.fullscreen;
      final route = PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: !fullscreen && message.dismissible,
        barrierColor: fullscreen ? null : Colors.black54,
        barrierLabel: 'Pushizo',
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (context, animation, secondary) => PopScope(
          // Geri tuşu ve dışarı dokunma SDK üzerinden kapatır (olay sırası: dismiss → willDismiss → kapanış).
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && message.dismissible) onDismiss();
          },
          child: _InAppPage(message: message, onButton: onButton, onDismiss: onDismiss),
        ),
        transitionsBuilder: (context, animation, secondary, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)), child: child),
        ),
      );
      p.route = route;
      navigator.push(route);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (p.closed) return;
      _report('inAppDisplayed', message.id);
      final seconds = message.autoDismissSeconds;
      if (seconds != null) p.autoDismiss = Timer(Duration(seconds: seconds), onDismiss);
    });
    return true;
  }

  /// Yerel SDK kapatma isteği: görünüm kaldırılır ve `inAppClosed` bildirilir.
  void close(String messageId) {
    final p = _current;
    if (p == null || p.message.id != messageId || p.closed) return;
    p.closed = true;
    p.autoDismiss?.cancel();
    final route = p.route;
    if (route != null && route.isActive) {
      final navigator = route.navigator;
      if (route.isCurrent) {
        navigator?.pop();
      } else {
        navigator?.removeRoute(route);
      }
    }
    p.entry?.remove();
    _current = null;
    _report('inAppClosed', messageId);
  }
}

/// Modal ve tam ekran sayfası.
class _InAppPage extends StatelessWidget {
  const _InAppPage({required this.message, required this.onButton, required this.onDismiss});

  final PushizoInAppMessage message;
  final ValueChanged<String> onButton;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final card = _InAppCard(message: message, onButton: onButton, onDismiss: onDismiss);
    if (message.layout == PushizoInAppLayout.fullscreen) return card;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: card),
        ),
      ),
    );
  }
}

/// Üst/alt banner (overlay girdisi; dışarıdaki dokunuşlar uygulamaya geçer).
class _InAppBanner extends StatefulWidget {
  const _InAppBanner({required this.message, required this.onButton, required this.onDismiss});

  final PushizoInAppMessage message;
  final ValueChanged<String> onButton;
  final VoidCallback onDismiss;

  @override
  State<_InAppBanner> createState() => _InAppBannerState();
}

class _InAppBannerState extends State<_InAppBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.message.layout == PushizoInAppLayout.bannerTop;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
        child: _InAppCard(message: widget.message, onButton: widget.onButton, onDismiss: widget.onDismiss, banner: true),
      ),
    );
    return Positioned(
      left: 0,
      right: 0,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      child: SafeArea(
        top: top,
        bottom: !top,
        child: reduceMotion
            ? card
            : SlideTransition(
                position: Tween(begin: Offset(0, top ? -1 : 1), end: Offset.zero)
                    .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
                child: card,
              ),
      ),
    );
  }
}

/// Mesaj kartı: yerel Flutter bileşenleri (ham HTML yok), sistem açık/koyu temasına uyan varsayılan renkler.
class _InAppCard extends StatelessWidget {
  const _InAppCard({required this.message, required this.onButton, required this.onDismiss, this.banner = false});

  final PushizoInAppMessage message;
  final ValueChanged<String> onButton;
  final VoidCallback onDismiss;
  final bool banner;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final explicitBackground = PushizoInAppColors.parse(message.backgroundColor);
    final background = explicitBackground ?? (dark ? PushizoInAppColors.darkBackground : PushizoInAppColors.lightBackground);
    final textColor = PushizoInAppColors.parse(message.textColor) ??
        (explicitBackground != null
            ? PushizoInAppColors.contrastingText(explicitBackground)
            : (dark ? PushizoInAppColors.darkText : PushizoInAppColors.lightText));
    final fullscreen = message.layout == PushizoInAppLayout.fullscreen;
    // Kapatılamaz ama düğmesiz ve otomatik kapanmayan mesajda kullanıcı mahsur kalmasın.
    final showClose = message.dismissible || (message.buttons.isEmpty && message.autoDismissSeconds == null);
    final textTheme = Theme.of(context).textTheme;
    final align = banner ? TextAlign.start : TextAlign.center;
    final closeLabel = Localizations.of<MaterialLocalizations>(context, MaterialLocalizations)?.closeButtonTooltip ?? 'Close';

    final children = <Widget>[];
    for (final block in message.blocks) {
      switch (block) {
        case PushizoInAppImage(:final url, :final alt):
          children.add(ConstrainedBox(
            constraints: BoxConstraints(maxHeight: banner ? 96 : 280),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              semanticLabel: alt,
              excludeFromSemantics: alt == null,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ));
        case PushizoInAppTitle(:final text):
          children.add(Semantics(
            header: true,
            child: Text(text,
                textAlign: align,
                style: (banner ? textTheme.titleMedium : textTheme.titleLarge)?.copyWith(color: textColor, fontWeight: FontWeight.bold)),
          ));
        case PushizoInAppBody(:final text):
          children.add(Text(text, textAlign: align, style: (banner ? textTheme.bodyMedium : textTheme.bodyLarge)?.copyWith(color: textColor)));
        case final PushizoInAppButton button:
          children.add(_inAppButton(button, dark, onButton));
        case final PushizoInAppCarousel carousel:
          children.add(_InAppCarousel(
            carousel: carousel,
            background: background,
            textColor: textColor,
            dark: dark,
            banner: banner,
            onButton: onButton,
          ));
      }
    }
    final startsWithImage = message.blocks.isNotEmpty && message.blocks.first is PushizoInAppImage;
    final inset = banner ? 16.0 : 24.0;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(inset, showClose && !startsWithImage ? 44 : inset, inset, inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
        ],
      ),
    );
    Widget body = SingleChildScrollView(child: content);
    if (fullscreen) {
      body = SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center(child: content)),
          ),
        ),
      );
    }
    return Semantics(
      scopesRoute: !banner,
      namesRoute: !banner,
      explicitChildNodes: true,
      label: message.blocks.whereType<PushizoInAppTitle>().firstOrNull?.text,
      child: Material(
        color: background,
        elevation: banner ? 6 : 0,
        borderRadius: fullscreen ? null : BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            body,
            if (showClose)
              Positioned(
                top: fullscreen ? MediaQuery.paddingOf(context).top + 4 : 4,
                right: 4,
                child: IconButton(icon: const Icon(Icons.close), color: textColor, tooltip: closeLabel, onPressed: onDismiss),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mesaj düğmesi (blok ve carousel kartı ortak); en az 48 dp yükseklik.
Widget _inAppButton(PushizoInAppButton button, bool dark, ValueChanged<String> onButton) {
  final bg = PushizoInAppColors.parse(button.backgroundColor) ?? (dark ? PushizoInAppColors.darkButton : PushizoInAppColors.lightButton);
  final fg = PushizoInAppColors.parse(button.textColor) ?? PushizoInAppColors.contrastingText(bg);
  return FilledButton(
    onPressed: () => onButton(button.id),
    style: FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Text(button.text, textAlign: TextAlign.center),
  );
}

/// Carousel: yatay kaydırmalı kartlar. Birden fazla kart varsa kart genişliği alanın %85'idir (sonraki kart görünür);
/// kartlar en uzun kart kadar yüksektir, düğmeler kart altına hizalanır. Ekran okuyucu kart başlığını
/// "Kart 1/3: başlık" olarak okur.
class _InAppCarousel extends StatelessWidget {
  const _InAppCarousel({
    required this.carousel,
    required this.background,
    required this.textColor,
    required this.dark,
    required this.banner,
    required this.onButton,
  });

  final PushizoInAppCarousel carousel;
  final Color background;
  final Color textColor;
  final bool dark;
  final bool banner;
  final ValueChanged<String> onButton;

  /// Erişilebilirlik etiketi (Android/iOS SDK'larıyla aynı biçim).
  static String cardLabel(String? languageCode, int index, int total, String title) =>
      languageCode == 'tr' ? 'Kart $index/$total: $title' : 'Card $index/$total: $title';

  @override
  Widget build(BuildContext context) {
    final total = carousel.cards.length;
    final language = Localizations.maybeLocaleOf(context)?.languageCode;
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = total > 1 ? constraints.maxWidth * 0.85 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  SizedBox(width: width, child: _card(carousel.cards[i], cardLabel(language, i + 1, total, carousel.cards[i].title), textTheme)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card(PushizoInAppCarouselCard card, String label, TextTheme textTheme) {
    final imageUrl = card.imageUrl;
    final body = card.body;
    final button = card.button;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: banner ? 80 : 140,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  semanticLabel: card.imageAlt,
                  excludeFromSemantics: card.imageAlt == null,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Semantics(
            header: true,
            label: label,
            child: ExcludeSemantics(
              child: Text(
                card.title,
                style: (banner ? textTheme.titleSmall : textTheme.titleMedium)?.copyWith(color: textColor, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(body, style: (banner ? textTheme.bodySmall : textTheme.bodyMedium)?.copyWith(color: textColor)),
          ],
          if (button != null) ...[
            const Spacer(),
            const SizedBox(height: 8),
            _inAppButton(button, dark, onButton),
          ],
        ],
      ),
    );
  }
}
