part of '../pushizo_flutter.dart';

/// Bildirim teslim riski (ADR-0092; yerel Android `HsDeliveryRisk` ile aynı anlam).
enum PushizoDeliveryRisk {
  /// Bilinen bir engel yok.
  none,

  /// Bildirimler gecikebilir (saldırgan pil yönetimli üretici ve pil muafiyeti yok, seyrek kullanım kovası, veri tasarrufu).
  elevated,

  /// Bildirimler büyük olasılıkla gelmiyor (bildirim izni ya da kanalı kapalı, arka plan etkinliği kısıtlı).
  high;

  static PushizoDeliveryRisk _fromWire(Object? value) => switch (value) {
        'elevated' => elevated,
        'high' => high,
        _ => none,
      };
}

/// [Pushizo.Delivery.openSettings] ve [Pushizo.Delivery.showGuidance] ile açılabilen Android ayar ekranı.
enum PushizoDeliverySetting {
  /// Duruma en uygun ekran ([PushizoDeliveryStatus.recommendedSettings] ilk öğesi; öneri yoksa pil optimizasyonu).
  auto('auto'),

  /// Uygulamanın bildirim ayarları.
  notifications('notifications'),

  /// Üreticinin otomatik başlatma / arka planda çalışma yöneticisi (yoksa uygulama ayrıntıları).
  autoStart('auto_start'),

  /// Pil optimizasyonu: üreticinin pil yöneticisi, yoksa sistemin pil optimizasyonu listesi.
  batteryOptimization('battery_optimization'),

  /// Uygulama ayrıntıları (arka plan kısıtı buradan kaldırılır).
  appDetails('app_details');

  const PushizoDeliverySetting(this.wire);

  /// Platform kanalındaki değer.
  final String wire;

  static PushizoDeliverySetting? _fromWire(Object? value) {
    for (final setting in values) {
      if (setting.wire == value) return setting;
    }
    return null;
  }
}

/// Cihazın bildirim teslim durumu ([Pushizo.Delivery.status]). Kişisel veri içermez: üretici, ROM ve kısıt bayrakları.
///
/// Yalnızca Android'de doludur. iOS'ta, web'de ve Android'de SDK başlatılmadan önce [supported] `false`, [risk]
/// [PushizoDeliveryRisk.none] ve [recommendedSettings] boştur.
class PushizoDeliveryStatus {
  const PushizoDeliveryStatus({
    required this.supported,
    this.manufacturer = '',
    this.brand = '',
    this.vendor = 'other',
    this.aggressiveVendor = false,
    this.rom = '',
    this.romVersion,
    this.notificationsEnabled = true,
    this.channelBlocked = false,
    this.batteryOptimizationExempt = true,
    this.backgroundRestricted = false,
    this.standbyBucket,
    this.powerSaveMode = false,
    this.dataSaverEnabled = false,
    this.restricted = false,
    this.risk = PushizoDeliveryRisk.none,
    this.recommendedSettings = const [],
  });

  /// Teşhisin desteklenmediği platformların durumu (risk yok).
  static const PushizoDeliveryStatus unsupported = PushizoDeliveryStatus(supported: false);

  /// Teşhis bu platformda okunabildi mi (yalnızca Android, SDK başlatıldıktan sonra).
  final bool supported;

  /// `Build.MANUFACTURER` (küçük harf).
  final String manufacturer;

  /// `Build.BRAND` (küçük harf).
  final String brand;

  /// Üretici ailesi: `xiaomi`, `huawei`, `honor`, `oppo`, `realme`, `oneplus`, `vivo`, `samsung`, `meizu`, `asus`,
  /// `transsion` ya da `other`.
  final String vendor;

  /// Üreticinin kendi pil/otomatik başlatma yöneticisi arka plandaki uygulamaları durdurabiliyor mu.
  final bool aggressiveVendor;

  /// ROM kimliği: `miui`, `hyperos`, `emui`, `harmonyos`, `magicos`, `coloros`, `oxygenos`, `realmeui`, `funtouchos`,
  /// `originos`, `oneui`, `flyme`, `android`.
  final String rom;
  final String? romVersion;

  /// Bildirim izni verilmiş ve bildirimler açık mı.
  final bool notificationsEnabled;

  /// Varsayılan bildirim kanalı kullanıcı tarafından kapatılmış mı.
  final bool channelBlocked;

  /// Uygulama pil optimizasyonundan muaf mı.
  final bool batteryOptimizationExempt;

  /// Kullanıcı arka plan etkinliğini kısıtlamış mı.
  final bool backgroundRestricted;

  /// Bekleme kovası: `exempted`, `active`, `working_set`, `frequent`, `rare`, `restricted` (okunamadıysa null).
  final String? standbyBucket;

  /// Pil tasarrufu kipi açık mı.
  final bool powerSaveMode;

  /// Veri tasarrufu uygulamanın arka plan verisini engelliyor mu.
  final bool dataSaverEnabled;

  /// Sistem arka plan kısıtı: kullanıcı kısıtlamış ya da uygulama `rare`/`restricted` kovasında.
  final bool restricted;
  final PushizoDeliveryRisk risk;

  /// Kullanıcının açması önerilen ayar ekranları (önem sırasıyla; öneri yoksa boş).
  final List<PushizoDeliverySetting> recommendedSettings;

  /// Platform kanalı sonucundan durum; `null` (iOS, web, başlatılmamış SDK) → [unsupported].
  factory PushizoDeliveryStatus.fromMap(Map<Object?, Object?>? map) {
    if (map == null || map['supported'] != true) return unsupported;
    final settings = <PushizoDeliverySetting>[];
    for (final value in (map['recommendedSettings'] as List<Object?>?) ?? const <Object?>[]) {
      // Yerel SDK'nın ileride ekleyeceği, bu sürümün tanımadığı ekran atlanır.
      final setting = PushizoDeliverySetting._fromWire(value);
      if (setting != null && setting != PushizoDeliverySetting.auto) settings.add(setting);
    }
    return PushizoDeliveryStatus(
      supported: true,
      manufacturer: map['manufacturer'] as String? ?? '',
      brand: map['brand'] as String? ?? '',
      vendor: map['vendor'] as String? ?? 'other',
      aggressiveVendor: map['aggressiveVendor'] == true,
      rom: map['rom'] as String? ?? '',
      romVersion: map['romVersion'] as String?,
      notificationsEnabled: map['notificationsEnabled'] != false,
      channelBlocked: map['channelBlocked'] == true,
      batteryOptimizationExempt: map['batteryOptimizationExempt'] != false,
      backgroundRestricted: map['backgroundRestricted'] == true,
      standbyBucket: map['standbyBucket'] as String?,
      powerSaveMode: map['powerSaveMode'] == true,
      dataSaverEnabled: map['dataSaverEnabled'] == true,
      restricted: map['restricted'] == true,
      risk: PushizoDeliveryRisk._fromWire(map['risk']),
      recommendedSettings: List.unmodifiable(settings),
    );
  }

  @override
  String toString() =>
      'PushizoDeliveryStatus(supported: $supported, vendor: $vendor, rom: $rom, risk: ${risk.name}, restricted: $restricted)';
}
