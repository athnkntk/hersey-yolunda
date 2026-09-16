import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';

const base = process.env.HY_TEST_API_URL ?? 'http://127.0.0.1:3000/v1';
const expectedMode = /^https:\/\//.test(base) ? 'production' : 'development';
async function call(method: string, path: string, body?: any, token?: string, key?: string) {
  const response = await fetch(base + path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...(key ? { 'Idempotency-Key': key } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: response.status, data: await response.json() as any, cache: response.headers.get('cache-control') };
}
async function login() {
  const auth = await call('POST', '/auth/device', { name: 'HTTP test', enabled: true, device_name: 'HTTP integration synthetic', registration_secret: randomBytes(32).toString('base64url') });
  assert.equal(auth.status, 200);
  return auth.data;
}

test('HTTP contract: auth, validation, profile, invite, check-in, revocation and deletion', async () => {
  const health = await call('GET', '/health');
  assert.equal(health.data.mode, expectedMode);
  assert.equal(health.cache, 'no-store');
  assert.equal((await call('GET', '/me')).status, 401);
  assert.equal((await call('POST', '/auth/device', { name: '' })).status, 400);
  assert.equal((await call('POST', '/auth/otp/start', { phone: 'unused' })).status, 410);
  const subject = await login(), viewer = await login();
  try {
    const profile = await call('PATCH', '/me/profile', { name: 'HTTP Test' }, subject.access_token);
    assert.equal(profile.data.name, 'HTTP Test');
    const invitation = await call('POST', '/invitations', { direction: 'request_theirs', label: 'Yakınım' }, viewer.access_token);
    assert.equal(invitation.status, 200);
    assert.equal((await call('POST', `/invitations/${invitation.data.id}/accept`, { token: invitation.data.token }, subject.access_token)).status, 200);
    const today = await call('GET', '/me/checkin/today', undefined, subject.access_token);
    const input = { occurrence_id: today.data.id, source: 'app', client_action_at: new Date().toISOString() };
    const key = randomUUID();
    const receipt = await call('POST', '/me/checkins', input, subject.access_token, key);
    assert.equal(receipt.status, 200);
    assert.equal(receipt.data.status, 'completed');
    assert.deepEqual((await call('POST', '/me/checkins', input, subject.access_token, key)).data, receipt.data);
    const family = await call('GET', '/me/relatives', undefined, viewer.access_token);
    assert.equal(family.data.items[0].today.state, 'completed');
    const notifications = await call('GET', '/me/notifications', undefined, viewer.access_token);
    assert.equal(notifications.data.items.length, 1);
    const relations = await call('GET', '/me/relationships', undefined, subject.access_token);
    await call('DELETE', `/me/relationships/${relations.data.items[0].id}`, undefined, subject.access_token);
    assert.equal((await call('GET', `/profiles/${subject.user_id}/status`, undefined, viewer.access_token)).status, 404);
  } finally {
    for (const session of [subject, viewer]) assert.equal((await call('DELETE', '/me', { confirmation: 'HESABIMI SİL' }, session.access_token)).status, 200);
  }
});
