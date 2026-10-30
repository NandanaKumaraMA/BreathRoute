import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getMessaging} from 'firebase-admin/messaging';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {setGlobalOptions} from 'firebase-functions/v2';
import {authenticatedUID, installation, tokenID, eligibleDevice, messageFor, expiredToken, PushError, REGION, MAX_TOKEN_AGE_MS} from './push-policy.js';

initializeApp();
setGlobalOptions({region: REGION, maxInstances: 2, memory: '256MiB', timeoutSeconds: 30});
const db = getFirestore();
const devices = db.collection('pushDevices'); // Admin only. Client SDK access is denied by Firestore rules.
const limits = db.collection('pushDeliveryState');
async function callable(action, request) {
  try { return await action(request); }
  catch (error) {
    if (error instanceof PushError) throw new HttpsError(error.code, error.message);
    if (error instanceof HttpsError) throw error;
    // Never reflect tokens, private records or provider error payloads to clients/logs.
    throw new HttpsError('unavailable', 'Cloud alerts could not connect. Please try again.');
  }
}
export const registerPushDevice = onCall(request => callable(async request => {
  const uid = authenticatedUID(request), device = installation(request.data, true), now = Date.now();
  const key = tokenID(device.token), reference = devices.doc(key);
  await db.runTransaction(async transaction => {
    const owned = await transaction.get(devices.where('uid', '==', uid));
    const otherActive = owned.docs.filter(item => item.id !== key && item.data().installationID !== device.installationID && eligibleDevice(item.data(), uid, now));
    if (otherActive.length >= 20) throw new PushError('resource-exhausted', 'Too many devices are connected to this account.');
    for (const old of owned.docs) {
      if (old.id !== key && (old.data().installationID === device.installationID || now - old.data().updatedAtMs >= MAX_TOKEN_AGE_MS)) transaction.delete(old.ref);
    }
    // A token has exactly one owner, including when the same installation changes accounts.
    transaction.set(reference, {schemaVersion: 1, uid, ...device, enabled: true, updatedAtMs: now});
  });
  return {registered: true};
}, request));

export const unregisterPushDevice = onCall(request => callable(async request => {
  const uid = authenticatedUID(request), {installationID} = installation(request.data);
  await db.runTransaction(async transaction => {
    const matches = await transaction.get(devices.where('uid', '==', uid).where('installationID', '==', installationID));
    for (const device of matches.docs) transaction.delete(device.ref);
  });
  return {removed: true};
}, request));

async function send(deviceDocument, kind) {
  const device = deviceDocument.data();
  try {
    const message = messageFor(device, kind);
    if (process.env.FUNCTIONS_EMULATOR === 'true' && process.env.GCLOUD_PROJECT === 'demo-breatheroute' && process.env.BREATHE_PUSH_TEST_TRANSPORT === 'true') {
      // Explicit emulator transport only. No FCM call or real device delivery occurs.
      await db.collection('_pushTestDeliveries').add({message, requestedAtMs: Date.now()});
    } else { await getMessaging().send(message); }
    return true;
  } catch (error) {
    if (expiredToken(error)) {
      // Do not delete a token that was reassigned to another account while this request was in flight.
      await db.runTransaction(async transaction => {
        const current = await transaction.get(deviceDocument.ref);
        if (current.data()?.uid === device.uid && current.data()?.updatedAtMs === device.updatedAtMs) transaction.delete(deviceDocument.ref);
      });
    }
    return false;
  }
}
async function lease(key, field, intervalMs, eventID = undefined) {
  return db.runTransaction(async transaction => {
    const ref = limits.doc(key), snapshot = await transaction.get(ref), data = snapshot.data() ?? {}, now = Date.now();
    if ((eventID && data.eventID === eventID) || (data[field] && now - data[field] < intervalMs)) return false;
    transaction.set(ref, {[field]: now, ...(eventID ? {eventID} : {})}, {merge: true}); return true;
  });
}
export const sendPushConnectionTest = onCall(request => callable(async request => {
  const uid = authenticatedUID(request), {installationID} = installation(request.data), now = Date.now();
  const matches = await devices.where('uid', '==', uid).where('installationID', '==', installationID).get();
  const active = matches.docs.filter(device => eligibleDevice(device.data(), uid, now));
  if (!active.length) throw new PushError('failed-precondition', 'Enable cloud alerts on this device first.');
  if (!await lease(tokenID(uid + ':' + installationID), 'testAtMs', 60_000)) throw new PushError('resource-exhausted', 'Wait a minute before sending another test.');
  const sent = await send(active[0], 'connection_test');
  if (!sent) throw new PushError('unavailable', 'Delivery could not be requested. Check the cloud notification setup.');
  return {accepted: true}; // Acceptance by FCM is not proof of device delivery.
}, request));

export const notifyJournalUpdated = onDocumentWritten('users/{uid}/journal/current', async event => {
  if (!event.data?.after.exists) return;
  const after = event.data.after.data(), before = event.data.before.data();
  if (!after?.revision || after.revision === before?.revision) return;
  const uid = event.params.uid, snapshot = await devices.where('uid', '==', uid).get(), now = Date.now();
  const active = snapshot.docs.filter(device => eligibleDevice(device.data(), uid, now)).slice(0, 20);
  if (!active.length || !await lease(tokenID(uid), 'journalAtMs', 300_000, event.id)) return;
  // Only a generic update is sent. The private journal payload is never read or included.
  await Promise.all(active.map(device => send(device, 'journal_updated')));
});
