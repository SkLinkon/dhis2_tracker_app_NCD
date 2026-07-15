import 'package:flutter/material.dart';
import '../data/local/database_helper.dart';
import '../core/sync_state.dart';

class SyncQueueScreen extends StatefulWidget {
  const SyncQueueScreen({super.key});

  @override
  State<SyncQueueScreen> createState() => _SyncQueueScreenState();
}

class _SyncQueueScreenState extends State<SyncQueueScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<Map<String, dynamic>> _pendingEnrollments = [];
  List<Map<String, dynamic>> _pendingEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  void _loadQueue() async {
    // 1. Fetch pending enrollments
    final enrollments = await _dbHelper.getPendingEnrollments();
    // 2. Fetch pending events
    final events = await _dbHelper.getAllPendingEvents();

    if (mounted) {
      setState(() {
        _pendingEnrollments = enrollments;
        _pendingEvents = events;
        _isLoading = false;
      });
    }
  }

  Widget _buildStatusBadge(String statusRaw) {
    SyncStatus status = parseSyncStatus(statusRaw);
    Color color;
    IconData icon;
    String text;

    switch (status) {
      case SyncStatus.toPost:
        color = Colors.blue;
        icon = Icons.cloud_upload;
        text = "To Post";
        break;
      case SyncStatus.toUpdate:
        color = Colors.orange;
        icon = Icons.update;
        text = "To Update";
        break;
      case SyncStatus.error:
        color = Colors.red;
        icon = Icons.error;
        text = "Error";
        break;
      case SyncStatus.uploading:
        color = Colors.blueAccent;
        icon = Icons.sync;
        text = "Uploading";
        break;
      case SyncStatus.warning:
        color = Colors.amber;
        icon = Icons.warning;
        text = "Warning";
        break;
      default:
        color = Colors.grey;
        icon = Icons.help;
        text = statusRaw;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sync Queue"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadQueue),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_pendingEnrollments.isEmpty && _pendingEvents.isEmpty)
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.green[200],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "All data is synced!",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_pendingEnrollments.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      "Pending Enrollments",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ..._pendingEnrollments.map(
                    (e) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_add),
                        ),
                        title: Text("Enrollment: ${e['enrollment']}"),
                        subtitle: Text("Date: ${e['enrollmentDate']}"),
                        trailing: _buildStatusBadge(e['syncStatus']),
                      ),
                    ),
                  ),
                ],

                if (_pendingEvents.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      "Pending Events",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ..._pendingEvents.map(
                    (e) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(Icons.event_note, color: Colors.white),
                        ),
                        title: Text("Event: ${e['event']}"),
                        subtitle: Text("Date: ${e['eventDate']}"),
                        trailing: _buildStatusBadge(e['syncStatus']),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
