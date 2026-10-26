// Local Firebase Auth Emulator only. Never accepts a production host or real credentials.
import assert from 'node:assert/strict';

const base = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/';
const nonce = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
const password = 'Local-emulator-example-42!';
async function call(action, body) {
  const response = await fetch(`${base}${action}?key=demo-api-key`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body)
  });
  return { status: response.status, body: await response.json() };
}
const aliceEmail = `alice-${nonce}@example.test`, bobEmail = `bob-${nonce}@example.test`;
const alice = await call('accounts:signUp', { email: aliceEmail, password, returnSecureToken: true });
const bob = await call('accounts:signUp', { email: bobEmail, password, returnSecureToken: true });
assert.equal(alice.status, 200); assert.equal(bob.status, 200);
assert.notEqual(alice.body.localId, bob.body.localId);
const signIn = await call('accounts:signInWithPassword', { email: aliceEmail, password, returnSecureToken: true });
assert.equal(signIn.status, 200); assert.equal(signIn.body.localId, alice.body.localId);
const wrong = await call('accounts:signInWithPassword', { email: aliceEmail, password: 'Incorrect-local-example!', returnSecureToken: true });
assert.equal(wrong.status, 400);
const reset = await call('accounts:sendOobCode', { email: aliceEmail, requestType: 'PASSWORD_RESET' });
assert.equal(reset.status, 200);
console.log('Auth emulator: two distinct accounts, sign-in identity, wrong-password rejection and reset request passed. No cloud requests made.');
