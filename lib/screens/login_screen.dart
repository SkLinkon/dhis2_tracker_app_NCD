import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; // Import flutter_svg
import '../services/auth_service.dart';
import '../core/dhis_client.dart'; // Import to set the URL
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // GENERIC: No default URL. Starts empty.
  final TextEditingController _urlController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _showUrlField = true; // GENERIC: Show URL field by default

  void _handleLogin() async {
    // 1. Validate URL
    String url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a Server URL'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // 2. Set the API URL
    DhisClient().setBaseUrl(url);

    // 3. Attempt Login
    bool success = await _authService.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login Successful! Data saved offline.')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login Failed. Check URL, internet, or credentials.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("")), //Can add app bar title here
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // Custom App Icon
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SvgPicture.asset(
                    'assets/images/app_icon.svg',
                    width: 100,
                    height: 100,
                    placeholderBuilder: (BuildContext context) => const Icon(
                      Icons.public,
                      size: 80,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                "Welcome",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),

              // URL Field (Visible by default)
              if (_showUrlField)
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'DHIS2 Server URL',
                    hintText:
                    'https://play.dhis2.org/android-current', // Generic Hint
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                ),

              if (_showUrlField) const SizedBox(height: 16),

              // Username Field
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),

              // Password Field
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 10),

              // Settings Toggle
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showUrlField = !_showUrlField;
                    });
                  },
                  icon: Icon(
                    _showUrlField ? Icons.expand_less : Icons.settings,
                  ),
                  label: Text(
                    _showUrlField ? "Hide Server Settings" : "Server Settings",
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Login Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Login'),
                ),
              ),

              // ------------------------------------------
              // NEW: Developer Info Footer
              // ------------------------------------------
              const SizedBox(height: 50),
              Column(
                children: [
                  Text(
                    "Developed by",
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "HISP Bangladesh Foundation", // By Sk Linkon
                    style: TextStyle(
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "v1.0.2",
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}