import {parseArgs} from 'node:util';
import {initializeApp, applicationDefault, deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getMessaging} from 'firebase-admin/messaging';
import {eligibleDevice, messageFor, expiredToken} from './push-policy.js';

// Operator-only sender for Spark. Run on your trusted computer; never bundle admin credentials in iOS.
let app;
try {
  const {values}=parseArgs({options:{project:{type:'string'},uid:{type:'string'},installation:{type:'string'},kind:{type:'string',default:'connection_test'},send:{type:'boolean',default:false}}});
  if(!values.project || !/^[a-z][a-z0-9-]{4,62}$/.test(values.project) || !values.uid || values.uid.includes('/') || values.uid.length>128 ||
     !values.installation || !/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(values.installation) || !['connection_test','journal_updated'].includes(values.kind)) {
    throw new Error('Use --project PROJECT --uid UID --installation UUID; optional --kind connection_test|journal_updated and --send.');
  }
  if(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('This live sender does not run against test emulators.');
  app=initializeApp({projectId:values.project,credential:applicationDefault()});
  const db=getFirestore(app), reference=db.collection('users').doc(values.uid).collection('pushDevices').doc(values.installation.toLowerCase());
  const snapshot=await reference.get(), stored=snapshot.data();
  const device={...stored,updatedAtMs:stored?.updatedAt?.toMillis?.()};
  if(!snapshot.exists || device.installationID!==values.installation.toLowerCase() || !eligibleDevice(device,values.uid)) throw new Error('No fresh enabled registration exists for this account and installation.');
  try {
    await getMessaging(app).send(messageFor(device,values.kind),!values.send);
    console.log(values.send?'FCM accepted the notification. Verify actual receipt on the device.':'Validation accepted. No notification sent. Add --send to request delivery.');
  } catch(error) {
    if(expiredToken(error)) {
      await db.runTransaction(async transaction=>{
        const current=await transaction.get(reference);
        if(current.data()?.token===stored.token && current.data()?.uid===values.uid) transaction.delete(reference);
      });
    }
    // Do not print provider response details or delivery tokens.
    throw new Error('FCM could not accept the notification. Check admin credentials, APNs setup and the device registration.');
  }
} catch(error) {
  console.error(error.message.startsWith('Use --') || error.message.startsWith('No fresh') || error.message.startsWith('This live') ? error.message : 'Notification sender could not run. Check the private admin credential configuration and APNs setup.');
  process.exitCode=1;
} finally { if(app) await deleteApp(app); }
