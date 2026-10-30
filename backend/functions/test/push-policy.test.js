import {test} from 'node:test';
import assert from 'node:assert/strict';
import {authenticatedUID, installation, tokenID, eligibleDevice, messageFor, expiredToken, MAX_TOKEN_AGE_MS} from '../push-policy.js';
const installationID = 'f1b4885a-87df-4b84-ab09-7c9708c65282';
const token = 'placeholder-fcm-registration-token-only-for-unit-tests';
const now = 1800000000000;
const device = {uid:'owner-a', installationID, token, enabled:true, updatedAtMs:now};

test('authentication takes identity from verified context, never from client data', () => {
  assert.equal(authenticatedUID({auth:{uid:'owner-a'},data:{uid:'owner-b'}}),'owner-a');
  for (const request of [{}, {auth:{}}, {auth:{uid:''}}]) assert.throws(()=>authenticatedUID(request),{code:'unauthenticated'});
});
test('registration rejects owner overrides, malformed IDs and unsafe tokens', () => {
  assert.deepEqual(installation({installationID:installationID.toUpperCase(),token},true),{installationID,token});
  for (const data of [null, [], {}, {installationID:'bad',token}, {installationID,token,uid:'owner-b'}, {installationID,token:'short'}, {installationID,token:'invalid token with whitespace'}]) {
    assert.throws(()=>installation(data,true),{code:'invalid-argument'});
  }
});
test('a token has one stable opaque storage key', () => {
  assert.equal(tokenID(token),tokenID(token)); assert.equal(tokenID(token).length,64); assert.notEqual(tokenID(token),tokenID(token+'2'));
  assert.ok(!tokenID(token).includes(token));
});
test('delivery excludes other accounts, opt-outs, stale and invalid timestamps', () => {
  assert.equal(eligibleDevice(device,'owner-a',now),true);
  assert.equal(eligibleDevice(device,'owner-b',now),false);
  for (const updated of [{enabled:false},{updatedAtMs:now-MAX_TOKEN_AGE_MS},{updatedAtMs:NaN},{updatedAtMs:now+400000}]) assert.equal(eligibleDevice({...device,...updated},'owner-a',now),false);
});
test('push payload contains generic text and typed routing, never health or journal content', () => {
  const message=messageFor({...device,symptoms:'private note',pm25:90,coordinates:[1,2]},'journal_updated',now);
  assert.deepEqual(message.data,{kind:'journal_updated',recipientUID:'owner-a',installationID,version:'1'});
  const json=JSON.stringify(message); for(const privateField of ['private note','symptoms','pm25','coordinates']) assert.ok(!json.includes(privateField));
  assert.equal(message.apns.headers['apns-push-type'],'alert');
  assert.equal(Number(message.apns.headers['apns-expiration']),now/1000+300);
  assert.throws(()=>messageFor(device,'arbitrary'),{code:'invalid-argument'});
});
test('only explicit invalid-token failures revoke a registration', () => {
  assert.equal(expiredToken({code:'messaging/registration-token-not-registered'}),true);
  for(const code of ['messaging/invalid-argument','messaging/server-unavailable','messaging/third-party-auth-error']) assert.equal(expiredToken({code}),false);
});
