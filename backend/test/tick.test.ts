import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { Database } from '../src/database';
import { APIError, Service } from '../src/service';

test('external tick endpoint requires a configured secret and rejects wrong ones', async () => {
  const db = new Database();
  try {
    await db.initialize();
    const secret = randomBytes(32).toString('base64url');
    const service = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 4), lookupKey: 'tick-test', tickSecret: secret });
    await assert.rejects(service.request('POST', '/tick', { secret: 'wrong-secret-value-1234567890' }), (error: any) => error instanceof APIError && error.code === 'invalid_secret');
    const result = await service.request('POST', '/tick', { secret });
    assert.equal(result.ok, true);
    const closed = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 4), lookupKey: 'tick-test' });
    await assert.rejects(closed.request('POST', '/tick', { secret }), (error: any) => error instanceof APIError && error.code === 'not_found');
  } finally { await db.close(); }
});

test('external tick dispatches the push worker after scheduling', async () => {
  const db = new Database();
  try {
    await db.initialize();
    const secret = randomBytes(32).toString('base64url');
    let runs = 0;
    const service = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 5), lookupKey: 'tick-worker', tickSecret: secret, pushWorker: { run: async () => { runs++; } } });
    const result = await service.request('POST', '/tick', { secret });
    assert.equal(result.ok, true);
    assert.equal(runs, 1);
  } finally { await db.close(); }
});
