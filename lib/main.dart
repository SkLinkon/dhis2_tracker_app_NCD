import 'dart:io'; // Import Platform to check if we are on Linux
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Import the desktop adapter
import 'screens/splash_screen.dart'; // UPDATED: Import Splash Screen
import 'services/sync_manager.dart'; // Import SyncManager

void main() {
  // Initialize Database for Desktop (Linux/Windows)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize the SyncManager (Start Network Listeners)
  SyncManager();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DHIS2 Tracker App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(
            0xFF0EA5E9,
          ), // Updated to match your NCD Asset Blue
        ),
        useMaterial3: true,
      ),
      // UPDATED: Start with Splash Screen instead of Login
      home: const CustomSplashScreen(),
    );
  }
}
