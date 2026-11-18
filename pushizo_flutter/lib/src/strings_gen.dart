// Üretilmiş dosya: sdk/scripts/gen-mobile-strings.mjs (kaynak sdk/i18n/mobile). Elle düzenlemeyin.
part of '../pushizo_flutter.dart';

/// Dart çizimindeki carousel kartı erişilebilirlik etiketi (ADR-0084; Android/iOS SDK'larıyla aynı metin).
const Map<String, String> _carouselCardLabels = {
  "tr": "Kart {n}/{total}: {title}",
  "en": "Card {n}/{total}: {title}",
  "de": "Karte {n}/{total}: {title}",
  "fr": "Carte {n}/{total} : {title}",
  "es": "Tarjeta {n}/{total}: {title}",
  "it": "Scheda {n}/{total}: {title}",
  "pt-BR": "Cartão {n}/{total}: {title}",
  "nl": "Kaart {n}/{total}: {title}",
  "pl": "Karta {n}/{total}: {title}",
  "ru": "Карточка {n}/{total}: {title}",
  "uk": "Картка {n}/{total}: {title}",
  "ar": "البطاقة {n}/{total}: {title}",
  "az": "Kart {n}/{total}: {title}",
  "ja": "カード {n}/{total}: {title}",
  "ko": "카드 {n}/{total}: {title}",
  "zh-CN": "卡片 {n}/{total}：{title}",
  "hi": "कार्ड {n}/{total}: {title}",
  "id": "Kartu {n}/{total}: {title}",
  "vi": "Thẻ {n}/{total}: {title}",
  "th": "การ์ด {n}/{total}: {title}",
  "sv": "Kort {n}/{total}: {title}",
  "ro": "Cardul {n}/{total}: {title}",
};

/// Dil kodunu desteklenen koda eşler (`pt` → `pt-BR`, `zh` → `zh-CN`); yoksa `en`.
String _resolvePushizoLanguage(String? languageCode, [String? countryCode]) {
  final lang = (languageCode ?? '').toLowerCase();
  if (lang == 'pt') return 'pt-BR';
  if (lang == 'zh') {
    final region = (countryCode ?? '').toUpperCase();
    return region == 'TW' || region == 'HK' || region == 'MO' ? 'en' : 'zh-CN';
  }
  return _carouselCardLabels.containsKey(lang) ? lang : 'en';
}
