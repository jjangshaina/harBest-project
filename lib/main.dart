import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/security/storing_data.dart';
import 'pages/home_page.dart';
import 'pages/user_dashboard.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initializing Firebase for auth & app data
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initializing Supabase for sensor data from Raspberry Pi
  await Supabase.initialize(                                    // ← changed
    url: 'https://vdginsecbpsqdayqugtg.supabase.co',          // ← removed /rest/v1/
    anonKey: 'sb_publishable_SCZV5hZeFBgFChWKvkE1Ig_4_4P1kOH',
  );

  // Check if user is already logged in from previous session
  final String? status = await StoringData().getLoginStatus();
  final bool isLoggedIn = (status == 'true');

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter HarBest App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: isLoggedIn ? const UserDashboard() : const HomePage(),
    );
  }
}