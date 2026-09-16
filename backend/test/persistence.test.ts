import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import { Database } from '../src/database';
import { Service } from '../src/service';

test('restart preserves committed check-in and pending notification, deletion stays deleted', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'yolunda-persistence-'));
  const options = { mode: 'test' as const, encryptionKey: Buffer.alloc(32, 2), lookupKey: 'persistence-test' };
  let db = new Database(undefined, join(directory, 'database'));
  try {
    await db.initialize();
    let service = new Service(db, options);
    const auth = await service.request('POST', '/auth/device', { name: 'Test', enabled: true, device_name: 'Persistence test', registration_secret: randomBytes(32).toString('base64url') });
    const viewer = await service.request('POST', '/auth/device', { name: 'Viewer', enabled: false, device_name: 'Persistence viewer', registration_secret: randomBytes(32).toString('base64url') });
    const invite = await service.request('POST', '/invitations', { direction: 'request_theirs', label: 'Yakınım' }, viewer.access_token);
    await service.request('POST', `/invitations/${invite.id}/accept`, { token: invite.token }, auth.access_token);
    const today = await service.request('GET', '/me/checkin/today', {}, auth.access_token);
    const request = { occurrence_id: today.id, source: 'app', client_action_at: new Date().toISOString() };
    const key = randomUUID();
    const receipt = await service.request('POST', '/me/checkins', request, auth.access_token, key);
    await db.close();
    db = new Database(undefined, join(directory, 'database'));
    await db.initialize();
    service = new Service(db, options);
    const recovered = await service.request('POST', '/me/checkins', request, auth.access_token, key);
    assert.equal(recovered.checkin_id, receipt.checkin_id);
    assert.equal((await service.request('GET', '/me/checkin/today', {}, auth.access_token)).state, 'completed');
    const notices = await service.request('GET', '/me/notifications', {}, viewer.access_token);
    assert.equal(notices.items.length, 1);
    assert.equal(notices.items[0].status, 'queued');
    await service.request('DELETE', '/me', { confirmation: 'HESABIMI SİL' }, auth.access_token);
    await db.close();
    db = new Database(undefined, join(directory, 'database'));
    await db.initialize();
    service = new Service(db, options);
    await assert.rejects(service.request('GET', '/me', {}, auth.access_token));
  } finally {
    await db.close();
    await rm(directory, { recursive: true, force: true });
  }
});
