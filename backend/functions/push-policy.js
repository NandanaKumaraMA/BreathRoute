import {createHash} from 'node:crypto';

export const MAX_TOKEN_AGE_MS = 30 * 86400_000;
export const REGION = 'asia-south1';
export class PushError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
export function authenticatedUID(request) {
  const uid = request.auth?.uid;
  if (typeof uid !== 'string' || !uid.length || uid.length > 128) throw new PushError('unauthenticated', 'Sign in to use cloud alerts.');
  return uid;
}
export function installation(data, withToken = false) {
  const allowed = withToken ? ['installationID', 'token'] : ['installationID'];
  if (!data || typeof data !== 'object' || Array.isArray(data) || Object.keys(data).some(key => !allowed.includes(key)) ||
      typeof data.installationID !== 'string' || !/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(data.installationID)) {
    throw new PushError('invalid-argument', 'Invalid device registration.');
  }
  if (withToken && (typeof data.token !== 'string' || data.token.length < 20 || data.token.length > 4096 || /\s/.test(data.token))) {
    throw new PushError('invalid-argument', 'Invalid delivery token.');
  }
  return {installationID: data.installationID.toLowerCase(), ...(withToken ? {token: data.token} : {})};
}
export const tokenID = token => createHash('sha256').update(token).digest('hex');
export function eligibleDevice(device, uid, now = Date.now()) {
  return device?.uid === uid && device.enabled === true && typeof device.token === 'string' &&
    Number.isFinite(device.updatedAtMs) && device.updatedAtMs <= now + 300_000 && now - device.updatedAtMs < MAX_TOKEN_AGE_MS;
}
export function messageFor(device, kind, now = Date.now()) {
  if (!['journal_updated', 'connection_test'].includes(kind)) throw new PushError('invalid-argument', 'Unsupported alert.');
  const test = kind === 'connection_test';
  return {
    token: device.token,
    notification: {title: test ? 'BreatheRoute is connected' : 'Your journal has an update',
      body: test ? 'Cloud notifications are ready on this device.' : 'Open BreatheRoute to view your latest journal.'},
    data: {kind, recipientUID: device.uid, installationID: device.installationID, version: '1'},
    apns: {headers: {'apns-push-type': 'alert', 'apns-priority': '10', 'apns-expiration': String(Math.floor(now / 1000) + 300),
      'apns-collapse-id': `breatheroute-${kind}`}, payload: {aps: {sound: 'default'}}}
  };
}
export function expiredToken(error) {
  return ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error?.code);
}
