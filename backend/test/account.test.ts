import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { Database } from '../src/database';
import { APIError, Service } from '../src/service';

let db: Database;
let service: Service;
let now = new Date('2026-09-20T05:00:00Z');
const input = (name = 'Ayşe') => ({ name, enabled: true, device_name: 'Account test', registration_secret: randomBytes(32).toString('base64url') });
const rejects = (work: Promise<unknown>, code: string) => assert.rejects(work, (error: any) => error instanceof APIError && error.code === code);
before(async () => {
  db = new Database();
  await db.initialize();
  service = new Service(db, { mode: 'production', encryptionKey: Buffer.alloc(32, 8), lookupKey: 'account-tests', clock: () => now });
});
after(async () => { await db.close(); });

test('same display name creates independent accounts without telephone data', async () => {
  const first = await service.request('POST', '/auth/device', input());
  const second = await service.request('POST', '/auth/device', input());
  assert.notEqual(first.user_id, second.user_id);
  assert.notEqual(first.access_token, second.access_token);
  const profile = await service.request('GET', '/me', {}, first.access_token);
  assert.equal(profile.name, 'Ayşe');
  await rejects(service.request('GET', '/me', {}, first.user_id), 'unauthorized');
  await rejects(service.request('GET', `/profiles/${first.user_id}/status`, {}, second.access_token), 'not_found');
  const users = await db.transaction(tx => tx.query('SELECT phone_hash,phone_encrypted FROM users WHERE id=$1', [first.user_id]));
  assert.equal(users.rows[0].phone_hash, null);
  assert.equal(users.rows[0].phone_encrypted, null);
});
test('registration retry preserves account, rotates response tokens and rejects changed payload', async () => {
  const request = input('Mehmet');
  const first = await service.request('POST', '/auth/device', request);
  const repeated = await service.request('POST', '/auth/device', request);
  assert.equal(repeated.user_id, first.user_id);
  await rejects(service.request('GET', '/me', {}, first.access_token), 'unauthorized');
  assert.ok(await service.request('GET', '/me', {}, repeated.access_token));
  await rejects(service.request('POST', '/auth/device', { ...request, name: 'Başka kişi' }), 'registration_conflict');
});
test('registration secret is not a permanent recovery method and logout invalidates it', async () => {
  const request = input('Hasan');
  const user = await service.request('POST', '/auth/device', request);
  await service.request('POST', '/auth/logout', {}, user.access_token);
  await rejects(service.request('POST', '/auth/device', request), 'registration_expired');
  const expiring = input('Elif');
  await service.request('POST', '/auth/device', expiring);
  now = new Date(now.getTime() + 11 * 60000);
  await rejects(service.request('POST', '/auth/device', expiring), 'registration_expired');
});
test('revoking a device session also prevents bootstrap credential reuse', async () => {
  const request = input('Revoked device');
  const user = await service.request('POST', '/auth/device', request, '', '', 'revocation');
  const sessions = await service.request('GET', '/me/sessions', {}, user.access_token);
  await service.request('DELETE', `/me/sessions/${sessions.items[0].id}`, {}, user.access_token);
  await rejects(service.request('POST', '/auth/device', request), 'registration_expired');
});
test('phone OTP endpoints are retired even outside production', async () => {
  const local = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 8), lookupKey: 'account-tests' });
  await rejects(local.request('POST', '/auth/otp/start', { phone: '+905000000000' }), 'auth_method_removed');
  await rejects(local.request('POST', '/auth/otp/verify', { code: '123456' }), 'auth_method_removed');
});
test('name is not enough for login and registration input is strictly validated', async () => {
  await assert.rejects(service.request('POST', '/auth/device', { name: 'Ayşe' }));
  await assert.rejects(service.request('POST', '/auth/device', { ...input(), name: '  ' }));
  await assert.rejects(service.request('POST', '/auth/device', { ...input(), user_id: 'chosen-id' }));
});
test('registration abuse is rate limited per network without collecting phone numbers', async () => {
  for (let index = 0; index < 10; index++) await service.request('POST', '/auth/device', input(), '', '', 'limit-test');
  await rejects(service.request('POST', '/auth/device', input(), '', '', 'limit-test'), 'rate_limited');
});
test('short invitation code is time-limited and never grants access without owner approval', async () => {
  const owner = await service.request('POST', '/auth/device', input('Owner'), '', '', 'circle');
  const viewer = await service.request('POST', '/auth/device', input('Viewer'), '', '', 'circle');
  const invite = await service.request('POST', '/invitations', { direction: 'share_mine', label: 'Yakınım' }, owner.access_token);
  assert.match(invite.code, /^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  const preview = await service.request('POST', '/invitations/preview', { code: invite.code.toLowerCase() }, viewer.access_token);
  assert.equal(preview.id, invite.id);
  await service.request('POST', `/invitations/${invite.id}/accept`, { code: invite.code }, viewer.access_token);
  await rejects(service.request('GET', `/profiles/${owner.user_id}/status`, {}, viewer.access_token), 'not_found');
  await service.request('POST', `/invitations/${invite.id}/approve-sharing`, {}, owner.access_token);
  assert.ok(await service.request('GET', `/profiles/${owner.user_id}/status`, {}, viewer.access_token));
  await rejects(service.request('POST', '/invitations/preview', { code: invite.code }, viewer.access_token), 'invalid_invitation');
  const expired = await service.request('POST', '/invitations', { direction: 'share_mine', label: 'Yakınım' }, owner.access_token);
  now = new Date(now.getTime() + 49 * 3600000);
  const refreshed = await service.request('POST', '/auth/refresh', { refresh_token: viewer.refresh_token });
  await rejects(service.request('POST', '/invitations/preview', { code: expired.code }, refreshed.access_token), 'invalid_invitation');
});
test('invalid invitation guesses consume the rate limit even when lookup fails', async () => {
  const viewer = await service.request('POST', '/auth/device', input('Guesser'), '', '', 'guesser');
  for (let attempt = 0; attempt < 20; attempt++) await rejects(service.request('POST', '/invitations/preview', { code: 'AAAA-BBBB-CCCC' }, viewer.access_token, '', 'guess-network'), 'invalid_invitation');
  await rejects(service.request('POST', '/invitations/preview', { code: 'AAAA-BBBB-CCCC' }, viewer.access_token, '', 'guess-network'), 'rate_limited');
});
test('omitted registration timezone defaults to Europe/Istanbul', async () => {
  const user = await service.request('POST', '/auth/device', input('Varsayılan'), '', '', 'tz-default');
  assert.equal((await service.request('GET', '/me', {}, user.access_token)).timezone, 'Europe/Istanbul');
});
test('chosen timezone persists across same-secret registration retry', async () => {
  const request = { ...input('Zaman'), timezone: 'America/New_York' };
  const first = await service.request('POST', '/auth/device', request, '', '', 'tz-retry');
  const repeated = await service.request('POST', '/auth/device', request, '', '', 'tz-retry');
  assert.equal(repeated.user_id, first.user_id);
  assert.equal((await service.request('GET', '/me', {}, repeated.access_token)).timezone, 'America/New_York');
});
test('changing timezone with the same registration secret conflicts', async () => {
  const request = { ...input('Çakışma'), timezone: 'Asia/Tokyo' };
  await service.request('POST', '/auth/device', request, '', '', 'tz-conflict');
  await rejects(service.request('POST', '/auth/device', { ...request, timezone: 'Europe/Istanbul' }, '', '', 'tz-conflict'), 'registration_conflict');
});
test('invalid timezone names are rejected', async () => {
  await assert.rejects(service.request('POST', '/auth/device', { ...input('Mars'), timezone: 'Mars/Olympus' }, '', '', 'tz-invalid'));
});

// --- Kurtarma anahtarı (v7) -------------------------------------------------
const recoveryKey = () => 'HYR1.' + randomBytes(32).toString('base64url');
const recover = (oldKey: string, replacement: string, requestId: string, ip: string, device = 'New phone') =>
  service.request('POST', '/auth/recover', { recovery_key: oldKey, replacement_key: replacement, request_id: requestId, device_name: device }, '', '', ip);

test('recovery key endpoints are owner-authenticated and strictly validated', async () => {
  const user = await service.request('POST', '/auth/device', input('Kurtarma'), '', '', 'rc-auth');
  await rejects(service.request('GET', '/me/recovery-key'), 'unauthorized');
  await rejects(service.request('PUT', '/me/recovery-key', { recovery_key: recoveryKey(), expected_version: 0 }), 'unauthorized');
  await rejects(service.request('DELETE', '/me/recovery-key', { expected_version: 0 }), 'unauthorized');
  await assert.rejects(service.request('PUT', '/me/recovery-key', { recovery_key: recoveryKey(), expected_version: 0, user_id: user.user_id }, user.access_token));
  await assert.rejects(service.request('PUT', '/me/recovery-key', { recovery_key: 'AYŞE-1234', expected_version: 0 }, user.access_token));
  await assert.rejects(service.request('PUT', '/me/recovery-key', { recovery_key: recoveryKey().slice(0, -1) + '=', expected_version: 0 }, user.access_token));
});

test('recovery key lifecycle: disabled legacy state, enable once, idempotent retry, version guard', async () => {
  const user = await service.request('POST', '/auth/device', input('Anahtar'), '', '', 'rc-cycle');
  const initial = await service.request('GET', '/me/recovery-key', {}, user.access_token);
  assert.deepEqual(initial, { enabled: false, version: 0, updated_at: null });
  const key = recoveryKey();
  const enabled = await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, user.access_token);
  assert.equal(enabled.enabled, true);
  assert.equal(enabled.version, 1);
  assert.ok(enabled.updated_at);
  // Kayıp yanıtın tekrarı: aynı anahtar + eski sürüm yine mevcut durumu döndürür.
  const replay = await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, user.access_token);
  assert.equal(replay.version, 1);
  const stored = await db.transaction(tx => tx.query('SELECT recovery_key_hash FROM users WHERE id=$1', [user.user_id]));
  assert.match(stored.rows[0].recovery_key_hash, /^[a-f0-9]{64}$/);
  assert.equal(stored.rows[0].recovery_key_hash.includes(key), false);
  await rejects(service.request('PUT', '/me/recovery-key', { recovery_key: recoveryKey(), expected_version: 0 }, user.access_token), 'recovery_changed');
});

test('key belongs to one account and rotation invalidates the old key', async () => {
  const first = await service.request('POST', '/auth/device', input('Bir'), '', '', 'rc-own1');
  const second = await service.request('POST', '/auth/device', input('İki'), '', '', 'rc-own2');
  const key = recoveryKey();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, first.access_token);
  await rejects(service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, second.access_token), 'recovery_key_unavailable');
  const next = recoveryKey();
  const rotated = await service.request('PUT', '/me/recovery-key', { recovery_key: next, expected_version: 1 }, first.access_token);
  assert.equal(rotated.version, 2);
  await rejects(service.request('POST', '/auth/recover', { recovery_key: key, replacement_key: recoveryKey(), request_id: randomUUID(), device_name: 'X' }, '', '', 'rc-rot'), 'recovery_invalid');
});

test('disabling is idempotent and a disabled key cannot recover', async () => {
  const user = await service.request('POST', '/auth/device', input('Kapatma'), '', '', 'rc-off');
  const key = recoveryKey();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, user.access_token);
  const disabled = await service.request('DELETE', '/me/recovery-key', { expected_version: 1 }, user.access_token);
  assert.equal(disabled.enabled, false);
  assert.equal(disabled.version, 2);
  const again = await service.request('DELETE', '/me/recovery-key', { expected_version: 1 }, user.access_token);
  assert.equal(again.enabled, false);
  await rejects(recover(key, recoveryKey(), randomUUID(), 'rc-off-net'), 'recovery_invalid');
});

test('recovery returns the same account with history and relationships, revokes old sessions and devices', async () => {
  const secret = randomBytes(32).toString('base64url');
  const owner = await service.request('POST', '/auth/device', { ...input('Sahip'), registration_secret: secret }, '', '', 'rc-full1');
  const viewer = await service.request('POST', '/auth/device', input('İzleyen'), '', '', 'rc-full2');
  const invite = await service.request('POST', '/invitations', { direction: 'share_mine', label: 'Yakınım' }, owner.access_token);
  await service.request('POST', `/invitations/${invite.id}/accept`, { token: invite.token }, viewer.access_token);
  await service.request('POST', `/invitations/${invite.id}/approve-sharing`, {}, owner.access_token);
  const today = await service.request('GET', '/me/checkin/today', {}, owner.access_token);
  await service.request('POST', '/me/checkins', { occurrence_id: today.id, source: 'app', client_action_at: now.toISOString() }, owner.access_token, randomUUID());
  await service.request('POST', '/me/devices', { id: randomUUID(), token: 'a'.repeat(64), permission: 'authorized', locale: 'tr' }, owner.access_token);
  const key = recoveryKey();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, owner.access_token);

  const replacement = recoveryKey();
  const recovered = await recover(key, replacement, randomUUID(), 'rc-full-net');
  assert.equal(recovered.user_id, owner.user_id);
  await rejects(service.request('GET', '/me', {}, owner.access_token), 'unauthorized');
  const profile = await service.request('GET', '/me', {}, recovered.access_token);
  assert.equal(profile.name, 'Sahip');
  assert.equal(profile.timezone, 'Europe/Istanbul');
  assert.equal((await service.request('GET', '/me/relationships', {}, recovered.access_token)).items.length, 1);
  const history = await service.request('GET', `/profiles/${owner.user_id}/checkins`, {}, viewer.access_token);
  assert.equal(history.items.length, 1);
  const devices = await db.transaction(tx => tx.query('SELECT token_encrypted,permission FROM devices WHERE user_id=$1', [owner.user_id]));
  assert.equal(devices.rows[0].token_encrypted, null);
  assert.equal(devices.rows[0].permission, 'denied');
  const status = await service.request('GET', '/me/recovery-key', {}, recovered.access_token);
  assert.equal(status.version, 2);
  // Ad, hesap kimliği ve davet kodu kurtarma kimliği değildir; bootstrap sırrı da eski aileyi açamaz.
  await assert.rejects(recover('Sahip', recoveryKey(), randomUUID(), 'rc-full-net'));
  await rejects(recover(key, recoveryKey(), randomUUID(), 'rc-full-net'), 'recovery_invalid');
  const rekeyed = await recover(replacement, recoveryKey(), randomUUID(), 'rc-full-net');
  assert.equal(rekeyed.user_id, owner.user_id);
  await rejects(service.request('GET', '/me', {}, recovered.access_token), 'unauthorized');
  await rejects(service.request('POST', '/auth/device', { ...input('Sahip'), registration_secret: secret }, '', '', 'rc-full1'), 'registration_expired');
});

test('same request replays stored response; different request cannot reuse the old key', async () => {
  const user = await service.request('POST', '/auth/device', input('Tekrar'), '', '', 'rc-replay');
  const key = recoveryKey(), replacement = recoveryKey(), requestId = randomUUID();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, user.access_token);
  const [a, b] = await Promise.all([recover(key, replacement, requestId, 'rc-replay-net'), recover(key, replacement, requestId, 'rc-replay-net')]);
  assert.deepEqual(a, b);
  // Aynı eski anahtarla yarışan iki FARKLI istekten yalnızca biri başarılı olabilir.
  const user2 = await service.request('POST', '/auth/device', input('Yarış'), '', '', 'rc-race');
  const key2 = recoveryKey();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key2, expected_version: 0 }, user2.access_token);
  const raced = await Promise.allSettled([recover(key2, recoveryKey(), randomUUID(), 'rc-race-net'), recover(key2, recoveryKey(), randomUUID(), 'rc-race-net')]);
  assert.equal(raced.filter(v => v.status === 'fulfilled').length, 1);
  assert.equal(raced.filter(v => v.status === 'rejected' && (v.reason as APIError).code === 'recovery_invalid').length, 1);
  // Değiştirilmiş parmak izi ne kurtarılan aileyi döndürür ne de iptal eder.
  await rejects(recover(key, replacement, requestId, 'rc-replay-net', 'Different device'), 'recovery_invalid');
  const stillValid = await service.request('GET', '/me', {}, a.access_token);
  assert.equal(stillValid.id, user.user_id);
});

test('expired, logged-out or rotated recovery requests cannot resurrect the family', async () => {
  const user = await service.request('POST', '/auth/device', input('Zaman'), '', '', 'rc-exp');
  const key = recoveryKey(), replacement = recoveryKey(), requestId = randomUUID();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, user.access_token);
  const recovered = await recover(key, replacement, requestId, 'rc-exp-net');
  // 10 dakikalık pencereden sonra aynı istek tekrarı geçersiz.
  now = new Date(now.getTime() + 11 * 60000);
  await rejects(recover(key, replacement, requestId, 'rc-exp-net'), 'recovery_invalid');
  // Oturum kapatılan aile için saklı yanıt da açılmaz.
  const user2 = await service.request('POST', '/auth/device', input('Çıkış'), '', '', 'rc-out');
  const key2 = recoveryKey(), rep2 = recoveryKey(), req2 = randomUUID();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key2, expected_version: 0 }, user2.access_token);
  const recovered2 = await recover(key2, rep2, req2, 'rc-out-net');
  await service.request('POST', '/auth/logout', {}, recovered2.access_token);
  await rejects(recover(key2, rep2, req2, 'rc-out-net'), 'recovery_invalid');
  // Kullanıcı anahtarı yenilediyse saklı yanıt artık geçersiz; güncel anahtarla yeni bilinçli kurtarma yapılabilir.
  const user3 = await service.request('POST', '/auth/device', input('Yenile'), '', '', 'rc-rot2');
  const key3 = recoveryKey(), rep3 = recoveryKey(), req3 = randomUUID();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key3, expected_version: 0 }, user3.access_token);
  const recovered3 = await recover(key3, rep3, req3, 'rc-rot2-net');
  const newer = recoveryKey();
  await service.request('PUT', '/me/recovery-key', { recovery_key: newer, expected_version: (await service.request('GET', '/me/recovery-key', {}, recovered3.access_token)).version }, recovered3.access_token);
  await rejects(recover(key3, rep3, req3, 'rc-rot2-net'), 'recovery_invalid');
  const conscious = await recover(newer, recoveryKey(), randomUUID(), 'rc-rot2-net');
  assert.equal(conscious.user_id, user3.user_id);
});

test('recovery rows hold only digests and encrypted responses; cleanup and cascade work', async () => {
  const user = await service.request('POST', '/auth/device', input('Depo'), '', '', 'rc-store');
  const key = recoveryKey(), replacement = recoveryKey(), requestId = randomUUID();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, user.access_token);
  const recovered = await recover(key, replacement, requestId, 'rc-store-net');
  const rows = await db.transaction(tx => tx.query('SELECT * FROM account_recoveries WHERE user_id=$1', [user.user_id]));
  assert.equal(rows.rows.length, 1);
  const row = rows.rows[0];
  for (const field of ['request_hash', 'old_key_hash', 'replacement_key_hash', 'fingerprint']) assert.match(row[field], /^[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(row).includes(key), false);
  assert.equal(JSON.stringify(row).includes(replacement), false);
  assert.equal(JSON.stringify(row).includes(recovered.access_token), false);
  assert.deepEqual(JSON.parse(service.decrypt(row.response_encrypted)), recovered);
  // 10 dakika geçince tick temizler.
  now = new Date(now.getTime() + 11 * 60000);
  await service.tick();
  assert.equal((await db.transaction(tx => tx.query('SELECT 1 FROM account_recoveries WHERE user_id=$1', [user.user_id]))).rows.length, 0);
  // Hesap silme kayıtları cascade ile siler.
  const user2 = await service.request('POST', '/auth/device', input('Silme'), '', '', 'rc-cascade');
  const key2 = recoveryKey(), rep2 = recoveryKey();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key2, expected_version: 0 }, user2.access_token);
  const recovered2 = await recover(key2, rep2, randomUUID(), 'rc-cascade-net');
  const status2 = await service.request('GET', '/me/recovery-key', {}, recovered2.access_token);
  assert.equal(status2.enabled, true);
  await service.request('DELETE', '/me', { confirmation: 'HESABIMI SİL' }, recovered2.access_token);
  assert.equal((await db.transaction(tx => tx.query('SELECT 1 FROM account_recoveries WHERE user_id=$1', [user2.user_id]))).rows.length, 0);
});

test('invalid recovery guesses consume the committed network rate limit', async () => {
  for (let attempt = 0; attempt < 10; attempt++) {
    await rejects(recover(recoveryKey(), recoveryKey(), randomUUID(), 'rc-limit-net'), 'recovery_invalid');
  }
  await rejects(recover(recoveryKey(), recoveryKey(), randomUUID(), 'rc-limit-net'), 'rate_limited');
});

test('key setup and recovery do not disturb history, name, timezone or the schedule', async () => {
  const user = await service.request('POST', '/auth/device', { ...input('Sabit'), timezone: 'America/New_York' }, '', '', 'rc-stable');
  const today = await service.request('GET', '/me/checkin/today', {}, user.access_token);
  await service.request('POST', '/me/checkins', { occurrence_id: today.id, source: 'app', client_action_at: now.toISOString() }, user.access_token, randomUUID());
  const key = recoveryKey();
  await service.request('PUT', '/me/recovery-key', { recovery_key: key, expected_version: 0 }, user.access_token);
  const recovered = await recover(key, recoveryKey(), randomUUID(), 'rc-stable-net');
  const profile = await service.request('GET', '/me', {}, recovered.access_token);
  assert.equal(profile.name, 'Sabit');
  assert.equal(profile.timezone, 'America/New_York');
  const status = await service.request('GET', '/me/checkin/today', {}, recovered.access_token);
  assert.equal(status.state, 'completed');
});
