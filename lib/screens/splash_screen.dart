import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart'; // Import Auth Service to check session
import 'login_screen.dart';
import 'home_screen.dart'; // Import Home Screen for auto-login

class CustomSplashScreen extends StatefulWidget {
  const CustomSplashScreen({super.key});

  @override
  State<CustomSplashScreen> createState() => _CustomSplashScreenState();
}

class _CustomSplashScreenState extends State<CustomSplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  // UPDATED: Check if user is logged in before navigating
  void _checkSession() async {
    // 1. Keep the splash screen for at least 3 seconds (Branding)
    await Future.delayed(const Duration(seconds: 3));

    // 2. Check Local Database for an existing user session
    // AuthService.isLoggedIn() returns true if a user exists in the local SQLite DB
    bool isLoggedIn = await AuthService().isLoggedIn();

    if (!mounted) return;

    // 3. Navigate accordingly
    if (isLoggedIn) {
      // User is already logged in -> Go straight to Home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } else {
      // No user found -> Go to Login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Container
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: SvgPicture.asset(
                  'assets/images/app_icon.svg',
                  width: 120,
                  height: 120,
                  placeholderBuilder: (BuildContext context) => const Icon(
                    Icons.public,
                    size: 80,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            const Text(
              "NCD Control",
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const Text(
              "Monitor. Manage. Live.",
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
            ),
            const SizedBox(height: 60),
            // Loading Bar
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: const Color(0xFF334155),
                color: const Color(0xFF10B981),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}