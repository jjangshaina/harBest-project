import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/home_page.dart';
import 'pages/user_dashboard.dart';
import 'firebase_options.dart';
import 'theme/app_style.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initializing Firebase for auth & app data
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initializing Supabase for sensor data from Raspberry Pi
  await Supabase.initialize(
    url: 'https://vdginsecbpsqdayqugtg.supabase.co',
    anonKey: 'sb_publishable_SCZV5hZeFBgFChWKvkE1Ig_4_4P1kOH',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter HarBest App',
      debugShowCheckedModeBanner: false,
      // The look of the whole app (colors, dialogs, text fields, buttons,
      // page transitions, scrolling) lives in theme/app_style.dart.
      scrollBehavior: const IosScrollBehavior(),
      theme: AppTheme.light(),
      // Every other page (HomePage, GetStarted, LogIn, UserAccount,
      // UserDashboard) is a plain widget relying on this one MaterialApp —
      // none of them should wrap themselves in another MaterialApp.
      home: const AuthGate(),
    );
  }
}

// Decides which screen to show based on Firebase Auth's own live session,
// not a locally cached flag. A cached flag (like the one previously read
// from secure storage) can drift out of sync with reality — e.g. it can
// survive an app reinstall on iOS via Keychain persistence even after
// Firebase's own session is gone, or stay "true" if a token is revoked in
// the background. Checking authStateChanges() directly avoids that class
// of bug entirely.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        // Defensive: the login flow already blocks unverified users and
        // signs them straight back out, so a persisted session reaching
        // here should already be verified. If that ever isn't true, don't
        // let it through to the Dashboard.
        if (user != null && !user.emailVerified) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            fb_auth.FirebaseAuth.instance.signOut();
          });
          return const HomePage();
        }

        return user != null ? const UserDashboard() : const HomePage();
      },
    );
  }
}