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

async function isolated(at: Date) {
  const database = new Database();
  await database.initialize();
  let localClock = at;
  const local = new Service(database, { mode: 'test', encryptionKey: Buffer.alloc(32, 6), lookupKey: 'isolated-calendar', clock: () => localClock });
  const register = (timezone: string, ip: string) => local.request('POST', '/auth/device',
    { name: 'Ayşe', enabled: true, device_name: 'Calendar', registration_secret: randomBytes(32).toString('base64url'), timezone }, '', '', ip);
  const tap = async (user: any) => {
    const today = await local.request('GET', '/me/checkin/today', {}, user.access_token);
    return local.request('POST', '/me/checkins', { occurrence_id: today.id, source: 'app', client_action_at: localClock.toISOString() }, user.access_token, randomUUID());
  };
  return { database, local, register, tap, setClock: (value: Date) => { localClock = value; } };
}

test('occurrence calendar honours each account timezone', async t => {
  const cases = [
    { timezone: 'Europe/Istanbul', local_date: '2026-10-15', starts_at: '2026-10-14T21:00:00.000Z', due_at: '2026-10-15T06:00:00.000Z', closes_at: '2026-10-15T21:00:00.000Z', effective: '2026-10-16' },
    { timezone: 'America/Los_Angeles', local_date: '2026-10-14', starts_at: '2026-10-14T07:00:00.000Z', due_at: '2026-10-14T16:00:00.000Z', closes_at: '2026-10-15T07:00:00.000Z', effective: '2026-10-15' },
    { timezone: 'Asia/Tokyo', local_date: '2026-10-15', starts_at: '2026-10-14T15:00:00.000Z', due_at: '2026-10-15T00:00:00.000Z', closes_at: '2026-10-15T15:00:00.000Z', effective: '2026-10-16' },
    { timezone: 'Asia/Kathmandu', local_date: '2026-10-15', starts_at: '2026-10-14T18:15:00.000Z', due_at: '2026-10-15T03:15:00.000Z', closes_at: '2026-10-15T18:15:00.000Z', effective: '2026-10-16' }
  ];
  for (const entry of cases) await t.test(entry.timezone, async () => {
    const { database, local, register, tap } = await isolated(new Date('2026-10-15T01:00:00Z'));
    try {
      const user = await register(entry.timezone, `calendar-${entry.timezone}`);
      const today = await local.request('GET', '/me/checkin/today', {}, user.access_token);
      assert.equal(today.local_date, entry.local_date);
      assert.equal(today.starts_at, entry.starts_at);
      assert.equal(today.due_at, entry.due_at);
      assert.equal(today.closes_at, entry.closes_at);
      assert.equal(today.deadline_at, new Date(new Date(entry.due_at).getTime() + 240 * 60000).toISOString());
      assert.equal(today.timezone, entry.timezone);
      assert.equal((await local.request('GET', '/me', {}, user.access_token)).timezone, entry.timezone);
      assert.equal((await tap(user)).status, 'completed');
      const scheduled = await local.request('PUT', '/me/checkin-schedule', { minute: 600, grace: 120 }, user.access_token);
      assert.equal(scheduled.effective_date, entry.effective);
    } finally { await database.close(); }
  });
});

test('DST transition days use PostgreSQL wall-clock conversion', async t => {
  await t.test('spring forward produces a 23-hour day', async () => {
    const { database, local, register } = await isolated(new Date('2026-03-08T12:00:00Z'));
    try {
      const user = await register('America/New_York', 'dst-spring');
      const today = await local.request('GET', '/me/checkin/today', {}, user.access_token);
      assert.equal(today.local_date, '2026-03-08');
      assert.equal(today.starts_at, '2026-03-08T05:00:00.000Z');
      assert.equal(today.due_at, '2026-03-08T13:00:00.000Z');
      assert.equal(today.closes_at, '2026-03-09T04:00:00.000Z');
    } finally { await database.close(); }
  });
  await t.test('fall back produces a 25-hour day', async () => {
    const { database, local, register } = await isolated(new Date('2026-11-01T12:00:00Z'));
    try {
      const user = await register('America/New_York', 'dst-fall');
      const today = await local.request('GET', '/me/checkin/today', {}, user.access_token);
      assert.equal(today.local_date, '2026-11-01');
      assert.equal(today.starts_at, '2026-11-01T04:00:00.000Z');
      assert.equal(today.due_at, '2026-11-01T14:00:00.000Z');
      assert.equal(today.closes_at, '2026-11-02T05:00:00.000Z');
    } finally { await database.close(); }
  });
  await t.test('nonexistent local schedule time resolves to the shifted instant', async () => {
    const { database, local, register, tap, setClock } = await isolated(new Date('2026-03-07T12:00:00Z'));
    try {
      const user = await register('America/New_York', 'dst-gap');
      const scheduled = await local.request('PUT', '/me/checkin-schedule', { minute: 150, grace: 60 }, user.access_token);
      assert.equal(scheduled.effective_date, '2026-03-08');
      setClock(new Date('2026-03-08T12:00:00Z'));
      const session = await local.request('POST', '/auth/refresh', { refresh_token: user.refresh_token });
      const today = await local.request('GET', '/me/checkin/today', {}, session.access_token);
      assert.equal(today.due_at, '2026-03-08T07:30:00.000Z');
      assert.equal(today.deadline_at, '2026-03-08T08:30:00.000Z');
      assert.equal((await local.request('GET', '/me/checkin/today', {}, session.access_token)).id, today.id);
      const first = await tap(session);
      const second = await tap(session);
      assert.equal(second.checkin_id, first.checkin_id);
      assert.equal(second.already_completed, true);
      const counts = await database.transaction(tx => tx.query('SELECT (SELECT count(*) FROM occurrences WHERE user_id=$1) AS occurrences,(SELECT count(*) FROM checkins WHERE actor_id=$1) AS checkins', [user.user_id]));
      assert.equal(Number(counts.rows[0].occurrences), 1);
      assert.equal(Number(counts.rows[0].checkins), 1);
    } finally { await database.close(); }
  });
  await t.test('repeated local schedule time chooses the standard-time occurrence', async () => {
    const { database, local, register, tap, setClock } = await isolated(new Date('2026-10-31T12:00:00Z'));
    try {
      const user = await register('America/New_York', 'dst-repeat');
      const scheduled = await local.request('PUT', '/me/checkin-schedule', { minute: 90, grace: 60 }, user.access_token);
      assert.equal(scheduled.effective_date, '2026-11-01');
      setClock(new Date('2026-11-01T12:00:00Z'));
      const session = await local.request('POST', '/auth/refresh', { refresh_token: user.refresh_token });
      const today = await local.request('GET', '/me/checkin/today', {}, session.access_token);
      assert.equal(today.due_at, '2026-11-01T06:30:00.000Z');
      assert.equal(today.deadline_at, '2026-11-01T07:30:00.000Z');
      assert.equal((await local.request('GET', '/me/checkin/today', {}, session.access_token)).id, today.id);
      const first = await tap(session);
      const second = await tap(session);
      assert.equal(second.checkin_id, first.checkin_id);
      assert.equal(second.already_completed, true);
      const counts = await database.transaction(tx => tx.query('SELECT (SELECT count(*) FROM occurrences WHERE user_id=$1) AS occurrences,(SELECT count(*) FROM checkins WHERE actor_id=$1) AS checkins', [user.user_id]));
      assert.equal(Number(counts.rows[0].occurrences), 1);
      assert.equal(Number(counts.rows[0].checkins), 1);
    } finally { await database.close(); }
  });
});

test('refresh response replays only for the original request id', async () => {
  const user = await account();
  const key = randomUUID();
  const rotated = await service.request('POST', '/auth/refresh', { refresh_token: user.refresh_token }, '', key);
  assert.ok(await service.request('GET', '/me', {}, rotated.access_token));
  const [first, second] = await Promise.all([
    service.request('POST', '/auth/refresh', { refresh_token: user.refresh_token }, '', key),
    service.request('POST', '/auth/refresh', { refresh_token: user.refresh_token }, '', key)
  ]);
  assert.deepEqual(first, rotated);
  assert.deepEqual(second, rotated);
  const stored = await db.transaction(tx => tx.query('SELECT refresh_response_encrypted FROM sessions WHERE user_id=$1 AND refresh_response_encrypted IS NOT NULL', [user.user_id]));
  assert.equal(stored.rows.length, 1);
  assert.equal(stored.rows[0].refresh_response_encrypted.includes(rotated.access_token), false);
  assert.equal(stored.rows[0].refresh_response_encrypted.includes(rotated.refresh_token), false);
  assert.equal(stored.rows[0].refresh_response_encrypted.includes(user.refresh_token), false);
  await rejects(service.request('POST', '/auth/refresh', { refresh_token: user.refresh_token }, '', randomUUID()), 'session_reused');
  await rejects(service.request('GET', '/me', {}, rotated.access_token), 'unauthorized');
});

test('replay window expiry, logout and tick cleanup retire the stored refresh copy', async () => {
  const expired = await account();
  const expiredKey = randomUUID();
  const rotated = await service.request('POST', '/auth/refresh', { refresh_token: expired.refresh_token }, '', expiredKey);
  clock = new Date(clock.getTime() + 61000);
  await rejects(service.request('POST', '/auth/refresh', { refresh_token: expired.refresh_token }, '', expiredKey), 'session_reused');
  await rejects(service.request('GET', '/me', {}, rotated.access_token), 'unauthorized');

  const logout = await account();
  const logoutKey = randomUUID();
  const logged = await service.request('POST', '/auth/refresh', { refresh_token: logout.refresh_token }, '', logoutKey);
  await service.request('POST', '/auth/logout', {}, logged.access_token);
  await rejects(service.request('POST', '/auth/refresh', { refresh_token: logout.refresh_token }, '', logoutKey), 'session_reused');

  const cleaned = await account();
  const cleanKey = randomUUID();
  await service.request('POST', '/auth/refresh', { refresh_token: cleaned.refresh_token }, '', cleanKey);
  clock = new Date(clock.getTime() + 61000);
  await service.tick();
  const rows = await db.transaction(tx => tx.query('SELECT refresh_request_hash,refresh_response_encrypted,refresh_replay_until FROM sessions WHERE user_id=$1', [cleaned.user_id]));
  assert.ok(rows.rows.length > 0);
  for (const row of rows.rows) {
    assert.equal(row.refresh_request_hash, null);
    assert.equal(row.refresh_response_encrypted, null);
    assert.equal(row.refresh_replay_until, null);
  }
});
