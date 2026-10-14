## 0.1.0

- Soğuk başlangıç: yapılandırma yerelde kalıcı; uygulama kapalıyken received/opened/dismissed kaybolmaz, tıklamalar clickStream dinlenene kadar bekletilir. Ön plan olayında `display()`, `pushSubscription.token`, `InAppMessages.addClickListener/addLifecycleListener` (+ remove), iOS `removeNotificationByIdentifier`.

- Kullanıcı tercihleri (`User.getPreferences/setPreferences`), in-app `variantId` ve `pushPrompt`/`outcome` aksiyon türleri (Faz 12, ADR-0019).

- E-posta/SMS aboneliği (`User.addEmail/removeEmail/addSms/removeSms`), in-app mesajlar (`InAppMessages`: trigger, ekran, duraklatma, tıklama ve yaşam döngüsü akışları; Flutter widget'larıyla çizim) ve bildirim kutusu (`Inbox.list/markRead/markAllRead/archive/unreadCount`).

- İlk sürüm: initialize, consent, login/logout, tag/dil, push aboneliği (optIn/optOut/state/changes), izin isteme, tıklama ve ön plan akışları, olay gönderimi, log seviyesi.
