import { onRequest } from 'firebase-functions/v2/https';

// Bölge: KVKK kapsamında veri yerleşimi için Avrupa bölgesi kullanılır.
// Tüm işlevler aynı bölgede tanımlanmalıdır.
const REGION = 'europe-west1';

export const health = onRequest({ region: REGION }, (request, response) => {
  response.set('Cache-Control', 'no-store');
  response.set('X-Content-Type-Options', 'nosniff');
  response.json({ status: 'ok', service: 'hersey-yolunda-functions', mode: 'firebase' });
});

// TODO(v1.4 port): NestJS service.ts içindeki endpoint'ler buraya taşınacak:
//   /auth/device, /auth/refresh, /auth/logout          -> users + sessions koleksiyonları
//   /me, /me/profile, /me/checkin-schedule             -> users dokümanları
//   /me/checkins (POST) + idempotency                  -> checkins koleksiyonu + transactions
//   /invitations + preview/accept/decline/approve      -> invitations koleksiyonu
//   /me/relationships, /me/relatives, /profiles/*      -> relationships koleksiyonu
//   /me/notifications, /me/devices, /me/sessions       -> notifications/devices/sessions
//   service.tick() (kaçırılan check-in)                -> Cloud Scheduler -> HTTP işlevi
//   APNsTransport                                     -> Firebase Admin Messaging (FCM)
// Port, Firebase projesi oluşturulup doğrulanabilir hale gelince yapılacak;
// doğrulanmadan tamamlanmış sayılmaz.
