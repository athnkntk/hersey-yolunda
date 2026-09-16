import { connect } from 'node:http2';
import { createPrivateKey, createSign, randomUUID } from 'node:crypto';
import { Database } from './database';

export type DeliveryResult = 'accepted' | 'retry' | 'invalid_device' | 'failed';
export interface PushTransport {
  send(token: string, event: { id: string; type: string; expires: Date }): Promise<DeliveryResult>;
}

export class APNsTransport implements PushTransport {
  private jwt = '';
  private issuedAt = 0;
  constructor(private config: { keyId: string; teamId: string; privateKey: string; topic: string; sandbox: boolean }) {}
  private authorization() {
    if (Date.now() - this.issuedAt < 3000000 && this.jwt) return this.jwt;
    const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: this.config.keyId })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ iss: this.config.teamId, iat: Math.floor(Date.now() / 1000) })).toString('base64url');
    const input = `${header}.${payload}`;
    const signature = createSign('SHA256').update(input).sign({ key: createPrivateKey(this.config.privateKey), dsaEncoding: 'ieee-p1363' }).toString('base64url');
    this.jwt = `${input}.${signature}`;
    this.issuedAt = Date.now();
    return this.jwt;
  }
  async send(token: string, event: { id: string; type: string; expires: Date }): Promise<DeliveryResult> {
    const authorization = this.authorization();
    return new Promise(resolve => {
      const client = connect(this.config.sandbox ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com');
      let finished = false;
      const finish = (result: DeliveryResult) => {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        client.destroy();
        resolve(result);
      };
      const timer = setTimeout(() => finish('retry'), 10000);
      client.on('error', () => finish('retry'));
      const request = client.request({
        ':method': 'POST', ':path': `/3/device/${token}`, authorization: `bearer ${authorization}`,
        'apns-topic': this.config.topic, 'apns-push-type': 'alert', 'apns-priority': '10',
        'apns-expiration': String(Math.floor(event.expires.getTime() / 1000)), 'apns-collapse-id': event.id
      });
      let status = 0;
      request.on('response', headers => { status = Number(headers[':status']); });
      request.on('data', () => undefined);
      request.on('error', () => finish('retry'));
      request.on('end', () => finish(status === 200 ? 'accepted' : status === 410 ? 'invalid_device' : status === 429 || status >= 500 ? 'retry' : 'failed'));
      request.end(JSON.stringify({ aps: { alert: { title: 'Herşey Yolunda', body: event.type.startsWith('reminder') ? 'Bugünkü haberinizi göndermeyi unutmayın.' : 'Yakınınızdan yeni bir haber var.' }, sound: 'default' }, event_id: event.id }));
    });
  }
}

export class NotificationWorker {
  constructor(private db: Database, private transport: PushTransport, private decrypt: (value: string) => string, private now: () => Date = () => new Date()) {}

  async run(limit = 20) {
    await this.db.transaction(async db => {
      await db.query(`INSERT INTO notification_deliveries(id,notification_id,device_id,available_at)
        SELECT n.id || ':' || d.id,n.id,d.id,$1 FROM notifications n JOIN devices d ON d.user_id=n.recipient_id
        WHERE n.status='queued' AND d.permission='authorized' AND d.token_encrypted IS NOT NULL ON CONFLICT DO NOTHING`, [this.now()]);
    });
    for (let i = 0; i < limit; i++) {
      const claim = await this.db.transaction(async db => {
        const row = (await db.query(`SELECT d.id AS delivery_id,d.attempts,n.id,n.type,n.status AS notification_status,n.relationship_id,
          o.state,o.closes_at,r.active,p.success,p.missed,v.token_encrypted,v.permission
          FROM notification_deliveries d JOIN notifications n ON n.id=d.notification_id
          JOIN occurrences o ON o.id=n.occurrence_id JOIN devices v ON v.id=d.device_id
          LEFT JOIN relationships r ON r.id=n.relationship_id LEFT JOIN preferences p ON p.user_id=n.recipient_id
          WHERE d.available_at<=$1 AND (d.status IN ('queued','retryable_failed') OR (d.status='sending' AND d.lease_until<$1))
          ORDER BY d.available_at LIMIT 1`, [this.now()])).rows[0];
        if (!row) return null;
        const invalid = row.notification_status === 'suppressed' || (row.relationship_id && !row.active)
          || new Date(row.closes_at) <= this.now() || !row.token_encrypted || row.permission !== 'authorized'
          || (row.type === 'completed' && (row.state !== 'completed' || row.success === false))
          || (row.type === 'missed' && (['completed', 'cancelled'].includes(row.state) || row.missed === false))
          || (row.type.startsWith('reminder') && ['completed', 'cancelled', 'alerted', 'overdue'].includes(row.state));
        if (invalid) {
          await db.query("UPDATE notification_deliveries SET status='suppressed' WHERE id=$1", [row.delivery_id]);
          return { suppressed: true };
        }
        await db.query("UPDATE notification_deliveries SET status='sending',attempts=attempts+1,lease_until=$2 WHERE id=$1", [row.delivery_id, new Date(this.now().getTime() + 30000)]);
        return row;
      });
      if (!claim) break;
      if (claim.suppressed) continue;
      let result: DeliveryResult;
      try { result = await this.transport.send(this.decrypt(claim.token_encrypted), { id: claim.id, type: claim.type, expires: new Date(claim.closes_at) }); }
      catch { result = 'retry'; }
      await this.db.transaction(async db => {
        const attempts = Number(claim.attempts) + 1;
        const status = result === 'accepted' ? 'provider_accepted' : result === 'retry' && attempts < 5 ? 'retryable_failed' : 'permanently_failed';
        const retryAt = new Date(this.now().getTime() + Math.min(900000, 1000 * 2 ** attempts + Math.floor(Math.random() * 1000)));
        await db.query('UPDATE notification_deliveries SET status=$2,available_at=$3,accepted_at=$4,lease_until=NULL WHERE id=$1', [claim.delivery_id, status, retryAt, result === 'accepted' ? this.now() : null]);
        if (result === 'accepted') await db.query("UPDATE notifications SET status='provider_accepted' WHERE id=$1 AND status<>'suppressed'", [claim.id]);
        if (result === 'invalid_device') await db.query('UPDATE devices SET token_encrypted=NULL WHERE id=(SELECT device_id FROM notification_deliveries WHERE id=$1)', [claim.delivery_id]);
      });
    }
  }
}
