import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/local/database_helper.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _programs = [];

  @override
  void initState() {
    super.initState();
    _loadProgramsFromDb();
  }

  void _loadProgramsFromDb() async {
    // Fetches id, name, and json from the local database
    var data = await _dbHelper.getPrograms();
    setState(() {
      _programs = data;
    });
  }

  void _openSettings() async {
    // Wait for the user to come back from Settings
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
    // Refresh the program list in case Metadata was synced
    _loadProgramsFromDb();
  }

  // Helper to determine the friendly type name and color
  Map<String, dynamic> _getProgramTypeDetails(String? jsonString) {
    String typeLabel = "Unknown Type";
    Color typeColor = Colors.grey;

    // FIX: Initialize directly with an IconData, do not cast a Color to it.
    IconData typeIcon = Icons.help_outline;

    if (jsonString != null) {
      try {
        var parsed = jsonDecode(jsonString);
        String rawType = parsed['programType'] ?? '';

        if (rawType == 'WITH_REGISTRATION') {
          typeLabel = "Tracker Program";
          typeColor = Colors.teal; // Color for Tracker
          typeIcon = Icons.person_pin_circle;
        } else if (rawType == 'WITHOUT_REGISTRATION') {
          typeLabel = "Event Program";
          typeColor = Colors.orange; // Color for Event
          typeIcon = Icons.event_note;
        } else {
          typeLabel = rawType;
        }
      } catch (e) {
        print("Error parsing program type: $e");
      }
    }

    return {'label': typeLabel, 'color': typeColor, 'icon': typeIcon};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Welcome"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _programs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("No programs found."),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text("Go to Settings to Sync Metadata"),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _programs.length,
              itemBuilder: (context, index) {
                var prog = _programs[index];
                var typeDetails = _getProgramTypeDetails(prog['json']);

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 6.0,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (typeDetails['color'] as Color)
                          .withOpacity(0.1),
                      child: Icon(
                        typeDetails['icon'] as IconData,
                        color: typeDetails['color'] as Color,
                      ),
                    ),
                    title: Text(
                      prog['name'],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    // UPDATED: Shows Type instead of ID
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        typeDetails['label'],
                        style: TextStyle(
                          color: typeDetails['color'],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SearchScreen(program: prog),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
