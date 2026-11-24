# Joker Cafe — Firebase cloud sync setup

## What was wrong

The app had all the Firebase code, but **no Firebase project was ever connected**:

- there was no `firebase_options.dart` and no `google-services.json`
- `Firebase.initializeApp()` failed silently (`catch (_) {}`)
- `firebaseReady` stayed `false`, so every `if (useCloud)` block never ran
- the only working sync was the LAN (same Wi-Fi) layer

That LAN layer was destructive: when a device connected, it replaced its
whole local database with the host's copy. Anything added while disconnected
was erased. That is why your data disappeared.

## What the app does now

- **Firestore is the single source of truth.** No LAN overwrite any more.
- Every change is written to a **durable local outbox first**, then pushed to
  Firestore. If the internet is down, the change stays on the device and is
  retried automatically (every 30 seconds and as soon as the connection
  returns).
- Every device listens to Firestore in real time, so a sale on the phone
  appears on the laptop instantly.
- Firestore offline persistence is enabled, so the app also works with no
  internet and syncs when it comes back.
- The old "ربط الأجهزة" button is now a cloud status button
  (متزامن / أوفلاين / غير متصل).

---

## Step 1 — Create the Firebase project

1. Open <https://console.firebase.google.com/>
2. Click **Add project**
3. Name it e.g. `joker-cafe`
4. Google Analytics is optional — you can disable it
5. Click **Create project**

## Step 2 — Add the Android app

1. In the project, click the **Android** icon (or **Add app → Android**)
2. **Android package name:** `com.cafepos.cafe_pos`
   (this is the id the build workflow generates; it must match the existing
   Firebase Android app exactly)
3. Nickname: `Joker Cafe Android`
4. Click **Register app**
5. Skip the download steps — you do not need `google-services.json`,
   because this app passes the config in code
6. Copy these values somewhere:
   - `apiKey`
   - `appId`
   - `messagingSenderId`
   - `projectId`
   - `storageBucket`

## Step 3 — Add the Web app (used by the Windows build)

1. Click **Add app → Web** (the `</>` icon)
2. Nickname: `Joker Cafe Windows`
3. **Do not** enable Firebase Hosting
4. Click **Register app**
5. Copy these values:
   - `apiKey`
   - `appId`
   - `messagingSenderId`
   - `projectId`
   - `authDomain`
   - `storageBucket`

> Windows support in the official FlutterFire plugins reuses the **Web app**
> registration. This is the documented behaviour of the `firebase_core`
> Windows plugin.

## Step 4 — Fill in `lib/firebase_options.dart`

Open `lib/firebase_options.dart` and replace the placeholders:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'ANDROID apiKey',
  appId: 'ANDROID appId',
  messagingSenderId: 'ANDROID messagingSenderId',
  projectId: 'ANDROID projectId',
  storageBucket: 'ANDROID storageBucket',
);

static const FirebaseOptions web = FirebaseOptions(
  apiKey: 'WEB apiKey',
  appId: 'WEB appId',
  messagingSenderId: 'WEB messagingSenderId',
  projectId: 'WEB projectId',
  authDomain: 'WEB authDomain',
  storageBucket: 'WEB storageBucket',
);
```

`windows` automatically uses `web`, so you only fill two blocks.

## Step 5 — Enable anonymous sign-in

1. Firebase Console → **Build → Authentication**
2. Click **Get started**
3. Open the **Sign-in method** tab
4. Click **Anonymous** → **Enable** → **Save**

The app signs every device in silently. No login screen for staff, but only
devices inside your project can read/write the data.

## Step 6 — Create Firestore and publish the rules

1. Firebase Console → **Build → Firestore Database**
2. Click **Create database**
3. Choose a location close to you (e.g. `eur3` or `me-central2`)
4. Start in **Production mode**
5. Open the **Rules** tab
6. Replace everything with the contents of `firestore.rules` in this repo:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

7. Click **Publish**

## Step 7 — Build and install

Run the **Build Joker Cafe** workflow in GitHub Actions
(**Actions → Build Joker Cafe → Run workflow**).

Install the new APK/EXE on **all** devices.

> The first device that runs the new version with an empty cloud database
> automatically uploads its local data (tables, inventory, sales, expenses,
> closed days, logs) to Firestore. Your existing data is not lost.

---

## How to verify it works

1. Open the app on two devices.
2. The badge in the top bar should say **متزامن** on both.
3. Tap the badge — you should see:
   - قاعدة البيانات السحابية: متصل بـ Firebase
   - الإنترنت: متاح
   - عمليات في انتظار الرفع: 0
4. Add an expense or start a table on one device — it should appear on the
   other within a second or two.
5. Turn off Wi-Fi on one device and add a sale, an expense, and an inventory
   edit. The badge changes to **أوفلاين - n بالانتظار** (n = saved changes).
   Tap it to confirm they are listed as pending.
6. Close the app completely while still offline, then reopen it. The edits are
   still there — they are written to disk before anything is sent to Firebase.
7. Turn Wi-Fi back on. The count drops to 0 and the badge returns to
   **متزامن**. Open the second device — all the edits appear there too.

## Offline edits — what to expect

- Every change is written to a durable outbox on the device **before** it is
  sent to Firestore, so it survives a killed app, a dead battery, or days
  without internet.
- While offline, incoming cloud snapshots are merged with your pending edits,
  so your changes never disappear from the screen before they are uploaded.
- The outbox is retried automatically every 30 seconds and immediately when
  connectivity returns. No need to press anything.
- **مزامنة الآن** in the status dialog forces an immediate retry, including
  writes that were previously rejected (e.g. before the rules were fixed).

## Troubleshooting

| Badge / error | Meaning | Fix |
|---|---|---|
| غير متصل | Firebase never initialised | `firebase_options.dart` still has `PASTE_...` values, or the project id is wrong |
| صلاحيات Firestore مرفوضة | Rules reject the client | Publish `firestore.rules`, and enable Anonymous auth |
| Firebase غير مُفعّل | Auth or Firestore not enabled | Enable Anonymous sign-in and create the Firestore database |
| أوفلاين - n بالانتظار | No internet, `n` changes saved on this device | Normal — they upload automatically when the connection returns; they also survive an app restart |
| مفتاح Firebase غير صحيح | API key rejected | Check `firebase_options.dart`; if the key is restricted in Google Cloud Console → APIs & Services → Credentials, set Application restrictions to **None** (or allow the Windows app) |
| Build fails: minSdk | Android minSdk too low | The workflow already forces `minSdk 24`; make sure you use the updated `.github/workflows/main.yml` |
| Windows build: `C4238` treated as an error | Firebase Auth C++ plugin warning with `/WX` | The workflow now adds `/wd4238`; re-run the updated `Build Joker Cafe` workflow |
| Android app opens then closes immediately | `MainActivity.kt` left in the old package after renaming | The workflow now moves it to `com.cafepos.cafe_pos`; re-run the updated `Build Joker Cafe` workflow and reinstall |

## Notes

- `github/workflows/build.yml` (without the leading dot) is **not** read by
  GitHub Actions. Only `.github/workflows/main.yml` runs. You can delete the
  stray folder.
- Both devices must be on the **same Firebase project**. They do not need to
  be on the same Wi-Fi any more.
- The API key in `firebase_options.dart` is public by design; the security
  rules are what protect your data.
