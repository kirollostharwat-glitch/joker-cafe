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
    apiKey: 'AIzaSyC38YsdDlepr22CJOieE0mrtBpHm25sYqg',
    appId: '1:600561749366:android:c5a909e7476728911bbe57',
    messagingSenderId: '600561749366',
    projectId: 'joker-cafe-ddc53',
    storageBucket: 'joker-cafe-ddc53.firebasestorage.app',
  );

  // ---- Web app (also used by the Windows build) ---------------------------
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAnI6IJg2RLK3Tv4ewLeBlqwl-VX5e4-ow',
    appId: '1:600561749366:web:362b796e0eddd43a1bbe57',
    messagingSenderId: '600561749366',
    projectId: 'joker-cafe-ddc53',
    authDomain: 'joker-cafe-ddc53.firebaseapp.com',
    storageBucket: 'joker-cafe-ddc53.firebasestorage.app',
  );

  // Windows reuses the Web app registration.
  static const FirebaseOptions windows = web;
}
