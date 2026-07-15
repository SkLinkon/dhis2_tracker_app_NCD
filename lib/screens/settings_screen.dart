import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../services/sync_manager.dart';
import '../data/local/database_helper.dart';
import 'login_screen.dart';
import '../widgets/sync_status_indicator.dart';
import 'sync_queue_screen.dart'; // Import Queue Screen

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SyncService _syncService = SyncService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = false;
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _currentOrgUnit;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  void _loadUserInfo() async {
    var user = await _dbHelper.getUser();
    var ou = await _dbHelper.getDefaultOrgUnit();
    if (mounted) {
      setState(() {
        _currentUser = user;
        _currentOrgUnit = ou;
      });
    }
  }

  void _runSyncMetadata() async {
    setState(() => _isLoading = true);
    bool success = await _syncService.downloadMetadata();
    _loadUserInfo();
    setState(() => _isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Metadata Synced!' : 'Sync Failed.')),
      );
    }
  }

  void _runSyncData() async {
    setState(() => _isLoading = true);
    int count = await _syncService.downloadData();
    setState(() => _isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imported $count clients.')));
    }
  }

  void _runUpload() async {
    SyncManager().startBackgroundSync();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Background Sync Started...')));
  }

  void _onReset() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset App Data?'),
        content: const Text(
          'This will delete ALL local data (events, metadata) and log you out. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset Everything'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      await _dbHelper.resetDatabase();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    String fullName = _currentUser != null
        ? "${_currentUser!['firstName']} ${_currentUser!['surname']}"
        : "Unknown User";
    String orgUnitName = _currentOrgUnit?['name'] ?? "No Org Unit Assigned";

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text("Settings"),
            actions: const [SyncStatusIndicator(), SizedBox(width: 16)],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Card(
                elevation: 3,
                color: Colors.blue[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _currentUser?['username'] ?? '',
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              orgUnitName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- NEW: Sync Queue Button ---
              Card(
                child: ListTile(
                  leading: const Icon(Icons.list_alt, color: Colors.purple),
                  title: const Text("Sync Queue"),
                  subtitle: const Text("View pending & unsynced data"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SyncQueueScreen(),
                      ),
                    );
                  },
                ),
              ),

              // ------------------------------
              const SizedBox(height: 10),
              const Text(
                "Data Synchronization",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.cloud_upload,
                        color: Colors.blue,
                      ),
                      title: const Text("Upload Data"),
                      subtitle: const Text("Send local events to server"),
                      onTap: _runUpload,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.cloud_download,
                        color: Colors.green,
                      ),
                      title: const Text("Download Patients"),
                      subtitle: const Text("Fetch clients from server"),
                      onTap: _isLoading ? null : _runSyncData,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.sync, color: Colors.orange),
                      title: const Text("Sync Metadata"),
                      subtitle: const Text("Sync programs and dependencies"),
                      onTap: _isLoading ? null : _runSyncMetadata,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Card(
                color: Colors.red[50],
                child: ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    "Reset App Data",
                    style: TextStyle(color: Colors.red),
                  ),
                  subtitle: const Text("Clear all data and logout"),
                  onTap: _isLoading ? null : _onReset,
                ),
              ),
            ],
          ),
        ),
        if (_isLoading)
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withOpacity(0.6),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}
