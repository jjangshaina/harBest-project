import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/pages/get_started.dart';
import 'package:flutter_application_harbest_1/pages/log_in.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';

// Plain widget now, not its own MaterialApp — relies on the single root
// MaterialApp defined in main.dart. Kept as a class (rather than being
// removed and replaced everywhere with WelcomeScreen) so existing
// Navigator calls elsewhere in the app (e.g. logout) don't need to change.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WelcomeScreen();
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.authBackground,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),

            // app title
            const Text('HarBest', style: AppText.welcomeBrand),
            const SizedBox(height: 10),
            const Text('JOIN THE FIELD', style: AppText.welcomeHeadline),

            const SizedBox(height: 20),
            const Text(
              'Monitor crop health in real-time with AI-powered analytics and IoT sensors.',
              textAlign: TextAlign.center,
              style: AppText.welcomeBody,
            ),

            const Spacer(flex: 2),

            // Buttons Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: Row(
                children: [
                  Expanded(
                    child: AppLandingButton(
                      label: 'Get Started',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GetStarted()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: AppLandingButton(
                      label: 'Log in',
                      primary: false,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LogIn()),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }
}