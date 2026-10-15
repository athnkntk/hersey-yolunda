import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { Database, SQL } from './database';

export class APIError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}
const fail = (status: number, code: string, message: string): never => { throw new APIError(status, code, message); };
const id = () => randomUUID();
const opaque = () => randomBytes(32).toString('base64url');
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
const iso = (value: any) => new Date(value).toISOString();
const invitationCredential = z.object({
  token: z.string().regex(/^[A-Za-z0-9_-]{43}$/).optional(),
  code: z.string().max(32).transform(value => value.replace(/[-\s]/g, '').toUpperCase()).pipe(z.string().regex(/^[A-HJ-NP-Z2-9]{12}$/)).optional()
}).strict().refine(value => Boolean(value.token) !== Boolean(value.code), 'Tek bir davet kodu veya bağlantısı kullanın.');
const uuid = z.string().uuid();
const recoveryKey = z.string().regex(/^HYR1\.[A-Za-z0-9_-]{43}$/).refine(value => {
  const bytes = Buffer.from(value.slice(5), 'base64url');
  return bytes.length === 32 && bytes.toString('base64url') === value.slice(5);
});
const recoverAccountInput = z.object({
  recovery_key: recoveryKey,
  replacement_key: recoveryKey,
  request_id: uuid,
  device_name: z.string().trim().min(1).max(80)
}).strict().refine(v => v.recovery_key !== v.replacement_key);
const labels = z.enum(['Oğlum', 'Kızım', 'Eşim', 'Kardeşim', 'Torunum', 'Yakınım', 'Diğer']);
const validTimeZone = (value: string): boolean => {
  if (value !== 'UTC' && value !== 'GMT' && !value.includes('/')) return false;
  try { new Intl.DateTimeFormat('en', { timeZone: value }).format(new Date(0)); return true; }
  catch { return false; }
};
const timezoneInput = z.string().min(1).max(100).refine(validTimeZone);

export interface Options {
  mode: 'development' | 'test' | 'production';
  encryptionKey: Buffer;
  lookupKey: string;
  clock?: () => Date;
  pushConfigured?: boolean;
  tickSecret?: string;
  pushWorker?: { run(): Promise<void> };
}

export class Service {
  constructor(public database: Database, public options: Options) {
    if (options.encryptionKey.length !== 32) throw new Error('Encryption key must be 32 bytes');
  }
  now() { return this.options.clock?.() ?? new Date(); }
  private encrypt(text: string) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.options.encryptionKey, iv);
    const encrypted = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), encrypted]).toString('base64');
  }
  decrypt(text: string) {
    const bytes = Buffer.from(text, 'base64');
    const cipher = createDecipheriv('aes-256-gcm', this.options.encryptionKey, bytes.subarray(0, 12));
    cipher.setAuthTag(bytes.subarray(12, 28));
    return Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString('utf8');
  }
  private lookup(text: string) { return createHmac('sha256', this.options.lookupKey).update(text).digest('hex'); }
  private day(timezone: string) {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit'
    }).formatToParts(this.now());
    const part = (type: string) => parts.find(value => value.type === type)!.value;
    return `${part('year')}-${part('month')}-${part('day')}`;
  }
  private nextDay(day: string) { return new Date(new Date(`${day}T12:00:00Z`).getTime() + 86400000).toISOString().slice(0, 10); }
  private async at(db: SQL, day: string, minute: number, timezone: string) {
    const row = await this.one(db,
      "SELECT (($1::date + ($2::integer * interval '1 minute')) AT TIME ZONE $3) AS instant",
      [day, minute, timezone]);
    return iso(row.instant);
  }
  private async one(db: SQL, query: string, values: any[] = []) { return (await db.query(query, values)).rows[0]; }
  private async audit(db: SQL, user: string, action: string) {
    await db.query('INSERT INTO audit_logs VALUES($1,$2,$3,$4)', [id(), user, action, this.now()]);
  }
  private async limit(db: SQL, key: string, max: number, seconds: number) {
    const row = await this.one(db, 'SELECT * FROM rate_limits WHERE key=$1', [key]);
    if (row && new Date(row.expires_at) > this.now() && row.count >= max) fail(429, 'rate_limited', 'Çok fazla deneme. Lütfen daha sonra yeniden deneyin.');
    if (!row || new Date(row.expires_at) <= this.now()) {
      await db.query('INSERT INTO rate_limits VALUES($1,1,$2) ON CONFLICT(key) DO UPDATE SET count=1,expires_at=$2', [key, new Date(this.now().getTime() + seconds * 1000)]);
    } else await db.query('UPDATE rate_limits SET count=count+1 WHERE key=$1', [key]);
  }
  private async issue(db: SQL, user: string, device: string, family = id()) {
    const access = opaque(), refresh = opaque();
    await db.query('INSERT INTO sessions(id,user_id,access_hash,refresh_hash,family_id,device_name,access_expires,refresh_expires,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)',
      [id(), user, hash(access), hash(refresh), family, device, new Date(this.now().getTime() + 15 * 60000), new Date(this.now().getTime() + 30 * 86400000), this.now()]);
    return { access_token: access, refresh_token: refresh, user_id: user, expires_in: 900 };
  }
  private profile(row: any) {
    return { id: row.id, name: row.name, timezone: row.timezone, enabled: row.enabled, schedule_minute: row.schedule_minute, grace_minutes: row.grace_minutes };
  }
  private recoveryStatus(user: any) {
    return { enabled: Boolean(user.recovery_key_hash), version: user.recovery_key_version, updated_at: user.recovery_key_set_at ? iso(user.recovery_key_set_at) : null };
  }
  private async schedule(db: SQL, user: any, day: string) {
    return await this.one(db, 'SELECT minute,grace,effective_date FROM schedules WHERE user_id=$1 AND effective_date <= $2 ORDER BY effective_date DESC LIMIT 1', [user.id, day])
      ?? { minute: user.schedule_minute, grace: user.grace_minutes, effective_date: day };
  }
  private async occurrence(db: SQL, user: any) {
    const day = this.day(user.timezone);
    let row = await this.one(db, 'SELECT * FROM occurrences WHERE user_id=$1 AND local_date=$2', [user.id, day]);
    if (!row) {
      const schedule = await this.schedule(db, user, day);
      const startsAt = await this.at(db, day, 0, user.timezone);
      const dueAt = await this.at(db, day, schedule.minute, user.timezone);
      const closesAt = await this.at(db, this.nextDay(day), 0, user.timezone);
      // Grace is elapsed time, including DST changes; it must end within this occurrence.
      const deadlineAt = new Date(Math.min(new Date(dueAt).getTime() + schedule.grace * 60000, new Date(closesAt).getTime() - 1)).toISOString();
      row = await this.one(db, 'INSERT INTO occurrences(id,user_id,local_date,due_at,deadline_at,closes_at,state,timezone,starts_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *',
        [id(), user.id, day, dueAt, deadlineAt, closesAt, user.enabled ? 'pending' : 'cancelled', user.timezone, startsAt]);
    }
    return row;
  }
  private async status(db: SQL, user: any) {
    const row = await this.occurrence(db, user);
    const tomorrow = this.nextDay(this.day(user.timezone));
    const next = await this.schedule(db, user, tomorrow);
    const count = await this.one(db, 'SELECT count(*) AS count FROM relationships WHERE subject_id=$1 AND active', [user.id]);
    return { ...row, due_at: iso(row.due_at), deadline_at: iso(row.deadline_at), closes_at: iso(row.closes_at), completed_at: row.completed_at ? iso(row.completed_at) : null,
      starts_at: iso(row.starts_at), timezone: row.timezone, next_due_at: await this.at(db, tomorrow, next.minute, user.timezone), next_schedule_minute: next.minute, next_grace_minutes: next.grace, trusted_contacts: Number(count.count), server_time: this.now().toISOString(), reminders_enabled: user.enabled && new Date(user.activated_at ?? user.created_at) <= new Date(row.due_at) };
  }
  private async authorize(db: SQL, actor: string, subject: string) {
    if (actor === subject) return null;
    const relation = await this.one(db, 'SELECT * FROM relationships WHERE subject_id=$1 AND viewer_id=$2 AND active', [subject, actor]);
    if (!relation) fail(404, 'not_found', 'Kayıt bulunamadı veya paylaşım izniniz yok.');
    return relation;
  }
  private async notify(db: SQL, occurrence: any, type: string) {
    const relations = (await db.query('SELECT * FROM relationships WHERE subject_id=$1 AND active', [occurrence.user_id])).rows;
    let eligible = 0;
    for (const relation of relations) {
      const preference = await this.one(db, 'SELECT * FROM preferences WHERE user_id=$1', [relation.viewer_id]);
      if ((type === 'completed' && preference?.success === false) || (type === 'missed' && preference?.missed === false)) continue;
      await db.query(`INSERT INTO notifications(id,occurrence_id,recipient_id,relationship_id,type,created_at,available_at) VALUES($1,$2,$3,$4,$5,$6,$6)
        ON CONFLICT(occurrence_id,recipient_id,type) DO UPDATE SET status='queued',relationship_id=$4,available_at=$6 WHERE notifications.status='suppressed'`,
        [id(), occurrence.id, relation.viewer_id, relation.id, type, this.now()]);
      eligible++;
    }
    return eligible;
  }

  async request(method: string, path: string, body: unknown = {}, token = '', key = '', ip = 'local'): Promise<any> {
    // /tick bilinçli olarak transaction dışında çalışır: tick() kendi transaction'ını açar;
    // iç içe transaction PGlite'da kilitlenmeye yol açar.
    if (method === 'POST' && path === '/tick') {
      const tickSecret = this.options.tickSecret;
      if (tickSecret) {
        const input = z.object({ secret: z.string().min(20).max(200) }).parse(body);
        if (!timingSafeEqual(Buffer.from(hash(input.secret)), Buffer.from(hash(tickSecret)))) fail(403, 'invalid_secret', 'Zamanlayıcı anahtarı geçersiz.');
        await this.tick();
        await this.options.pushWorker?.run();
        return { ok: true, ran_at: this.now().toISOString() };
      }
      fail(404, 'not_found', 'İşlem bulunamadı.');
    }
    if (method === 'POST' && (path === '/invitations/preview' || /^\/invitations\/[^/]+\/(accept|decline)$/.test(path))) {
      await this.database.transaction(async db => {
        const session = await this.one(db, 'SELECT user_id FROM sessions WHERE access_hash=$1 AND NOT revoked AND access_expires>$2', [hash(token), this.now()]);
        if (!session) fail(401, 'unauthorized', 'Lütfen yeniden giriş yapın.');
        await this.limit(db, `invite-guess:${session.user_id}`, 20, 600);
        await this.limit(db, `invite-network:${this.lookup(ip)}`, 60, 600);
      });
    }
    // Kurtarma tahminleri ana işlem başarısız olsa bile limiti tüketmeli;
    // davet-tahmin limitiyle aynı şekilde önceden commitlenmiş transaction'da sayılır.
    const recovery = method === 'POST' && path === '/auth/recover' ? recoverAccountInput.parse(body) : undefined;
    if (recovery) await this.database.transaction(async db => {
      await this.limit(db, `recovery-network:${this.lookup(ip)}`, 10, 600);
    });
    const result = await this.database.transaction(async db => {
      if (path === '/health') return { status: 'ok', mode: this.options.mode, push_configured: this.options.pushConfigured ?? false, sms_configured: false };
      if (path.startsWith('/auth/otp/')) fail(410, 'auth_method_removed', 'Telefonla giriş kaldırıldı. Uygulamayı güncelleyip adınızla yeni cihaz hesabı oluşturun. Mevcut oturumunuz varsa kullanmaya devam edebilirsiniz.');
      if (method === 'POST' && path === '/auth/device') {
        const input = z.object({ name: z.string().trim().min(1).max(60), enabled: z.boolean(), device_name: z.string().trim().min(1).max(80), registration_secret: z.string().regex(/^[A-Za-z0-9_-]{43}$/), timezone: timezoneInput.optional() }).strict().parse(body);
        const secretHash = hash(input.registration_secret);
        const fingerprint = hash(JSON.stringify(input.timezone === undefined
          ? [input.name, input.enabled, input.device_name]
          : [input.name, input.enabled, input.device_name, input.timezone]));
        const previous = await this.one(db, 'SELECT * FROM account_registrations WHERE secret_hash=$1', [secretHash]);
        if (previous) {
          if (new Date(previous.expires_at) <= this.now()) fail(409, 'registration_expired', 'Hesap oluşturma tekrar süresi doldu. Adınız veya hesap ID’si ile eski hesaba giriş yapılamaz.');
          if (previous.fingerprint !== fingerprint) fail(409, 'registration_conflict', 'Bekleyen hesap oluşturma işlemini aynı ad ve tercihlerle yeniden deneyin.');
          const activeSession = await this.one(db, 'SELECT id FROM sessions WHERE family_id=$1 AND NOT revoked AND refresh_expires>$2 LIMIT 1', [previous.family_id, this.now()]);
          if (!activeSession) fail(409, 'registration_expired', 'Bu cihazın erişimi kaldırılmış. Kayıt anahtarı hesabı yeniden açamaz.');
          await this.limit(db, `registration-retry:${secretHash}`, 20, 600);
          await db.query('UPDATE sessions SET revoked=true WHERE family_id=$1', [previous.family_id]);
          return this.issue(db, previous.user_id, input.device_name, previous.family_id);
        }
        await this.limit(db, `registration:${this.lookup(ip)}`, 10, 3600);
        await this.limit(db, 'registration-global', 1000, 86400);
        const userId = id(), family = id();
        await db.query('INSERT INTO users(id,name,enabled,created_at,activated_at,timezone) VALUES($1,$2,$3,$4,$4,$5)', [userId, input.name, input.enabled, this.now(), input.timezone ?? 'Europe/Istanbul']);
        await db.query('INSERT INTO preferences(user_id) VALUES($1)', [userId]);
        await db.query('INSERT INTO account_registrations VALUES($1,$2,$3,$4,$5)', [secretHash, userId, fingerprint, family, new Date(this.now().getTime() + 10 * 60000)]);
        await this.audit(db, userId, 'device_account_created');
        return this.issue(db, userId, input.device_name, family);
      }
      if (method === 'POST' && path === '/auth/refresh') {
        const input = z.object({ refresh_token: z.string().min(20).max(200) }).parse(body);
        if (key) uuid.parse(key);
        const session = await this.one(db, 'SELECT * FROM sessions WHERE refresh_hash=$1', [hash(input.refresh_token)]);
        if (!session || new Date(session.refresh_expires) <= this.now()) fail(401, 'session_expired', 'Yeniden giriş yapın.');
        if (session.revoked) {
          if (key && session.refresh_request_hash === hash(key) && session.refresh_response_encrypted
              && new Date(session.refresh_replay_until) > this.now()) {
            const response = JSON.parse(this.decrypt(session.refresh_response_encrypted));
            const active = await this.one(db,
              'SELECT id FROM sessions WHERE refresh_hash=$1 AND family_id=$2 AND NOT revoked AND refresh_expires>$3',
              [hash(response.refresh_token), session.family_id, this.now()]);
            if (active) return response;
          }
          await db.query('UPDATE sessions SET revoked=true WHERE family_id=$1', [session.family_id]);
          await db.query("UPDATE devices SET token_encrypted=NULL,permission='denied' WHERE session_family_id=$1", [session.family_id]);
          return { internal_error: { status: 401, code: 'session_reused', message: 'Güvenlik nedeniyle yeniden giriş yapın.' } };
        }
        const response = await this.issue(db, session.user_id, session.device_name, session.family_id);
        await db.query('UPDATE sessions SET revoked=true,refresh_request_hash=$2,refresh_response_encrypted=$3,refresh_replay_until=$4 WHERE id=$1',
          [session.id, key ? hash(key) : null, key ? this.encrypt(JSON.stringify(response)) : null,
            key ? new Date(this.now().getTime() + 60000) : null]);
        return response;
      }
      if (recovery) {
        const oldHash = this.lookup('recovery:' + recovery.recovery_key);
        const replacementHash = this.lookup('recovery:' + recovery.replacement_key);
        const requestHash = hash(recovery.request_id);
        const fingerprint = hash(JSON.stringify([oldHash, replacementHash, recovery.device_name]));
        const prior = await this.one(db, 'SELECT ar.*,u.recovery_key_hash AS current_key_hash FROM account_recoveries ar JOIN users u ON u.id=ar.user_id WHERE ar.request_hash=$1', [requestHash]);
        if (prior) {
          if (prior.fingerprint !== fingerprint || prior.old_key_hash !== oldHash || prior.current_key_hash !== replacementHash || new Date(prior.expires_at) <= this.now()) fail(401,'recovery_invalid','Kurtarma anahtarı geçersiz, değiştirilmiş veya daha önce kullanılmış.');
          const active = await this.one(db, 'SELECT id FROM sessions WHERE family_id=$1 AND NOT revoked AND refresh_expires>$2 LIMIT 1', [prior.family_id,this.now()]);
          if (!active) fail(401,'recovery_invalid','Kurtarma anahtarı geçersiz, değiştirilmiş veya daha önce kullanılmış.');
          return JSON.parse(this.decrypt(prior.response_encrypted));
        }
        const recovered = await this.one(db, 'SELECT * FROM users WHERE recovery_key_hash=$1', [oldHash]);
        if (!recovered) fail(401,'recovery_invalid','Kurtarma anahtarı geçersiz, değiştirilmiş veya daha önce kullanılmış.');
        const collision = await this.one(db, 'SELECT id FROM users WHERE recovery_key_hash=$1 AND id<>$2', [replacementHash,recovered.id]);
        if (collision) fail(409,'recovery_key_unavailable','Bu kurtarma anahtarı kullanılamıyor. Yeni bir anahtar oluşturun.');
        await db.query('UPDATE sessions SET revoked=true WHERE user_id=$1',[recovered.id]);
        await db.query("UPDATE devices SET token_encrypted=NULL,permission='denied' WHERE user_id=$1",[recovered.id]);
        await db.query('UPDATE account_registrations SET expires_at=$1 WHERE user_id=$2',[this.now(),recovered.id]);
        await db.query('UPDATE users SET recovery_key_hash=$2,recovery_key_version=recovery_key_version+1,recovery_key_set_at=$3 WHERE id=$1',[recovered.id,replacementHash,this.now()]);
        const family = id();
        const response = await this.issue(db,recovered.id,recovery.device_name,family);
        await db.query('INSERT INTO account_recoveries(request_hash,user_id,old_key_hash,replacement_key_hash,fingerprint,family_id,response_encrypted,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8)',[requestHash,recovered.id,oldHash,replacementHash,fingerprint,family,this.encrypt(JSON.stringify(response)),new Date(this.now().getTime()+10*60000)]);
        await this.audit(db,recovered.id,'account_recovered');
        return response;
      }
      const session = await this.one(db, 'SELECT * FROM sessions WHERE access_hash=$1 AND NOT revoked AND access_expires>$2', [hash(token), this.now()]);
      if (!session) fail(401, 'unauthorized', 'Lütfen yeniden giriş yapın.');
      const user = await this.one(db, 'SELECT * FROM users WHERE id=$1', [session.user_id]);
      if (method === 'POST' && path === '/auth/logout') {
        await db.query('UPDATE sessions SET revoked=true WHERE family_id=$1', [session.family_id]);
        await db.query('UPDATE account_registrations SET expires_at=$1 WHERE family_id=$2', [this.now(), session.family_id]);
        await db.query("UPDATE devices SET token_encrypted=NULL,permission='denied' WHERE session_family_id=$1", [session.family_id]);
        return { ok: true };
      }
      if (path === '/me' && method === 'GET') return this.profile(user);
      if (path === '/me/recovery-key' && method === 'GET') return this.recoveryStatus(user);
      if (path === '/me/recovery-key' && method === 'PUT') {
        const input = z.object({ recovery_key: recoveryKey, expected_version: z.number().int().nonnegative() }).strict().parse(body);
        const digest = this.lookup('recovery:' + input.recovery_key);
        // Kayıp yanıtın tekrarı: aynı anahtar zaten kayıtlıysa mevcut durumu döndür.
        if (user.recovery_key_hash === digest) return this.recoveryStatus(user);
        if (input.expected_version !== user.recovery_key_version) fail(409,'recovery_changed','Kurtarma ayarı değişti. Ekranı yenileyip yeniden deneyin.');
        await this.limit(db, `recovery-setup:${user.id}`, 5, 3600);
        const existing = await this.one(db, 'SELECT id FROM users WHERE recovery_key_hash=$1 AND id<>$2', [digest,user.id]);
        if (existing) fail(409,'recovery_key_unavailable','Bu kurtarma anahtarı kullanılamıyor. Yeni bir anahtar oluşturun.');
        const updated = await this.one(db, 'UPDATE users SET recovery_key_hash=$2,recovery_key_version=recovery_key_version+1,recovery_key_set_at=$3 WHERE id=$1 RETURNING *', [user.id,digest,this.now()]);
        await this.audit(db,user.id,'recovery_key_changed');
        return this.recoveryStatus(updated);
      }
      if (path === '/me/recovery-key' && method === 'DELETE') {
        const input = z.object({ expected_version: z.number().int().nonnegative() }).strict().parse(body);
        if (!user.recovery_key_hash) return this.recoveryStatus(user);
        if (input.expected_version !== user.recovery_key_version) fail(409,'recovery_changed','Kurtarma ayarı değişti. Ekranı yenileyip yeniden deneyin.');
        const updated = await this.one(db, 'UPDATE users SET recovery_key_hash=NULL,recovery_key_version=recovery_key_version+1,recovery_key_set_at=NULL WHERE id=$1 RETURNING *', [user.id]);
        await this.audit(db,user.id,'recovery_key_disabled');
        return this.recoveryStatus(updated);
      }
      if (path === '/me/profile' && method === 'PATCH') {
        const input = z.object({ name: z.string().trim().min(1).max(60), enabled: z.boolean().optional() }).parse(body);
        const enabled = input.enabled ?? user.enabled;
        await db.query('UPDATE users SET name=$1,enabled=$3,activated_at=$4 WHERE id=$2', [input.name, user.id, enabled, enabled && !user.enabled ? this.now() : user.activated_at]);
        if (enabled !== user.enabled) {
          await db.query("UPDATE occurrences SET state=$3 WHERE user_id=$1 AND local_date=$2 AND state<>'completed'", [user.id, this.day(user.timezone), enabled ? 'pending' : 'cancelled']);
          if (!enabled) await db.query("UPDATE notifications SET status='suppressed' WHERE occurrence_id IN (SELECT id FROM occurrences WHERE user_id=$1 AND local_date=$2) AND status IN ('queued','retryable_failed')", [user.id, this.day(user.timezone)]);
          await this.audit(db, user.id, enabled ? 'program_enabled' : 'program_disabled');
        }
        return this.profile({ ...user, ...input, enabled });
      }
      if (path === '/me/checkin/today' && method === 'GET') return this.status(db, user);
      if (path === '/me/checkins' && method === 'POST') {
        if (!user.enabled) fail(409, 'program_disabled', 'Önce günlük haber vermeyi etkinleştirin.');
        const input = z.object({ occurrence_id: uuid, source: z.enum(['app', 'ios_widget']), client_action_at: z.string().datetime() }).parse(body);
        uuid.parse(key);
        const fingerprint = hash(JSON.stringify(input));
        const existing = await this.one(db, 'SELECT * FROM idempotency WHERE user_id=$1 AND key=$2', [user.id, key]);
        if (existing) {
          if (existing.fingerprint !== fingerprint) fail(409, 'idempotency_conflict', 'İşlem kimliği farklı bir istek için kullanılmış.');
          return existing.response;
        }
        const row = await this.one(db, 'SELECT * FROM occurrences WHERE id=$1 AND user_id=$2', [input.occurrence_id, user.id]);
        if (!row) fail(404, 'not_found', 'Günlük kontrol bulunamadı.');
        const actionAge = this.now().getTime() - new Date(input.client_action_at).getTime();
        if (row.local_date !== this.day(user.timezone) || new Date(row.starts_at) > this.now() || new Date(row.closes_at) <= this.now()) fail(409, 'stale_day', 'Bu kontrolün günü geçti. Bugünkü ekranı yenileyin.');
        if (actionAge > 300000 || actionAge < -60000) fail(409, 'stale_action', 'Lütfen yeniden dokunarak haber verin.');
        if (row.state === 'cancelled') fail(409, 'paused', 'Bugünkü kontrol devre dışı. Önce yeniden etkinleştirin.');
        let checkin = await this.one(db, 'SELECT * FROM checkins WHERE occurrence_id=$1', [row.id]);
        const repeated = Boolean(checkin);
        if (!checkin) {
          checkin = await this.one(db, 'INSERT INTO checkins VALUES($1,$2,$3,$4,$5) RETURNING *', [id(), row.id, user.id, input.source, this.now()]);
          await db.query("UPDATE occurrences SET state='completed',completed_at=$1 WHERE id=$2", [this.now(), row.id]);
          await db.query("UPDATE notifications SET status='suppressed' WHERE occurrence_id=$1 AND type<>'completed' AND status IN ('queued','retryable_failed')", [row.id]);
          await this.notify(db, row, 'completed');
        }
        const response = { checkin_id: checkin.id, status: 'completed', received_at: iso(checkin.received_at), already_completed: repeated, notification_state: 'queued' };
        await db.query('INSERT INTO idempotency VALUES($1,$2,$3,$4,$5)', [user.id, key, fingerprint, JSON.stringify(response), this.now()]);
        return response;
      }
      if (path === '/me/checkin/today/pause' && method === 'POST') {
        const row = await this.occurrence(db, user);
        if (row.state !== 'completed') {
          await db.query("UPDATE occurrences SET state='cancelled' WHERE id=$1", [row.id]);
          await db.query("UPDATE notifications SET status='suppressed' WHERE occurrence_id=$1 AND status IN ('queued','retryable_failed')", [row.id]);
          await this.audit(db, user.id, 'checkin_paused');
        }
        return this.status(db, user);
      }
      if (path === '/me/checkin/today/resume' && method === 'POST') {
        if (!user.enabled) fail(409, 'program_disabled', 'Önce günlük haber vermeyi etkinleştirin.');
        const row = await this.occurrence(db, user);
        await db.query("UPDATE occurrences SET state='pending' WHERE id=$1 AND state='cancelled'", [row.id]);
        return this.status(db, user);
      }
      if (path === '/me/checkin-schedule' && method === 'GET') {
        const current = await this.schedule(db, user, this.day(user.timezone));
        const next = await this.schedule(db, user, this.nextDay(this.day(user.timezone)));
        return { current, next, timezone: user.timezone };
      }
      if (path === '/me/checkin-schedule' && method === 'PUT') {
        const input = z.object({ minute: z.number().int().min(0).max(1439), grace: z.number().int().min(30).max(720) }).refine(v => v.minute + v.grace < 1440, 'Bekleme süresi aynı güne sığmalı.').parse(body);
        const day = this.nextDay(this.day(user.timezone));
        await db.query('INSERT INTO schedules VALUES($1,$2,$3,$4,$5) ON CONFLICT(user_id,effective_date) DO UPDATE SET minute=$3,grace=$4', [id(), user.id, input.minute, input.grace, day]);
        await this.audit(db, user.id, 'schedule_updated');
        return { ...input, effective_date: day, timezone: user.timezone };
      }
      if (path === '/invitations' && method === 'POST') {
        const input = z.object({ direction: z.enum(['share_mine', 'request_theirs']), label: labels }).parse(body);
        await this.limit(db, `invite:${user.id}`, 10, 86400);
        const invitationToken = opaque(), invitationId = id();
        const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        let code: string;
        do { code = Array.from(randomBytes(12), byte => alphabet[byte & 31]).join(''); }
        while (await this.one(db, 'SELECT id FROM invitations WHERE code_hash=$1', [this.lookup(code)]));
        await db.query('INSERT INTO invitations(id,creator_id,subject_id,recipient_id,token_hash,label,status,expires_at,created_at,code_hash) VALUES($1,$2,$3,NULL,$4,$5,$6,$7,$8,$9)',
          [invitationId, user.id, input.direction === 'share_mine' ? user.id : null, hash(invitationToken), input.label, 'pending', new Date(this.now().getTime() + 48 * 3600000), this.now(), this.lookup(code)]);
        return { id: invitationId, token: invitationToken, code: code.match(/.{4}/g)!.join('-'), expires_in: 172800 };
      }
      if (path === '/invitations' && method === 'GET') {
        return { items: (await db.query("SELECT i.id,i.status,i.label,i.expires_at,u.name AS recipient_name FROM invitations i LEFT JOIN users u ON u.id=i.recipient_id WHERE i.creator_id=$1 AND i.status IN ('pending','awaiting_approval') AND i.expires_at>$2", [user.id, this.now()])).rows };
      }
      if (path === '/invitations/preview' && method === 'POST') {
        const input = invitationCredential.parse(body);
        const invite = await this.one(db, "SELECT i.*,u.name AS creator_name FROM invitations i JOIN users u ON u.id=i.creator_id WHERE (token_hash=$1 OR code_hash=$2) AND status='pending' AND expires_at>$3", [input.token ? hash(input.token) : null, input.code ? this.lookup(input.code) : null, this.now()]);
        if (!invite) fail(404, 'invalid_invitation', 'Davet geçersiz veya süresi dolmuş.');
        return { id: invite.id, creator_name: invite.creator_name, direction: invite.subject_id ? 'share_mine' : 'request_theirs', label: invite.label };
      }
      const invitationAction = path.match(/^\/invitations\/([^/]+)\/(accept|decline|approve-sharing)$/);
      if (invitationAction && method === 'POST') {
        const [, invitationId, action] = invitationAction;
        const invite = await this.one(db, 'SELECT * FROM invitations WHERE id=$1 AND expires_at>$2', [invitationId, this.now()]);
        if (!invite) fail(404, 'invalid_invitation', 'Davet bulunamadı.');
        if (action === 'approve-sharing') {
          if (invite.creator_id !== user.id || invite.subject_id !== user.id || invite.status !== 'awaiting_approval') fail(403, 'forbidden', 'Bu daveti onaylayamazsınız.');
          await this.connect(db, invite.subject_id, invite.recipient_id, invite.label);
          await db.query("UPDATE invitations SET status='accepted' WHERE id=$1", [invite.id]);
          return { status: 'accepted' };
        }
        const input = invitationCredential.parse(body);
        const matches = input.token ? hash(input.token) === invite.token_hash : this.lookup(input.code!) === invite.code_hash;
        if (!matches || invite.status !== 'pending' || invite.creator_id === user.id) fail(403, 'forbidden', 'Bu davet kullanılamıyor.');
        if (action === 'decline') {
          await db.query("UPDATE invitations SET status='declined',recipient_id=$2 WHERE id=$1", [invite.id, user.id]);
          return { status: 'declined' };
        }
        if (invite.subject_id) {
          await db.query("UPDATE invitations SET status='awaiting_approval',recipient_id=$2 WHERE id=$1", [invite.id, user.id]);
          return { status: 'awaiting_approval' };
        }
        await this.connect(db, user.id, invite.creator_id, invite.label);
        await db.query("UPDATE invitations SET status='accepted',recipient_id=$2,subject_id=$2 WHERE id=$1", [invite.id, user.id]);
        return { status: 'accepted' };
      }
      if (path === '/me/relationships' && method === 'GET') {
        return { items: (await db.query('SELECT r.id,r.subject_id,r.viewer_id,r.label,r.authorized_at,s.name AS subject_name,v.name AS viewer_name FROM relationships r JOIN users s ON s.id=r.subject_id JOIN users v ON v.id=r.viewer_id WHERE r.active AND (r.subject_id=$1 OR r.viewer_id=$1)', [user.id])).rows };
      }
      const relationPath = path.match(/^\/me\/relationships\/([^/]+)$/);
      if (relationPath && method === 'DELETE') {
        const relation = await this.one(db, 'SELECT * FROM relationships WHERE id=$1 AND (subject_id=$2 OR viewer_id=$2) AND active', [relationPath[1], user.id]);
        if (!relation) fail(404, 'not_found', 'Paylaşım bulunamadı.');
        await db.query('UPDATE relationships SET active=false WHERE id=$1', [relation.id]);
        await db.query("UPDATE notifications SET status='suppressed' WHERE relationship_id=$1", [relation.id]);
        await this.audit(db, user.id, 'relationship_revoked');
        return { ok: true };
      }
      if (path === '/me/relatives' && method === 'GET') {
        const relatives = (await db.query('SELECT u.* FROM users u JOIN relationships r ON r.subject_id=u.id WHERE r.viewer_id=$1 AND r.active', [user.id])).rows;
        return { items: await Promise.all(relatives.map(async relative => ({ profile: this.profile(relative), today: await this.status(db, relative) }))) };
      }
      const profilePath = path.match(/^\/profiles\/([^/]+)\/(status|checkins)$/);
      if (profilePath && method === 'GET') {
        const relation = await this.authorize(db, user.id, profilePath[1]);
        const subject = await this.one(db, 'SELECT * FROM users WHERE id=$1', [profilePath[1]]);
        if (!subject) fail(404, 'not_found', 'Kişi bulunamadı.');
        if (profilePath[2] === 'status') return { profile: this.profile(subject), today: await this.status(db, subject) };
        const since = new Date(Math.max(this.now().getTime() - 30 * 86400000, relation ? new Date(relation.authorized_at).getTime() : 0));
        return { items: (await db.query('SELECT c.id,c.source,c.received_at,o.local_date FROM checkins c JOIN occurrences o ON o.id=c.occurrence_id WHERE c.actor_id=$1 AND c.received_at >= $2 ORDER BY c.received_at DESC LIMIT 30', [subject.id, since])).rows };
      }
      if (path === '/me/notifications' && method === 'GET') {
        return { items: (await db.query("SELECT n.id,n.type,n.status,n.created_at,n.opened_at,u.name AS subject_name FROM notifications n JOIN occurrences o ON o.id=n.occurrence_id JOIN users u ON u.id=o.user_id LEFT JOIN relationships r ON r.id=n.relationship_id WHERE n.recipient_id=$1 AND n.status<>'suppressed' AND (n.relationship_id IS NULL OR r.active) ORDER BY n.created_at DESC LIMIT 50", [user.id])).rows };
      }
      const notificationPath = path.match(/^\/me\/notifications\/([^/]+)\/opened$/);
      if (notificationPath && method === 'POST') {
        await db.query("UPDATE notifications SET opened_at=$1 WHERE id=$2 AND recipient_id=$3 AND status<>'suppressed'", [this.now(), notificationPath[1], user.id]);
        return { ok: true };
      }
      if (path === '/me/notification-preferences' && method === 'GET') return this.one(db, 'SELECT success,missed,analytics FROM preferences WHERE user_id=$1', [user.id]);
      if (path === '/me/notification-preferences' && method === 'PATCH') {
        const input = z.object({ success: z.boolean(), missed: z.boolean(), analytics: z.boolean() }).parse(body);
        await db.query('UPDATE preferences SET success=$1,missed=$2,analytics=$3 WHERE user_id=$4', [input.success, input.missed, input.analytics, user.id]);
        await db.query('INSERT INTO consent_records VALUES($1,$2,$3,$4,$5,$6)', [id(), user.id, 'product_analytics', '1.0', input.analytics, this.now()]);
        return input;
      }
      if (path === '/me/devices' && method === 'POST') {
        const input = z.object({ id: uuid, token: z.string().regex(/^[a-fA-F0-9]{32,512}$/).optional(), permission: z.enum(['authorized', 'denied', 'not_determined']), locale: z.enum(['tr','en']).optional() }).parse(body);
        const device = await this.one(db, 'SELECT user_id FROM devices WHERE id=$1', [input.id]);
        if (device && device.user_id !== user.id) fail(403, 'forbidden', 'Cihaz kaydı kullanılamıyor.');
        await db.query("INSERT INTO devices(id,user_id,token_encrypted,permission,updated_at,session_family_id,locale) VALUES($1,$2,$3,$4,$5,$6,COALESCE($7,'tr')) ON CONFLICT(id) DO UPDATE SET token_encrypted=COALESCE($3,devices.token_encrypted),permission=$4,updated_at=$5,session_family_id=$6,locale=COALESCE($7,devices.locale)", [input.id, user.id, input.token ? this.encrypt(input.token) : null, input.permission, this.now(), session.family_id, input.locale ?? null]);
        return { ok: true };
      }
      if (path === '/me/sessions' && method === 'GET') return { items: (await db.query('SELECT id,device_name,created_at,id=$2 AS current FROM sessions WHERE user_id=$1 AND NOT revoked AND refresh_expires>$3', [user.id, session.id, this.now()])).rows };
      const sessionPath = path.match(/^\/me\/sessions\/([^/]+)$/);
      if (sessionPath && method === 'DELETE') {
        await db.query('UPDATE sessions SET revoked=true WHERE user_id=$1 AND family_id IN (SELECT family_id FROM sessions WHERE id=$2 AND user_id=$1)', [user.id, sessionPath[1]]);
        await db.query("UPDATE devices SET token_encrypted=NULL,permission='denied' WHERE user_id=$1 AND session_family_id IN (SELECT family_id FROM sessions WHERE id=$2 AND user_id=$1)", [user.id, sessionPath[1]]);
        return { ok: true };
      }
      if (path === '/me/exports' && method === 'POST') {
        await this.audit(db, user.id, 'export_created');
        return { profile: this.profile(user), checkins: (await db.query('SELECT source,received_at FROM checkins WHERE actor_id=$1 ORDER BY received_at DESC', [user.id])).rows,
          consents: (await db.query('SELECT purpose,version,granted,created_at FROM consent_records WHERE user_id=$1', [user.id])).rows };
      }
      if (path === '/me' && method === 'DELETE') {
        z.object({ confirmation: z.literal('HESABIMI SİL') }).parse(body);
        await db.query('DELETE FROM otp_challenges WHERE phone_hash=$1', [user.phone_hash]);
        await db.query('DELETE FROM users WHERE id=$1', [user.id]);
        return { deleted: true };
      }
      fail(404, 'not_found', 'İşlem bulunamadı.');
    });
    if (result?.internal_error) throw new APIError(result.internal_error.status, result.internal_error.code, result.internal_error.message);
    return result;
  }

  private async connect(db: SQL, subject: string, viewer: string, label: string) {
    const exists = await this.one(db, 'SELECT id FROM relationships WHERE subject_id=$1 AND viewer_id=$2 AND active', [subject, viewer]);
    if (exists) return;
    const count = await this.one(db, 'SELECT count(*) AS count FROM relationships WHERE subject_id=$1 AND active', [subject]);
    if (Number(count.count) >= 10) fail(409, 'circle_limit', 'Güven Çemberiniz en fazla on yakından oluşabilir.');
    await db.query('INSERT INTO relationships VALUES($1,$2,$3,$4,true,$5)', [id(), subject, viewer, label, this.now()]);
    await this.audit(db, subject, 'relationship_authorized');
  }

  async tick() {
    return this.database.transaction(async db => {
      const users = (await db.query("SELECT * FROM users WHERE enabled AND name<>''")).rows;
      for (const user of users) {
        const row = await this.occurrence(db, user);
        if (['completed', 'cancelled'].includes(row.state) || new Date(user.activated_at ?? user.created_at) > new Date(row.due_at)) continue;
        if (this.now() >= new Date(row.deadline_at)) {
          await db.query("UPDATE occurrences SET state='overdue' WHERE id=$1 AND state IN ('pending','reminded')", [row.id]);
          const recipients = await this.notify(db, row, 'missed');
          if (recipients > 0) await db.query("UPDATE occurrences SET state='alerted' WHERE id=$1", [row.id]);
          continue;
        }
        const minutes = (this.now().getTime() - new Date(row.due_at).getTime()) / 60000;
        const step = minutes >= 180 ? 2 : minutes >= 60 ? 1 : minutes >= 0 ? 0 : -1;
        if (step < 0) continue;
        const inserted = await db.query('INSERT INTO reminders VALUES($1,$2,$3) ON CONFLICT DO NOTHING RETURNING *', [row.id, step, this.now()]);
        if (inserted.rows.length) {
          await db.query("UPDATE occurrences SET state='reminded' WHERE id=$1", [row.id]);
          await db.query(`INSERT INTO notifications(id,occurrence_id,recipient_id,type,created_at,available_at) VALUES($1,$2,$3,$4,$5,$5)
            ON CONFLICT(occurrence_id,recipient_id,type) DO UPDATE SET status='queued',available_at=$5 WHERE notifications.status='suppressed'`, [id(), row.id, user.id, `reminder_${step}`, this.now()]);
        }
      }
      await db.query("UPDATE notifications SET status='suppressed' WHERE status IN ('queued','retryable_failed') AND occurrence_id IN (SELECT id FROM occurrences WHERE closes_at<=$1)", [this.now()]);
      await db.query('DELETE FROM occurrences WHERE closes_at<$1', [new Date(this.now().getTime() - 30 * 86400000)]);
      await db.query('DELETE FROM idempotency WHERE created_at<$1', [new Date(this.now().getTime() - 30 * 86400000)]);
      await db.query('DELETE FROM otp_challenges WHERE expires_at<$1', [new Date(this.now().getTime() - 86400000)]);
      await db.query('DELETE FROM rate_limits WHERE expires_at<$1', [this.now()]);
      await db.query('DELETE FROM audit_logs WHERE created_at<$1', [new Date(this.now().getTime() - 180 * 86400000)]);
      await db.query('DELETE FROM invitations WHERE expires_at<$1', [new Date(this.now().getTime() - 30 * 86400000)]);
      await db.query('DELETE FROM sessions WHERE refresh_expires<$1', [new Date(this.now().getTime() - 30 * 86400000)]);
      await db.query('UPDATE sessions SET refresh_response_encrypted=NULL,refresh_request_hash=NULL,refresh_replay_until=NULL WHERE refresh_replay_until<=$1', [this.now()]);
      await db.query('DELETE FROM account_recoveries WHERE expires_at<=$1',[this.now()]);
    });
  }
}
