import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/home_page.dart';
import 'pages/user_dashboard.dart';
import 'firebase_options.dart';

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

// iOS-style scrolling for every scrollable page: rubber-band bounce, and no
// Android glow/stretch overscroll effect on top of it.
class IosScrollBehavior extends MaterialScrollBehavior {
  const IosScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color _brandGreen = Color(0xFF7CB342);
  static const Color _iosBackground = Color(0xFFF2F2F7);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter HarBest App',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const IosScrollBehavior(),
      theme: ThemeData(
        // Seeded from the app's own green (was deepPurple), so default
        // colors (spinners, text buttons, focused fields) match the brand.
        colorScheme: ColorScheme.fromSeed(seedColor: _brandGreen),
        useMaterial3: true,
        // Preserves the font family that HomePage/UserDashboard/UserAccount
        // used to set individually via their own nested MaterialApps.
        // Now that those are plain widgets, this is the one place it's
        // applied app-wide.
        fontFamily: 'Arial',

        // iOS grouped-list gray behind pages that don't set their own
        // background.
        scaffoldBackgroundColor: _iosBackground,

        // iOS slide-in / swipe-back on every route, on Android too.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),

        // Floating, rounded snack bars.
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),

        // Rounded buttons (pages that set their own style still win).
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // White rounded cards with a soft shadow (the Material 3 purple-ish
        // surface tint is turned off). Needs Flutter 3.27+.
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 1.5,
          shadowColor: const Color(0x26000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // iOS-style alert dialogs: white, large rounded corners.
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),

        // Rounded white text fields with a light gray outline that turns
        // green when focused. Fields that set their own decoration win.
        // Needs Flutter 3.35+ (InputDecorationThemeData).
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _brandGreen, width: 1.5),
          ),
        ),
      ),
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