import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { Database } from '../src/database';
import { APIError, Service } from '../src/service';

let db: Database;
let service: Service;
let clock = new Date('2026-09-15T05:00:00Z');
let sequence = 0;
const rejects = (work: Promise<unknown>, code: string) => assert.rejects(work, (e: any) => e instanceof APIError && e.code === code);
async function account(name = 'Ayşe') {
  return service.request('POST', '/auth/device', { name, enabled: true, device_name: 'Test', registration_secret: randomBytes(32).toString('base64url') }, '', '', `fixture-${++sequence}`);
}
async function connect(subject: any, viewer: any) {
  const invite = await service.request('POST', '/invitations', { direction: 'share_mine', label: 'Yakınım' }, subject.access_token);
  const accepted = await service.request('POST', `/invitations/${invite.id}/accept`, { token: invite.token }, viewer.access_token);
  assert.equal(accepted.status, 'awaiting_approval');
  await service.request('POST', `/invitations/${invite.id}/approve-sharing`, {}, subject.access_token);
}
async function checkin(user: any, source = 'app', key = randomUUID(), at = clock.toISOString()) {
  const today = await service.request('GET', '/me/checkin/today', {}, user.access_token);
  return service.request('POST', '/me/checkins', { occurrence_id: today.id, source, client_action_at: at }, user.access_token, key);
}
before(async () => {
  db = new Database();
  await db.initialize();
  service = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 7), lookupKey: 'tests-only', clock: () => clock });
});
after(async () => { await db.close(); });

test('display name cannot replace a valid session', async () => {
  await account('Ayşe');
  await rejects(service.request('GET', '/me', {}, 'Ayşe'), 'unauthorized');
});
test('concurrent app/widget check-ins produce one record and one notification', async () => {
  const subject = await account(), viewer = await account('Mehmet');
  await connect(subject, viewer);
  const results = await Promise.all([checkin(subject), checkin(subject, 'ios_widget')]);
  assert.equal(results[0].checkin_id, results[1].checkin_id);
  assert.equal(results.filter(v => v.already_completed).length, 1);
  const notifications = await service.request('GET', '/me/notifications', {}, viewer.access_token);
  assert.equal(notifications.items.length, 1);
});
test('lost response retry returns original receipt, different payload conflicts', async () => {
  const user = await account();
  const today = await service.request('GET', '/me/checkin/today', {}, user.access_token);
  const input = { occurrence_id: today.id, source: 'app', client_action_at: clock.toISOString() };
  const key = randomUUID();
  const first = await service.request('POST', '/me/checkins', input, user.access_token, key);
  assert.deepEqual(await service.request('POST', '/me/checkins', input, user.access_token, key), first);
  await rejects(service.request('POST', '/me/checkins', { ...input, source: 'ios_widget' }, user.access_token, key), 'idempotency_conflict');
});
test('unapproved recipient cannot see subject; revocation removes access', async () => {
  const subject = await account(), viewer = await account('Elif');
  const invite = await service.request('POST', '/invitations', { direction: 'share_mine', label: 'Yakınım' }, subject.access_token);
  await service.request('POST', `/invitations/${invite.id}/accept`, { token: invite.token }, viewer.access_token);
  await rejects(service.request('GET', `/profiles/${subject.user_id}/status`, {}, viewer.access_token), 'not_found');
  await service.request('POST', `/invitations/${invite.id}/approve-sharing`, {}, subject.access_token);
  assert.ok(await service.request('GET', `/profiles/${subject.user_id}/status`, {}, viewer.access_token));
  const relations = await service.request('GET', '/me/relationships', {}, subject.access_token);
  await service.request('DELETE', `/me/relationships/${relations.items[0].id}`, {}, subject.access_token);
  await rejects(service.request('GET', `/profiles/${subject.user_id}/checkins`, {}, viewer.access_token), 'not_found');
});
test('pause blocks completion and resume restores conscious check-in', async () => {
  const user = await account();
  const paused = await service.request('POST', '/me/checkin/today/pause', {}, user.access_token);
  assert.equal(paused.state, 'cancelled');
  await rejects(checkin(user), 'paused');
  await service.request('POST', '/me/checkin/today/resume', {}, user.access_token);
  assert.equal((await checkin(user)).status, 'completed');
  assert.equal((await service.request('POST', '/me/checkin/today/pause', {}, user.access_token)).state, 'completed');
});
test('schedule applies tomorrow and rejects midnight overflow', async () => {
  const user = await account();
  await service.request('PUT', '/me/checkin-schedule', { minute: 600, grace: 120 }, user.access_token);
  const schedule = await service.request('GET', '/me/checkin-schedule', {}, user.access_token);
  assert.equal(schedule.current.minute, 540);
  assert.equal(schedule.next.minute, 600);
  await assert.rejects(service.request('PUT', '/me/checkin-schedule', { minute: 1380, grace: 120 }, user.access_token));
});
test('stale offline action is not accepted as fresh proof', async () => {
  const user = await account();
  await rejects(checkin(user, 'app', randomUUID(), new Date(clock.getTime() - 3600000).toISOString()), 'stale_action');
});
test('refresh rotation and reuse revoke the token family', async () => {
  const user = await account();
  const rotated = await service.request('POST', '/auth/refresh', { refresh_token: user.refresh_token });
  await rejects(service.request('GET', '/me', {}, user.access_token), 'unauthorized');
  assert.ok(await service.request('GET', '/me', {}, rotated.access_token));
  await rejects(service.request('POST', '/auth/refresh', { refresh_token: user.refresh_token }), 'session_reused');
  await rejects(service.request('GET', '/me', {}, rotated.access_token), 'unauthorized');
});
test('deletion removes account, check-ins and active sessions', async () => {
  const user = await account();
  await checkin(user);
  const exported = await service.request('POST', '/me/exports', {}, user.access_token);
  assert.equal(exported.checkins.length, 1);
  assert.equal(JSON.stringify(exported).includes('phone'), false);
  await service.request('DELETE', '/me', { confirmation: 'HESABIMI SİL' }, user.access_token);
  await rejects(service.request('GET', '/me', {}, user.access_token), 'unauthorized');
  const rows = await db.transaction(tx => tx.query('SELECT * FROM checkins WHERE actor_id=$1', [user.user_id]));
  assert.equal(rows.rows.length, 0);
});
test('scheduler reminder, grace alert, late completion and cancelled day', async () => {
  clock = new Date('2026-09-16T05:59:00Z');
  const subject = await account(), viewer = await account('Hasan');
  await connect(subject, viewer);
  clock = new Date('2026-09-16T06:00:00Z');
  await service.tick();
  assert.equal((await service.request('GET', '/me/checkin/today', {}, subject.access_token)).state, 'reminded');
  clock = new Date('2026-09-16T10:00:00Z');
  const refreshedSubject = await service.request('POST', '/auth/refresh', { refresh_token: subject.refresh_token });
  const refreshedViewer = await service.request('POST', '/auth/refresh', { refresh_token: viewer.refresh_token });
  await service.tick();
  await service.tick();
  assert.equal((await service.request('GET', '/me/checkin/today', {}, refreshedSubject.access_token)).state, 'alerted');
  const notices = await service.request('GET', '/me/notifications', {}, refreshedViewer.access_token);
  assert.equal(notices.items.filter((n: any) => n.type === 'missed').length, 1);
  await checkin(refreshedSubject);
  await service.tick();
  assert.equal((await service.request('GET', '/me/checkin/today', {}, refreshedSubject.access_token)).state, 'completed');
  const paused = await account();
  await service.request('POST', '/me/checkin/today/pause', {}, paused.access_token);
  await service.tick();
  assert.equal((await service.request('GET', '/me/checkin/today', {}, paused.access_token)).state, 'cancelled');
});
test('expired day cannot complete next day', async () => {
  const user = await account();
  const today = await service.request('GET', '/me/checkin/today', {}, user.access_token);
  clock = new Date('2026-09-17T05:00:00Z');
  const session = await service.request('POST', '/auth/refresh', { refresh_token: user.refresh_token });
  await rejects(service.request('POST', '/me/checkins', { occurrence_id: today.id, source: 'app', client_action_at: clock.toISOString() }, session.access_token, randomUUID()), 'stale_day');
});
test('late onboarding starts reminders tomorrow instead of immediately alerting family', async () => {
  clock = new Date('2026-09-17T11:00:00Z');
  const user = await account('Late onboarding');
  await service.tick();
  const today = await service.request('GET', '/me/checkin/today', {}, user.access_token);
  assert.equal(today.state, 'pending');
  assert.equal(today.reminders_enabled, false);
  assert.equal((await checkin(user)).status, 'completed');
});
test('family-only role has no personal reminders and activation does not backdate its schedule', async () => {
  clock = new Date('2026-09-18T11:00:00Z');
  const user = await account('Viewer only');
  await service.request('PATCH', '/me/profile', { name: 'Viewer only', enabled: false }, user.access_token);
  await service.tick();
  assert.equal((await service.request('GET', '/me', {}, user.access_token)).enabled, false);
  await rejects(checkin(user), 'program_disabled');
  await rejects(service.request('POST', '/me/checkin/today/resume', {}, user.access_token), 'program_disabled');
  await service.request('PATCH', '/me/profile', { name: 'Viewer only', enabled: true }, user.access_token);
  const today = await service.request('GET', '/me/checkin/today', {}, user.access_token);
  assert.equal(today.state, 'pending');
  assert.equal(today.reminders_enabled, false);
  assert.equal((await checkin(user)).status, 'completed');
});
