import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { Database } from '../src/database';
import { APIError, Service } from '../src/service';

let db: Database;
let service: Service;
let now = new Date('2026-09-20T05:00:00Z');
const input = (name = 'Ayşe') => ({ name, enabled: true, device_name: 'Account test', registration_secret: randomBytes(32).toString('base64url') });
const rejects = (work: Promise<unknown>, code: string) => assert.rejects(work, (error: any) => error instanceof APIError && error.code === code);
before(async () => {
  db = new Database();
  await db.initialize();
  service = new Service(db, { mode: 'production', encryptionKey: Buffer.alloc(32, 8), lookupKey: 'account-tests', clock: () => now });
});
after(async () => { await db.close(); });

test('same display name creates independent accounts without telephone data', async () => {
  const first = await service.request('POST', '/auth/device', input());
  const second = await service.request('POST', '/auth/device', input());
  assert.notEqual(first.user_id, second.user_id);
  assert.notEqual(first.access_token, second.access_token);
  const profile = await service.request('GET', '/me', {}, first.access_token);
  assert.equal(profile.name, 'Ayşe');
  await rejects(service.request('GET', '/me', {}, first.user_id), 'unauthorized');
  await rejects(service.request('GET', `/profiles/${first.user_id}/status`, {}, second.access_token), 'not_found');
  const users = await db.transaction(tx => tx.query('SELECT phone_hash,phone_encrypted FROM users WHERE id=$1', [first.user_id]));
  assert.equal(users.rows[0].phone_hash, null);
  assert.equal(users.rows[0].phone_encrypted, null);
});
test('registration retry preserves account, rotates response tokens and rejects changed payload', async () => {
  const request = input('Mehmet');
  const first = await service.request('POST', '/auth/device', request);
  const repeated = await service.request('POST', '/auth/device', request);
  assert.equal(repeated.user_id, first.user_id);
  await rejects(service.request('GET', '/me', {}, first.access_token), 'unauthorized');
  assert.ok(await service.request('GET', '/me', {}, repeated.access_token));
  await rejects(service.request('POST', '/auth/device', { ...request, name: 'Başka kişi' }), 'registration_conflict');
});
test('registration secret is not a permanent recovery method and logout invalidates it', async () => {
  const request = input('Hasan');
  const user = await service.request('POST', '/auth/device', request);
  await service.request('POST', '/auth/logout', {}, user.access_token);
  await rejects(service.request('POST', '/auth/device', request), 'registration_expired');
  const expiring = input('Elif');
  await service.request('POST', '/auth/device', expiring);
  now = new Date(now.getTime() + 11 * 60000);
  await rejects(service.request('POST', '/auth/device', expiring), 'registration_expired');
});
test('revoking a device session also prevents bootstrap credential reuse', async () => {
  const request = input('Revoked device');
  const user = await service.request('POST', '/auth/device', request, '', '', 'revocation');
  const sessions = await service.request('GET', '/me/sessions', {}, user.access_token);
  await service.request('DELETE', `/me/sessions/${sessions.items[0].id}`, {}, user.access_token);
  await rejects(service.request('POST', '/auth/device', request), 'registration_expired');
});
test('phone OTP endpoints are retired even outside production', async () => {
  const local = new Service(db, { mode: 'test', encryptionKey: Buffer.alloc(32, 8), lookupKey: 'account-tests' });
  await rejects(local.request('POST', '/auth/otp/start', { phone: '+905000000000' }), 'auth_method_removed');
  await rejects(local.request('POST', '/auth/otp/verify', { code: '123456' }), 'auth_method_removed');
});
test('name is not enough for login and registration input is strictly validated', async () => {
  await assert.rejects(service.request('POST', '/auth/device', { name: 'Ayşe' }));
  await assert.rejects(service.request('POST', '/auth/device', { ...input(), name: '  ' }));
  await assert.rejects(service.request('POST', '/auth/device', { ...input(), user_id: 'chosen-id' }));
});
test('registration abuse is rate limited per network without collecting phone numbers', async () => {
  for (let index = 0; index < 10; index++) await service.request('POST', '/auth/device', input(), '', '', 'limit-test');
  await rejects(service.request('POST', '/auth/device', input(), '', '', 'limit-test'), 'rate_limited');
});
test('short invitation code is time-limited and never grants access without owner approval', async () => {
  const owner = await service.request('POST', '/auth/device', input('Owner'), '', '', 'circle');
  const viewer = await service.request('POST', '/auth/device', input('Viewer'), '', '', 'circle');
  const invite = await service.request('POST', '/invitations', { direction: 'share_mine', label: 'Yakınım' }, owner.access_token);
  assert.match(invite.code, /^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  const preview = await service.request('POST', '/invitations/preview', { code: invite.code.toLowerCase() }, viewer.access_token);
  assert.equal(preview.id, invite.id);
  await service.request('POST', `/invitations/${invite.id}/accept`, { code: invite.code }, viewer.access_token);
  await rejects(service.request('GET', `/profiles/${owner.user_id}/status`, {}, viewer.access_token), 'not_found');
  await service.request('POST', `/invitations/${invite.id}/approve-sharing`, {}, owner.access_token);
  assert.ok(await service.request('GET', `/profiles/${owner.user_id}/status`, {}, viewer.access_token));
  await rejects(service.request('POST', '/invitations/preview', { code: invite.code }, viewer.access_token), 'invalid_invitation');
  const expired = await service.request('POST', '/invitations', { direction: 'share_mine', label: 'Yakınım' }, owner.access_token);
  now = new Date(now.getTime() + 49 * 3600000);
  const refreshed = await service.request('POST', '/auth/refresh', { refresh_token: viewer.refresh_token });
  await rejects(service.request('POST', '/invitations/preview', { code: expired.code }, refreshed.access_token), 'invalid_invitation');
});
test('invalid invitation guesses consume the rate limit even when lookup fails', async () => {
  const viewer = await service.request('POST', '/auth/device', input('Guesser'), '', '', 'guesser');
  for (let attempt = 0; attempt < 20; attempt++) await rejects(service.request('POST', '/invitations/preview', { code: 'AAAA-BBBB-CCCC' }, viewer.access_token, '', 'guess-network'), 'invalid_invitation');
  await rejects(service.request('POST', '/invitations/preview', { code: 'AAAA-BBBB-CCCC' }, viewer.access_token, '', 'guess-network'), 'rate_limited');
});
