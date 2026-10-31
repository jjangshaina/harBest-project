import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/home_page.dart';
import 'pages/user_dashboard.dart';
import 'firebase_options.dart';
import 'theme/app_style.dart';
import 'pages/log_in.dart' show loginInProgress;

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

Future<void> _initializeServices() async {
  try {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      throw StateError('Missing Supabase configuration.');
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      accessToken: () async =>
          await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken(),
    );
  } catch (error, stackTrace) {
    debugPrint('HarBest startup failed: $error\n$stackTrace');
    rethrow;
  }
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
      home: const _AppStartup(),
    );
  }
}

class _AppStartup extends StatefulWidget {
  const _AppStartup();

  @override
  State<_AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<_AppStartup> {
  late final Future<void> _initialization = _initializeServices();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          final isMissingConfig =
              error is StateError &&
              error.message == 'Missing Supabase configuration.';
          return _StartupErrorPage(
            message: isMissingConfig
                ? 'Add SUPABASE_URL and SUPABASE_ANON_KEY to env.json, then launch using “HarBest (with env.json)”.'
                : 'HarBest could not initialize. Check the VS Code Debug Console for details.',
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return const AuthGate();
      },
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  'HarBest could not start',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
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
//
// While the Log In page is still running its own checks (loginInProgress),
// this waits on the Welcome screen so the Dashboard is never built for a
// login that is about to be rejected.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: loginInProgress,
      builder: (context, loggingIn, _) => StreamBuilder<fb_auth.User?>(
        stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (loggingIn) return const HomePage();

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
      ),
    );
  }
}