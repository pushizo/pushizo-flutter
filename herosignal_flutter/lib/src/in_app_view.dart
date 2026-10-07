part of '../herosignal_flutter.dart';

/// In-app renk kuralları (Android/iOS SDK'larıyla aynı; ortak vektörler `sdk/testdata/messaging-vectors.json`).
class HeroSignalInAppColors {
  HeroSignalInAppColors._();

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

  final HeroSignalInAppMessage message;
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
    final key = HeroSignal._navigatorKey;
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
      await HeroSignal._channel.invokeMethod<void>(method, {'messageId': messageId, ...extra});
    } on PlatformException catch (e) {
      debugPrint('HeroSignal: $method bildirilemedi: ${e.message}');
    }
  }

  /// false → gösterilemedi (navigator yok veya başka mesaj açık).
  bool show(HeroSignalInAppMessage message) {
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

    final banner = message.layout == HeroSignalInAppLayout.bannerTop || message.layout == HeroSignalInAppLayout.bannerBottom;
    if (banner) {
      final overlay = navigator.overlay;
      if (overlay == null) {
        _current = null;
        return false;
      }
      p.entry = OverlayEntry(builder: (_) => _InAppBanner(message: message, onButton: onButton, onDismiss: onDismiss));
      overlay.insert(p.entry!);
    } else {
      final fullscreen = message.layout == HeroSignalInAppLayout.fullscreen;
      final route = PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: !fullscreen && message.dismissible,
        barrierColor: fullscreen ? null : Colors.black54,
        barrierLabel: 'HeroSignal',
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

  final HeroSignalInAppMessage message;
  final ValueChanged<String> onButton;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final card = _InAppCard(message: message, onButton: onButton, onDismiss: onDismiss);
    if (message.layout == HeroSignalInAppLayout.fullscreen) return card;
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

  final HeroSignalInAppMessage message;
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
    final top = widget.message.layout == HeroSignalInAppLayout.bannerTop;
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

  final HeroSignalInAppMessage message;
  final ValueChanged<String> onButton;
  final VoidCallback onDismiss;
  final bool banner;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final explicitBackground = HeroSignalInAppColors.parse(message.backgroundColor);
    final background = explicitBackground ?? (dark ? HeroSignalInAppColors.darkBackground : HeroSignalInAppColors.lightBackground);
    final textColor = HeroSignalInAppColors.parse(message.textColor) ??
        (explicitBackground != null
            ? HeroSignalInAppColors.contrastingText(explicitBackground)
            : (dark ? HeroSignalInAppColors.darkText : HeroSignalInAppColors.lightText));
    final fullscreen = message.layout == HeroSignalInAppLayout.fullscreen;
    // Kapatılamaz ama düğmesiz ve otomatik kapanmayan mesajda kullanıcı mahsur kalmasın.
    final showClose = message.dismissible || (message.buttons.isEmpty && message.autoDismissSeconds == null);
    final textTheme = Theme.of(context).textTheme;
    final align = banner ? TextAlign.start : TextAlign.center;
    final closeLabel = Localizations.of<MaterialLocalizations>(context, MaterialLocalizations)?.closeButtonTooltip ?? 'Close';

    final children = <Widget>[];
    for (final block in message.blocks) {
      switch (block) {
        case HeroSignalInAppImage(:final url, :final alt):
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
        case HeroSignalInAppTitle(:final text):
          children.add(Semantics(
            header: true,
            child: Text(text,
                textAlign: align,
                style: (banner ? textTheme.titleMedium : textTheme.titleLarge)?.copyWith(color: textColor, fontWeight: FontWeight.bold)),
          ));
        case HeroSignalInAppBody(:final text):
          children.add(Text(text, textAlign: align, style: (banner ? textTheme.bodyMedium : textTheme.bodyLarge)?.copyWith(color: textColor)));
        case final HeroSignalInAppButton button:
          final bg = HeroSignalInAppColors.parse(button.backgroundColor) ?? (dark ? HeroSignalInAppColors.darkButton : HeroSignalInAppColors.lightButton);
          final fg = HeroSignalInAppColors.parse(button.textColor) ?? HeroSignalInAppColors.contrastingText(bg);
          children.add(FilledButton(
            onPressed: () => onButton(button.id),
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(button.text, textAlign: TextAlign.center),
          ));
      }
    }
    final startsWithImage = message.blocks.isNotEmpty && message.blocks.first is HeroSignalInAppImage;
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
      label: message.blocks.whereType<HeroSignalInAppTitle>().firstOrNull?.text,
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
