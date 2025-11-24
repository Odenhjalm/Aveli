// This is a lightweight placeholder for Firebase options so the app compiles.
// Replace this file with a generated one from FlutterFire CLI for real builds.
// Run: flutterfire configure --project=<your-firebase-project>

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        return web;
    }
  }

  // NOTE: These are dummy placeholders; actual values come from FlutterFire.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'dev-placeholder',
    appId: 'dev-placeholder',
    messagingSenderId: 'dev-placeholder',
    projectId: 'dev-placeholder',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'dev-placeholder',
    appId: 'dev-placeholder',
    messagingSenderId: 'dev-placeholder',
    projectId: 'dev-placeholder',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'dev-placeholder',
    appId: 'dev-placeholder',
    messagingSenderId: 'dev-placeholder',
    projectId: 'dev-placeholder',
    iosBundleId: 'dev.placeholder',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'dev-placeholder',
    appId: 'dev-placeholder',
    messagingSenderId: 'dev-placeholder',
    projectId: 'dev-placeholder',
    iosBundleId: 'dev.placeholder',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'dev-placeholder',
    appId: 'dev-placeholder',
    messagingSenderId: 'dev-placeholder',
    projectId: 'dev-placeholder',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'dev-placeholder',
    appId: 'dev-placeholder',
    messagingSenderId: 'dev-placeholder',
    projectId: 'dev-placeholder',
  );
}
