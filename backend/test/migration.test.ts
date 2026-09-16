import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { Database } from '../src/database';
import { Service } from '../src/service';

test('v5 migration preserves legacy telephone account, session, relationship and check-in', async () => {
  const db = new Database();
  try {
    await db.initialize(4);
    const owner = randomUUID(), viewer = randomUUID(), occurrence = randomUUID();
    const access = randomBytes(32).toString('base64url');
    const hash = (text: string) => createHash('sha256').update(text).digest('hex');
    const now = new Date('2026-09-20T06:00:00Z');
    await db.transaction(async tx => {
      for (const user of [owner, viewer]) await tx.query('INSERT INTO users(id,phone_hash,phone_encrypted,name,created_at) VALUES($1,$2,$3,$4,$5)', [user, `legacy-${user}`, 'legacy-ciphertext-fixture', 'Ayşe', now]);
      await tx.query('INSERT INTO sessions(id,user_id,access_hash,refresh_hash,family_id,device_name,access_expires,refresh_expires) VALUES($1,$2,$3,$4,$5,$6,$7,$8)', [randomUUID(), owner, hash(access), hash('legacy-refresh'), randomUUID(), 'Legacy device', new Date(now.getTime() + 900000), new Date(now.getTime() + 86400000)]);
      await tx.query('INSERT INTO relationships VALUES($1,$2,$3,$4,true,$5)', [randomUUID(), owner, viewer, 'Yakınım', now]);
      await tx.query('INSERT INTO occurrences(id,user_id,local_date,due_at,deadline_at,closes_at,state,completed_at) VALUES($1,$2,$3,$4,$5,$6,$7,$4)', [occurrence, owner, '2026-09-20', now, new Date('2026-09-20T10:00:00Z'), new Date('2026-09-20T21:00:00Z'), 'completed']);
      await tx.query('INSERT INTO checkins VALUES($1,$2,$3,$4,$5)', [randomUUID(), occurrence, owner, 'app', now]);
    });
    await db.initialize();
    const service = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 9), lookupKey: 'migration', clock: () => now });
    assert.equal((await service.request('GET', '/me', {}, access)).id, owner);
    assert.equal((await service.request('GET', '/me/relationships', {}, access)).items.length, 1);
    assert.equal((await service.request('GET', `/profiles/${owner}/checkins`, {}, access)).items.length, 1);
    const fresh = await service.request('POST', '/auth/device', { name: 'Ayşe', enabled: true, device_name: 'New device', registration_secret: randomBytes(32).toString('base64url') });
    assert.notEqual(fresh.user_id, owner);
    const legacy = await db.transaction(tx => tx.query('SELECT phone_hash,phone_encrypted FROM users WHERE id=$1', [owner]));
    assert.equal(legacy.rows[0].phone_hash, `legacy-${owner}`);
    assert.equal(legacy.rows[0].phone_encrypted, 'legacy-ciphertext-fixture');
  } finally { await db.close(); }
});
