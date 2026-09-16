import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { Database } from '../src/database';
import { Service } from '../src/service';
import { NotificationWorker, DeliveryResult } from '../src/notifications';

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
  assert.deepEqual(versions.rows.map(row => row.version), [1, 2, 3, 4, 5]);
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
