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
    assert.equal((await service.request('GET', '/me', {}, access)).timezone, 'Europe/Istanbul');
    assert.equal((await service.request('GET', '/me/relationships', {}, access)).items.length, 1);
    assert.equal((await service.request('GET', `/profiles/${owner}/checkins`, {}, access)).items.length, 1);
    const migrated = await db.transaction(tx => tx.query('SELECT timezone,starts_at FROM occurrences WHERE id=$1', [occurrence]));
    assert.equal(migrated.rows[0].timezone, 'Europe/Istanbul');
    assert.equal(new Date(migrated.rows[0].starts_at).toISOString(), '2026-09-19T21:00:00.000Z');
    const fresh = await service.request('POST', '/auth/device', { name: 'Ayşe', enabled: true, device_name: 'New device', registration_secret: randomBytes(32).toString('base64url') });
    assert.notEqual(fresh.user_id, owner);
    const legacy = await db.transaction(tx => tx.query('SELECT phone_hash,phone_encrypted FROM users WHERE id=$1', [owner]));
    assert.equal(legacy.rows[0].phone_hash, `legacy-${owner}`);
    assert.equal(legacy.rows[0].phone_encrypted, 'legacy-ciphertext-fixture');
    // v7: mevcut hesaplar için kurtarma kapalı ve sürüm 0 kalır; yeni tablo boştur.
    const recovery = await db.transaction(tx => tx.query('SELECT recovery_key_hash,recovery_key_version,recovery_key_set_at FROM users WHERE id=$1', [owner]));
    assert.equal(recovery.rows[0].recovery_key_hash, null);
    assert.equal(recovery.rows[0].recovery_key_version, 0);
    assert.equal(recovery.rows[0].recovery_key_set_at, null);
    assert.equal((await db.transaction(tx => tx.query('SELECT 1 FROM account_recoveries'))).rows.length, 0);
    assert.deepEqual((await db.transaction(tx => tx.query('SELECT version FROM schema_migrations ORDER BY version'))).rows.map(row => row.version), [1, 2, 3, 4, 5, 6, 7]);
  } finally { await db.close(); }
});
