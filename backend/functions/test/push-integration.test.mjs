import {test, after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {tokenID} from '../push-policy.js';

if (process.env.GCLOUD_PROJECT !== 'demo-breatheroute' || !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Push integration checks require the isolated demo-breatheroute emulators.');
}
const app=initializeApp({projectId:'demo-breatheroute'},'push-tests');
const db=getFirestore(app);
after(async()=>{await db.terminate();await deleteApp(app);});
async function user() {
  const response=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator-key',{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({returnSecureToken:true})});
  assert.equal(response.status,200); const result=await response.json();return {uid:result.localId,idToken:result.idToken};
}
async function call(name, data, identity) {
  const response=await fetch(`http://127.0.0.1:5001/demo-breatheroute/asia-south1/${name}`,{
    method:'POST',headers:{'Content-Type':'application/json',...(identity?{Authorization:`Bearer ${identity.idToken}`}:{})},body:JSON.stringify({data})});
  const body=await response.json();return {status:response.status,body};
}
const value = response => response.body.result ?? response.body.data;

test('authenticated HTTP registration, rotation, cross-account isolation, revoke and journal trigger', async()=>{
  const a=await user(), b=await user(); const aID=crypto.randomUUID(), bID=crypto.randomUUID();
  const token1='emulator-placeholder-fcm-token-one', token2='emulator-placeholder-fcm-token-two';
  let response=await call('registerPushDevice',{installationID:aID,token:token1});
  assert.equal(response.status,401,'anonymous registration denied');
  response=await call('registerPushDevice',{installationID:aID,token:token1,uid:b.uid},a);
  assert.equal(response.status,400,'a client cannot select another owner');
  response=await call('registerPushDevice',{installationID:aID,token:token1},a);
  assert.equal(value(response)?.registered,true);
  assert.equal((await db.doc(`pushDevices/${tokenID(token1)}`).get()).data().uid,a.uid);
  response=await call('sendPushConnectionTest',{installationID:aID},b);
  assert.equal(response.status,400,'another account cannot target the device');
  response=await call('sendPushConnectionTest',{installationID:aID},a);
  assert.equal(value(response)?.accepted,true,'mock delivery accepted');
  let deliveries=await db.collection('_pushTestDeliveries').get();
  assert.equal(deliveries.size,1);assert.equal(deliveries.docs[0].data().message.data.recipientUID,a.uid);
  assert.equal(deliveries.docs[0].data().message.data.kind,'connection_test');
  response=await call('sendPushConnectionTest',{installationID:aID},a);
  assert.equal(response.status,429,'connection tests are rate limited');
  response=await call('registerPushDevice',{installationID:aID,token:token2},a);
  assert.equal(value(response)?.registered,true);
  assert.equal((await db.doc(`pushDevices/${tokenID(token1)}`).get()).exists,false,'rotated token removed');
  response=await call('registerPushDevice',{installationID:bID,token:token2},b);
  assert.equal(value(response)?.registered,true);
  assert.equal((await db.doc(`pushDevices/${tokenID(token2)}`).get()).data().uid,b.uid,'token has only its current owner');
  response=await call('unregisterPushDevice',{installationID:aID},a);
  assert.equal(value(response)?.removed,true);
  assert.equal((await db.doc(`pushDevices/${tokenID(token2)}`).get()).data().uid,b.uid,'old owner cannot revoke the new owner');
  for(let i=0;i<2;i++) assert.equal(value(await call('unregisterPushDevice',{installationID:bID},b))?.removed,true);
  assert.equal((await db.doc(`pushDevices/${tokenID(token2)}`).get()).exists,false,'revocation is idempotent');
  const token3='emulator-placeholder-fcm-token-journal';
  assert.equal(value(await call('registerPushDevice',{installationID:aID,token:token3},a))?.registered,true);
  await db.doc(`users/${a.uid}/journal/current`).set({schemaVersion:2,revision:crypto.randomUUID(),payload:'PRIVATE_TEST_NOTE_NOT_FOR_PUSH'});
  let received;
  for(let i=0;i<60;i++) {
    const snapshot=await db.collection('_pushTestDeliveries').get();
    received=snapshot.docs.map(d=>d.data().message).find(m=>m.data.kind==='journal_updated'&&m.data.recipientUID===a.uid);
    if(received)break;
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  assert.ok(received,'journal write triggers a server notification');
  assert.ok(!JSON.stringify(received).includes('PRIVATE_TEST_NOTE_NOT_FOR_PUSH'),'private content never enters push payload');
  await call('unregisterPushDevice',{installationID:aID},a);
});

test('active-device limit and stale token rotation keep registrations bounded', async()=>{
  const identity=await user(), now=Date.now(), seeded=[];
  const batch=db.batch();
  for(let i=0;i<20;i++) {
    const token=`emulator-device-limit-placeholder-${i}`, installationID=crypto.randomUUID();
    const reference=db.doc(`pushDevices/${tokenID(token)}`);
    batch.set(reference,{schemaVersion:1,uid:identity.uid,installationID,token,enabled:true,updatedAtMs:now});
    seeded.push({reference,installationID});
  }
  await batch.commit();
  const next={installationID:crypto.randomUUID(),token:'emulator-device-limit-new-token'};
  assert.equal((await call('registerPushDevice',next,identity)).status,429,'twenty active installations is the limit');
  await seeded[0].reference.update({updatedAtMs:now-31*86400_000});
  assert.equal(value(await call('registerPushDevice',next,identity))?.registered,true,'an expired installation frees a slot');
  assert.equal((await seeded[0].reference.get()).exists,false,'stale mapping pruned');
  await seeded[1].reference.update({updatedAtMs:now-31*86400_000});
  assert.equal(value(await call('registerPushDevice',{installationID:seeded[1].installationID,token:'emulator-stale-rotated-new-token'},identity))?.registered,true);
  assert.equal((await seeded[1].reference.get()).exists,false,'a stale previous token rotates without duplicate deletes');
  assert.equal((await db.collection('pushDevices').where('uid','==',identity.uid).get()).size,20);
});
