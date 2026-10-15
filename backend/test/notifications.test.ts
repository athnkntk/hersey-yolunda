import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { Database } from '../src/database';
import { Service } from '../src/service';
import { NotificationWorker, DeliveryResult, pushPayload } from '../src/notifications';
import { errorMessage, languageFor } from '../src/localization';

let db: Database, service: Service;
let now = new Date('2026-09-15T06:00:00Z');
let sequence = 0;
async function user() {
  return service.request('POST', '/auth/device', { name: 'Test', enabled: true, device_name: 'Push test', registration_secret: randomBytes(32).toString('base64url') }, '', '', `fixture-${++sequence}`);
}
async function fixture() {
  const subject = await user(), viewer = await user();
  const invite = await service.request('POST', '/invitations', { direction: 'request_theirs', label: 'Yakınım' }, viewer.access_token);
  await service.request('POST', `/invitations/${invite.id}/accept`, { token: invite.token }, subject.access_token);
  await service.request('POST', '/me/devices', { id: randomUUID(), token: 'a'.repeat(64), permission: 'authorized' }, viewer.access_token);
  const today = await service.request('GET', '/me/checkin/today', {}, subject.access_token);
  await service.request('POST', '/me/checkins', { occurrence_id: today.id, source: 'app', client_action_at: now.toISOString() }, subject.access_token, randomUUID());
  return { subject, viewer };
}
before(async () => {
  db = new Database();
  await db.initialize();
  service = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 1), lookupKey: 'test', clock: () => now });
});
after(async () => { await db.close(); });

test('migration initialization is repeatable', async () => {
  await db.initialize();
  const versions = await db.transaction(tx => tx.query('SELECT version FROM schema_migrations ORDER BY version'));
  assert.deepEqual(versions.rows.map(row => row.version), [1, 2, 3, 4, 5, 6]);
});
test('transport is called once after provider acceptance', async () => {
  const { viewer } = await fixture();
  let calls = 0;
  const worker = new NotificationWorker(db, { send: async () => { calls++; return 'accepted'; } }, value => service.decrypt(value), () => now);
  await worker.run();
  await worker.run();
  assert.equal(calls, 1);
  const notices = await service.request('GET', '/me/notifications', {}, viewer.access_token);
  assert.equal(notices.items[0].status, 'provider_accepted');
});
test('temporary failure retries after backoff, without false success', async () => {
  const { viewer } = await fixture();
  let calls = 0;
  const worker = new NotificationWorker(db, { send: async (): Promise<DeliveryResult> => ++calls === 1 ? 'retry' : 'accepted' }, value => service.decrypt(value), () => now);
  await worker.run();
  await worker.run();
  assert.equal(calls, 1);
  const notices = await service.request('GET', '/me/notifications', {}, viewer.access_token);
  assert.equal(notices.items[0].status, 'queued');
  now = new Date(now.getTime() + 10000);
  await worker.run();
  assert.equal(calls, 2);
});
test('revoked relationship suppresses queued delivery', async () => {
  const { subject } = await fixture();
  const relations = await service.request('GET', '/me/relationships', {}, subject.access_token);
  await service.request('DELETE', `/me/relationships/${relations.items[0].id}`, {}, subject.access_token);
  let calls = 0;
  const worker = new NotificationWorker(db, { send: async () => { calls++; return 'accepted'; } }, value => service.decrypt(value), () => now);
  await worker.run();
  assert.equal(calls, 0);
});
test('invalid device is disabled, never retried indefinitely', async () => {
  await fixture();
  let calls = 0;
  const worker = new NotificationWorker(db, { send: async () => { calls++; return 'invalid_device'; } }, value => service.decrypt(value), () => now);
  await worker.run();
  await worker.run();
  assert.equal(calls, 1);
  const disabled = await db.transaction(tx => tx.query('SELECT * FROM devices WHERE token_encrypted IS NULL'));
  assert.equal(disabled.rows.length, 1);
});
test('retry exhaustion produces a dead-letter status', async () => {
  await fixture();
  let calls = 0;
  const worker = new NotificationWorker(db, { send: async () => { calls++; return 'retry'; } }, value => service.decrypt(value), () => now);
  for (let i = 0; i < 7; i++) {
    await worker.run();
    now = new Date(now.getTime() + 60000);
  }
  assert.equal(calls, 5);
  const failed = await db.transaction(tx => tx.query("SELECT * FROM notification_deliveries WHERE status='permanently_failed'"));
  assert.ok(failed.rows.length >= 1);
});
test('logout removes the device token and prevents queued delivery', async () => {
  const { viewer } = await fixture();
  await service.request('POST', '/auth/logout', {}, viewer.access_token);
  let calls = 0;
  const worker = new NotificationWorker(db, { send: async () => { calls++; return 'accepted'; } }, value => service.decrypt(value), () => now);
  await worker.run();
  assert.equal(calls, 0);
  const devices = await db.transaction(tx => tx.query('SELECT token_encrypted,permission FROM devices WHERE user_id=$1', [viewer.user_id]));
  assert.equal(devices.rows[0].token_encrypted, null);
  assert.equal(devices.rows[0].permission, 'denied');
});
test('re-registering a device without a token keeps the stored push token', async () => {
  const owner = await user();
  const device = randomUUID();
  await service.request('POST', '/me/devices', { id: device, token: 'b'.repeat(64), permission: 'authorized' }, owner.access_token);
  await service.request('POST', '/me/devices', { id: device, permission: 'authorized' }, owner.access_token);
  const row = await db.transaction(tx => tx.query('SELECT token_encrypted FROM devices WHERE id=$1', [device]));
  assert.ok(row.rows[0].token_encrypted);
});
test('push payload localizes body per device locale and carries event type', async () => {
  const reminderEn = pushPayload({ id: 'n1', type: 'reminder_0', locale: 'en' });
  assert.equal(reminderEn.aps.alert.body, 'Remember to send your daily check-in.');
  assert.equal(reminderEn.event_type, 'reminder_0');
  const missedEn = pushPayload({ id: 'n2', type: 'missed', locale: 'en' });
  assert.equal(missedEn.aps.alert.body, 'There is an update from your family.');
  assert.equal(missedEn.event_id, 'n2');
  const reminderTr = pushPayload({ id: 'n3', type: 'reminder_1', locale: 'tr' });
  assert.equal(reminderTr.aps.alert.body, 'Bugünkü haberinizi göndermeyi unutmayın.');
  const missedTr = pushPayload({ id: 'n4', type: 'missed' });
  assert.equal(missedTr.aps.alert.body, 'Yakınınızdan yeni bir haber var.');
});
test('each recipient device receives push text in its own locale', async () => {
  const subject = await user(), viewer = await user();
  const invite = await service.request('POST', '/invitations', { direction: 'request_theirs', label: 'Yakınım' }, viewer.access_token);
  await service.request('POST', `/invitations/${invite.id}/accept`, { token: invite.token }, subject.access_token);
  await service.request('POST', '/me/devices', { id: randomUUID(), token: 'a'.repeat(64), permission: 'authorized', locale: 'tr' }, viewer.access_token);
  await service.request('POST', '/me/devices', { id: randomUUID(), token: 'b'.repeat(64), permission: 'authorized', locale: 'en' }, viewer.access_token);
  const today = await service.request('GET', '/me/checkin/today', {}, subject.access_token);
  await service.request('POST', '/me/checkins', { occurrence_id: today.id, source: 'app', client_action_at: now.toISOString() }, subject.access_token, randomUUID());
  const sent: any[] = [];
  const worker = new NotificationWorker(db, { send: async (token, event) => { sent.push(event); return 'accepted'; } }, value => service.decrypt(value), () => now);
  await worker.run();
  assert.equal(sent.length, 2);
  assert.deepEqual(sent.map(event => event.locale).sort(), ['en', 'tr']);
  assert.ok(sent.every(event => event.type === 'completed'));
});
test('re-registering a device without locale keeps the stored locale and token', async () => {
  const owner = await user();
  const device = randomUUID();
  await service.request('POST', '/me/devices', { id: device, token: 'c'.repeat(64), permission: 'authorized', locale: 'en' }, owner.access_token);
  await service.request('POST', '/me/devices', { id: device, permission: 'authorized' }, owner.access_token);
  const row = await db.transaction(tx => tx.query('SELECT token_encrypted,locale FROM devices WHERE id=$1', [device]));
  assert.ok(row.rows[0].token_encrypted);
  assert.equal(row.rows[0].locale, 'en');
});
test('accept-language negotiation and english error mapping', async () => {
  assert.equal(languageFor('en-US'), 'en');
  assert.equal(languageFor('tr-TR'), 'tr');
  assert.equal(languageFor('fr-FR'), 'en');
  assert.equal(languageFor(undefined), 'tr');
  assert.equal(languageFor('tr;q=0'), 'en');
  assert.equal(languageFor('en;q=0.5,tr;q=0.9'), 'tr');
  assert.equal(errorMessage('paused', 'Bugünkü kontrol devre dışı.', 'en'), 'Today’s check-in is paused. Resume it first.');
  assert.equal(errorMessage('paused', 'Bugünkü kontrol devre dışı.', 'tr'), 'Bugünkü kontrol devre dışı.');
  assert.equal(errorMessage('unknown_code', 'x', 'en'), 'The request could not be completed. Please try again.');
});
test('missed alert suppressed by pause is re-queued after resume', async () => {
  now = new Date('2026-09-21T05:30:00Z');
  const subject = await user(), viewer = await user();
  const invite = await service.request('POST', '/invitations', { direction: 'request_theirs', label: 'Yakınım' }, viewer.access_token);
  await service.request('POST', `/invitations/${invite.id}/accept`, { token: invite.token }, subject.access_token);
  now = new Date('2026-09-21T10:30:00Z');
  const subjectRefreshed = await service.request('POST', '/auth/refresh', { refresh_token: subject.refresh_token });
  const viewerRefreshed = await service.request('POST', '/auth/refresh', { refresh_token: viewer.refresh_token });
  await service.tick();
  let notices = await service.request('GET', '/me/notifications', {}, viewerRefreshed.access_token);
  assert.equal(notices.items.filter((n: any) => n.type === 'missed').length, 1);
  await service.request('POST', '/me/checkin/today/pause', {}, subjectRefreshed.access_token);
  await service.request('POST', '/me/checkin/today/resume', {}, subjectRefreshed.access_token);
  await service.tick();
  notices = await service.request('GET', '/me/notifications', {}, viewerRefreshed.access_token);
  assert.equal(notices.items.filter((n: any) => n.type === 'missed').length, 1);
});
