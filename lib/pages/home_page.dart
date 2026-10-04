import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/pages/get_started.dart';
import 'package:flutter_application_harbest_1/pages/log_in.dart';

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
        decoration: const BoxDecoration(color: Color(0xFF2E5926)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),

            // app title
            const Text(
              'HarBest',
              style: TextStyle(
                color: Color.fromARGB(255, 97, 154, 50),
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'JOIN THE FIELD',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              'Monitor crop health in real-time with AI-powered analytics and IoT sensors.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),

            const Spacer(flex: 2),

            // Buttons Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: Row(
                children: [
                  // Get Started Button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GetStarted(),
                          ),
                        );
                      },
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF7DB343), Color(0xFF4C7A2D)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              // ignore: deprecated_member_use
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Get Started',
                            style: TextStyle(
                              // ignore: deprecated_member_use
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),

                  // Log in Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LogIn(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD9D9D9),
                        foregroundColor: Colors.black,
                        minimumSize: const Size(0, 60),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Log in',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
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