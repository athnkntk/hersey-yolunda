import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { Database } from '../src/database';
import { Service } from '../src/service';

test('100 concurrent requests and deadline worker leave one declaration and no queued stale alert', async () => {
  const db = new Database();
  const now = new Date('2026-09-15T10:00:00Z');
  try {
    await db.initialize();
    const service = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 3), lookupKey: 'concurrency', clock: () => now });
    async function login(name: string) {
      return service.request('POST', '/auth/device', { name, enabled: true, device_name: 'Concurrency test', registration_secret: randomBytes(32).toString('base64url') });
    }
    const user = await login('Subject'), viewer = await login('Viewer');
    await service.request('PATCH', '/me/profile', { name: 'Synthetic' }, user.access_token);
    const invite = await service.request('POST', '/invitations', { direction: 'request_theirs', label: 'Yakınım' }, viewer.access_token);
    await service.request('POST', `/invitations/${invite.id}/accept`, { token: invite.token }, user.access_token);
    await db.transaction(tx => tx.query('UPDATE users SET created_at=$1,activated_at=$1 WHERE id=$2', [new Date(now.getTime() - 5 * 3600000), user.user_id]));
    const today = await service.request('GET', '/me/checkin/today', {}, user.access_token);
    assert.equal(today.reminders_enabled, true);
    const elapsed: number[] = [];
    const checkins = Array.from({ length: 100 }, (_, index) => async () => {
      const start = performance.now();
      const value = await service.request('POST', '/me/checkins', { occurrence_id: today.id, source: index % 2 ? 'app' : 'ios_widget', client_action_at: now.toISOString() }, user.access_token, randomUUID());
      elapsed.push(performance.now() - start);
      return value;
    });
    const [_, ...results] = await Promise.all([service.tick(), ...checkins.map(run => run())]);
    assert.equal(new Set(results.map(value => value.checkin_id)).size, 1);
    assert.equal(results.filter(value => !value.already_completed).length, 1);
    const notices = await service.request('GET', '/me/notifications', {}, viewer.access_token);
    assert.deepEqual(notices.items.map((row: any) => row.type), ['completed']);
    const final = await service.request('GET', '/me/checkin/today', {}, user.access_token);
    assert.equal(final.state, 'completed');
    elapsed.sort((a, b) => a - b);
    console.log(`Local PGlite concurrency sample: requests=100 p95_ms=${Math.round(elapsed[94])}; not a production SLO`);
  } finally { await db.close(); }
});
