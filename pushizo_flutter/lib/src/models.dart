part of '../pushizo_flutter.dart';

/// Push aboneliği durumu.
class PushizoPushSubscriptionState {
  const PushizoPushSubscriptionState({required this.id, required this.token, required this.optedIn, required this.permission});

  final String? id;
  final String? token;
  final bool optedIn;
  final bool permission;

  factory PushizoPushSubscriptionState.fromMap(Map<Object?, Object?> map) => PushizoPushSubscriptionState(
        id: map['id'] as String?,
        token: map['token'] as String?,
        optedIn: map['optedIn'] == true,
        permission: map['permission'] == true,
      );

  @override
  String toString() => 'PushizoPushSubscriptionState(id: $id, optedIn: $optedIn, permission: $permission)';
}

/// Yalnızca Flutter web'de kullanılan başlatma seçenekleri (Web SDK `init` seçeneklerine aynen iletilir).
class PushizoWebOptions {
  const PushizoWebOptions({this.serviceWorkerPath, this.serviceWorkerScope, this.allowLocalhostAsSecureOrigin});

  /// Service worker yolu (site origin'inde); verilmezse dashboard ayarı, o da yoksa `/PushizoSDKWorker.js`.
  final String? serviceWorkerPath;

  /// Service worker kapsamı; verilmezse dashboard ayarı veya service worker'ın bulunduğu dizin.
  final String? serviceWorkerScope;

  /// Güvenli olmayan (HTTP) localhost adreslerinde Web Push'a izin verir (yalnızca geliştirme).
  final bool? allowLocalhostAsSecureOrigin;

  Map<String, Object?> toMap() => {
        'serviceWorkerPath': ?serviceWorkerPath,
        'serviceWorkerScope': ?serviceWorkerScope,
        'allowLocalhostAsSecureOrigin': ?allowLocalhostAsSecureOrigin,
      };
}

/// Bildirim içeriği.
class PushizoNotification {
  const PushizoNotification({this.title, this.body, this.url, this.deliveryId, this.messageId, this.data = const {}, this.androidNotificationId});

  final String? title;
  final String? body;
  final String? url;
  final String? deliveryId;
  final String? messageId;
  final Map<String, String> data;

  /// Android tepsi kimliği ([Pushizo.Notifications.removeNotification] için); iOS'ta null.
  final int? androidNotificationId;

  factory PushizoNotification.fromMap(Map<Object?, Object?> map) => PushizoNotification(
        title: map['title'] as String?,
        body: map['body'] as String?,
        url: map['url'] as String?,
        deliveryId: map['deliveryId'] as String?,
        messageId: map['messageId'] as String?,
        data: (map['data'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
        androidNotificationId: map['androidNotificationId'] as int?,
      );
}

/// İzin gözlemcisi: `granted` yeni etkin bildirim izni durumudur.
typedef PushizoPermissionObserver = void Function(bool granted);

/// Ön plan gösterim kararı işleyicisi.
typedef PushizoForegroundWillDisplayHandler = FutureOr<void> Function(PushizoForegroundEvent event);

/// Ön planda gelen bildirim; [preventDefault] gösterimi engeller. Karar sonradan verilecekse önce [preventDefault],
/// ardından gerekirse [display] çağrılır (iOS'ta en fazla 25 sn içinde).
class PushizoForegroundEvent {
  PushizoForegroundEvent(this.notification, {String? eventId}) : _eventId = eventId;

  final PushizoNotification notification;

  /// Yerel taraftaki ertelenmiş olayın kimliği ([display] için).
  final String? _eventId;
  bool _prevented = false;
  bool _displayed = false;

  /// Gösterim engellendi mi.
  bool get prevented => _prevented;

  /// Bildirimin sistem tarafından gösterilmesini engeller.
  void preventDefault() => _prevented = true;

  /// Bildirimi şimdi gösterir (yalnızca bir kez; [preventDefault] sonrasında da çalışır).
  Future<void> display() async {
    final eventId = _eventId;
    if (_displayed || eventId == null) return;
    _displayed = true;
    await Pushizo._channel.invokeMethod<void>('displayForegroundNotification', {'eventId': eventId});
  }
}

/// Bildirim tıklaması.
class PushizoClickEvent {
  const PushizoClickEvent({required this.notification, this.actionId, this.url});

  final PushizoNotification notification;
  final String? actionId;
  final String? url;

  factory PushizoClickEvent.fromMap(Map<String, dynamic> map) => PushizoClickEvent(
        notification: PushizoNotification.fromMap(Map<Object?, Object?>.from(map['notification'] as Map)),
        actionId: map['actionId'] as String?,
        url: map['url'] as String?,
      );
}
