// =============================================================================
// Firebase configuration
// =============================================================================
// Fill this file with the values from:
//   Firebase Console -> Project settings (gear icon) -> Your apps
//
// You must register TWO apps inside the same Firebase project:
//   1) Android app -> package name: com.cafepos.cafe_pos
//   2) Web app     -> used by the Windows build (this is how Firebase's
//                     official Windows support works: Windows reuses the
//                     Web app id).
//
// These values are NOT secrets. They are public client identifiers and are
// safe to commit. Your data is protected by Firestore security rules
// (see firestore.rules in the repo root).
// =============================================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        return windows;
      default:
        return windows;
    }
  }

  // ---- Android app --------------------------------------------------------
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PASTE_ANDROID_API_KEY',
    appId: 'PASTE_ANDROID_APP_ID',
    messagingSenderId: 'PASTE_MESSAGING_SENDER_ID',
    projectId: 'PASTE_PROJECT_ID',
    storageBucket: 'PASTE_PROJECT_ID.firebasestorage.app',
  );

  // ---- Web app (also used by the Windows build) ---------------------------
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'PASTE_WEB_API_KEY',
    appId: 'PASTE_WEB_APP_ID',
    messagingSenderId: 'PASTE_MESSAGING_SENDER_ID',
    projectId: 'PASTE_PROJECT_ID',
    authDomain: 'PASTE_PROJECT_ID.firebaseapp.com',
    storageBucket: 'PASTE_PROJECT_ID.firebasestorage.app',
  );

  // Windows reuses the Web app registration.
  static const FirebaseOptions windows = web;
}
