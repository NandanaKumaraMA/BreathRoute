import { after, before, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, collection, getDocs, serverTimestamp, Timestamp, writeBatch } from 'firebase/firestore';

let environment;
const path = uid => `users/${uid}/journal/current`;
const snapshot = (overrides = {}) => ({
  schemaVersion: 1, revision: crypto.randomUUID(), updatedAt: serverTimestamp(),
  payload: JSON.stringify({ trips: [], notes: [] }), ...overrides,
});

const walk = (id, revision, extra = {}) => ({ schemaVersion: 1, id, date: Timestamp.fromMillis(1700000000000),
  destination: 'Synthetic park', metres: 800, seconds: 720, dose: 1.2, coverage: 1, demo: false, complete: true,
  journalRevision: revision, ...extra });
const symptom = (id, revision, extra = {}) => ({ schemaVersion: 1, id, date: Timestamp.fromMillis(1700000000000),
  kind: 'Cough', severity: 2, notes: 'Synthetic rules fixture', journalRevision: revision, ...extra });

test('structured owner data validates types, rejects private raw fields and follows the current revision', async () => {
  const uid = 'structured', db = environment.authenticatedContext(uid).firestore(), revision = crypto.randomUUID();
  await assertSucceeds(setDoc(doc(db, path(uid)), snapshot({ schemaVersion: 2, revision })));
  await assertSucceeds(setDoc(doc(db, `users/${uid}`), { schemaVersion: 1, displayName: 'Synthetic Walker', walkCount: 0,
    symptomCount: 0, journalRevision: revision, updatedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(db, `users/${uid}/preferences/current`), { schemaVersion: 1, walkingPace: 'Brisk',
    extraMinutes: 20, journalRevision: revision, updatedAt: serverTimestamp() }));
  const id = crypto.randomUUID(), reference = doc(db, `users/${uid}/walks/${id}`);
  await assertSucceeds(setDoc(reference, walk(id, revision)));
  for (const extra of [{ metres: -1 }, { coverage: 2 }, { dose: NaN }, { date: 'bad' }, { recordedPath: [] },
    { health: {} }, { journalRevision: crypto.randomUUID() }, { id: crypto.randomUUID() }]) {
    await assertFails(setDoc(reference, walk(id, revision, extra)));
  }
  const noteID = crypto.randomUUID(), noteRef = doc(db, `users/${uid}/symptoms/${noteID}`);
  await assertSucceeds(setDoc(noteRef, symptom(noteID, revision)));
  await assertFails(setDoc(noteRef, symptom(noteID, revision, { severity: 6 })));
  await assertFails(setDoc(noteRef, symptom(noteID, revision, { gps: [6.9, 79.8] })));
  await assertSucceeds(getDocs(collection(db, `users/${uid}/walks`)));
  await assertSucceeds(getDocs(collection(db, `users/${uid}/symptoms`)));
  await assertSucceeds(deleteDoc(noteRef));
  await assertSucceeds(setDoc(doc(db, path(uid)), snapshot()));
  await assertFails(setDoc(reference, walk(id, revision)));
});

test('all structured collections deny anonymous and cross-account reads and writes', async () => {
  const paths = ['users/structured', 'users/structured/preferences/current',
    `users/structured/walks/${crypto.randomUUID()}`, `users/structured/symptoms/${crypto.randomUUID()}`,
    'users/structured/demoDatasets/coursework2026'];
  for (const context of [environment.unauthenticatedContext(), environment.authenticatedContext('outsider')]) {
    const db = context.firestore();
    for (const location of paths) {
      await assertFails(getDoc(doc(db, location)));
      await assertFails(setDoc(doc(db, location), { unexpected: true }));
    }
    await assertFails(getDocs(collection(db, 'users/structured/walks')));
    await assertFails(getDocs(collection(db, 'users/structured/symptoms')));
  }
});

test('demo fixtures require explicit synthetic labels and cannot be mistaken for journal records', async () => {
  const uid = 'demo-owner', db = environment.authenticatedContext(uid).firestore();
  const base = `users/${uid}/demoDatasets/coursework2026`;
  const metadata = { schemaVersion: 1, label: 'Coursework demonstration — synthetic', synthetic: true, walkCount: 30,
    symptomCount: 45, updatedAt: serverTimestamp(), profile: { displayName: 'Demo Walker' },
    preferences: { walkingPace: 'Easy', extraMinutes: 10 } };
  await assertSucceeds(setDoc(doc(db, base), metadata));
  await assertFails(setDoc(doc(db, base), { ...metadata, synthetic: false }));
  await assertFails(setDoc(doc(db, base), { ...metadata, walkCount: 30000 }));
  await assertFails(setDoc(doc(db, base), { ...metadata, symptomCount: 0 }));
  const id = crypto.randomUUID(), revision = crypto.randomUUID();
  const example = walk(id, revision, { demo: true, synthetic: true, datasetID: 'coursework2026' });
  await assertSucceeds(setDoc(doc(db, `${base}/walks/${id}`), example));
  await assertFails(setDoc(doc(db, `${base}/walks/${id}`), { ...example, demo: false }));
  await assertFails(setDoc(doc(db, `${base}/walks/${id}`), { ...example, synthetic: false }));
  const outsider = environment.authenticatedContext('different-demo-user').firestore();
  await assertFails(getDoc(doc(outsider, `${base}/walks/${id}`)));
});

test('a full projection chunk remains inside rules access limits', async () => {
  const uid = 'chunk-owner', db = environment.authenticatedContext(uid).firestore(), revision = crypto.randomUUID();
  await setDoc(doc(db, path(uid)), snapshot({ revision, schemaVersion: 2 }));
  const batch = writeBatch(db);
  for (let index = 0; index < 40; index++) {
    const id = crypto.randomUUID();
    batch.set(doc(db, `users/${uid}/walks/${id}`), walk(id, revision));
  }
  await assertSucceeds(batch.commit());
  const records = await getDocs(collection(db, `users/${uid}/walks`));
  if (records.size !== 40) throw new Error('Projection chunk was incomplete');
});
before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-breatheroute',
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => { await environment?.cleanup(); });

test('owner can read, create and update only the bounded current snapshot', async () => {
  const db = environment.authenticatedContext('owner').firestore();
  await assertSucceeds(getDoc(doc(db, path('owner'))));
  await assertSucceeds(setDoc(doc(db, path('owner')), snapshot()));
  await assertSucceeds(getDoc(doc(db, path('owner'))));
  await assertSucceeds(setDoc(doc(db, path('owner')), snapshot()));
  await assertFails(deleteDoc(doc(db, path('owner'))));
  await assertFails(setDoc(doc(db, 'users/owner/journal/other'), snapshot()));
  await assertFails(setDoc(doc(db, 'users/owner/profile/current'), { name: 'Synthetic' }));
  await assertFails(getDocs(collection(db, 'users/owner/journal')));
});

test('unauthenticated and different accounts cannot read or write another journal', async () => {
  for (const context of [environment.unauthenticatedContext(), environment.authenticatedContext('different')]) {
    const db = context.firestore();
    await assertFails(getDoc(doc(db, path('owner'))));
    await assertFails(setDoc(doc(db, path('owner')), snapshot()));
    await assertFails(deleteDoc(doc(db, path('owner'))));
  }
});

test('invalid schema, extra fields, forged timestamp, invalid revision and oversized data fail', async () => {
  const db = environment.authenticatedContext('validation').firestore();
  const reference = doc(db, path('validation'));
  for (const changes of [
    { schemaVersion: 3 }, { schemaVersion: '1' }, { extra: 'unexpected' },
    { updatedAt: Timestamp.fromMillis(0) }, { revision: 'invalid' },
    { payload: '' }, { payload: 'x'.repeat(350001) }, { payload: {} },
  ]) await assertFails(setDoc(reference, snapshot(changes)));
  const missing = snapshot(); delete missing.payload;
  await assertFails(setDoc(reference, missing));
  const fixed = snapshot();
  await assertSucceeds(setDoc(reference, fixed));
  await assertFails(setDoc(reference, { ...fixed, updatedAt: serverTimestamp() }));
});
