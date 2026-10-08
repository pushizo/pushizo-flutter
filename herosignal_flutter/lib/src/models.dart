part of '../herosignal_flutter.dart';

/// Push aboneliği durumu.
class HeroSignalPushSubscriptionState {
  const HeroSignalPushSubscriptionState({required this.id, required this.token, required this.optedIn, required this.permission});

  final String? id;
  final String? token;
  final bool optedIn;
  final bool permission;

  factory HeroSignalPushSubscriptionState.fromMap(Map<Object?, Object?> map) => HeroSignalPushSubscriptionState(
        id: map['id'] as String?,
        token: map['token'] as String?,
        optedIn: map['optedIn'] == true,
        permission: map['permission'] == true,
      );

  @override
  String toString() => 'HeroSignalPushSubscriptionState(id: $id, optedIn: $optedIn, permission: $permission)';
}

/// Bildirim içeriği.
class HeroSignalNotification {
  const HeroSignalNotification({this.title, this.body, this.url, this.deliveryId, this.messageId, this.notificationId, this.data = const {}});

  final String? title;
  final String? body;
  final String? url;
  final String? deliveryId;
  final String? messageId;

  /// `HeroSignal.Notifications.removeNotification` için kimlik: Android'de sistem bildirim kimliği, iOS'ta teslimat kimliği.
  final String? notificationId;
  final Map<String, String> data;

  factory HeroSignalNotification.fromMap(Map<Object?, Object?> map) => HeroSignalNotification(
        title: map['title'] as String?,
        body: map['body'] as String?,
        url: map['url'] as String?,
        deliveryId: map['deliveryId'] as String?,
        messageId: map['messageId'] as String?,
        notificationId: map['notificationId'] as String?,
        data: (map['data'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
      );
}

/// Ön plan gösterim kararı işleyicisi.
typedef HeroSignalForegroundWillDisplayHandler = FutureOr<void> Function(HeroSignalForegroundEvent event);

/// Ön planda gelen bildirim; [preventDefault] gösterimi engeller.
class HeroSignalForegroundEvent {
  HeroSignalForegroundEvent(this.notification);

  final HeroSignalNotification notification;
  bool _prevented = false;

  /// Gösterim engellendi mi.
  bool get prevented => _prevented;

  /// Bildirimin sistem tarafından gösterilmesini engeller.
  void preventDefault() => _prevented = true;
}

/// Bildirim tıklaması.
class HeroSignalClickEvent {
  const HeroSignalClickEvent({required this.notification, this.actionId, this.url});

  final HeroSignalNotification notification;
  final String? actionId;
  final String? url;

  factory HeroSignalClickEvent.fromMap(Map<String, dynamic> map) => HeroSignalClickEvent(
        notification: HeroSignalNotification.fromMap(Map<Object?, Object?>.from(map['notification'] as Map)),
        actionId: map['actionId'] as String?,
        url: map['url'] as String?,
      );
}
