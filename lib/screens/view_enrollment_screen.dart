import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/local/database_helper.dart';
import 'enrollment_edit_screen.dart';
import '../core/sync_state.dart';
import '../services/sync_manager.dart';

class ViewEnrollmentScreen extends StatefulWidget {
  final Map<String, dynamic> program;
  final String teiId;
  final String enrollmentId;
  final Map<String, dynamic> initialAttributes;

  const ViewEnrollmentScreen({
    super.key,
    required this.program,
    required this.teiId,
    required this.enrollmentId,
    required this.initialAttributes,
  });

  @override
  State<ViewEnrollmentScreen> createState() => _ViewEnrollmentScreenState();
}

class _ViewEnrollmentScreenState extends State<ViewEnrollmentScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late Map<String, dynamic> _currentAttributes;
  final Map<String, String> _attributeLabels = {};
  final List<String> _attributeOrder = [];

  bool _isLoading = true;
  bool _hasChanges = false;
  Map<String, dynamic>? _enrollmentData;

  @override
  void initState() {
    super.initState();
    _currentAttributes = widget.initialAttributes;
    _parseMetadata();
    _loadEnrollmentData();
  }

  void _loadEnrollmentData() async {
    var enr = await _dbHelper.getEnrollment(widget.teiId, widget.program['id']);
    if (mounted) {
      setState(() {
        _enrollmentData = enr;
      });
    }
  }

  void _parseMetadata() {
    try {
      Map<String, dynamic> p = jsonDecode(widget.program['json']);
      if (p.containsKey('programTrackedEntityAttributes')) {
        var pteas = p['programTrackedEntityAttributes'] as List;
        for (var ptea in pteas) {
          var tea = ptea['trackedEntityAttribute'];
          String id = tea['id'];
          String label =
              tea['formName'] ?? tea['displayName'] ?? tea['name'] ?? 'Unknown';
          _attributeLabels[id] = label;
          _attributeOrder.add(id);
        }
      }
    } catch (e) {
      print("Error parsing metadata: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _openEditScreen() async {
    bool? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnrollmentEditScreen(
          program: widget.program,
          teiId: widget.teiId,
          enrollmentId: widget.enrollmentId,
          initialAttributes: _currentAttributes,
        ),
      ),
    );
    if (result == true) {
      _hasChanges = true;
      var updatedAttrs = await _dbHelper.getTeiAttributes(widget.teiId);
      setState(() {
        _currentAttributes = updatedAttrs;
      });
      _loadEnrollmentData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Profile Updated")));
    }
  }

  // NEW: Sync Trigger
  void _triggerSync() {
    SyncManager().startBackgroundSync();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Sync Started...")));
  }

  @override
  Widget build(BuildContext context) {
    String syncStatusRaw = _enrollmentData?['syncStatus'] ?? 'synced';
    SyncStatus syncStatus = parseSyncStatus(syncStatusRaw);

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Patient Profile"),
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              onPressed: _triggerSync,
              tooltip: "Sync Now",
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: "Edit Profile",
              onPressed: _openEditScreen,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  if (syncStatus != SyncStatus.synced)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: syncStatus == SyncStatus.error
                            ? Colors.red[50]
                            : Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: syncStatus == SyncStatus.error
                              ? Colors.red
                              : Colors.orange,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            syncStatus == SyncStatus.error
                                ? Icons.error
                                : Icons.cloud_off,
                            color: syncStatus == SyncStatus.error
                                ? Colors.red
                                : Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Status: ${syncStatusRaw.toUpperCase()}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: syncStatus == SyncStatus.error
                                      ? Colors.red
                                      : Colors.orange[800],
                                ),
                              ),
                              const Text(
                                "Changes are waiting to be synced.",
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Enrollment Details",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const Divider(),
                          const SizedBox(height: 10),
                          ..._attributeOrder.map((id) {
                            String label = _attributeLabels[id] ?? id;
                            String value = _currentAttributes[id] ?? '-';
                            if (value.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      value,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openEditScreen,
          icon: const Icon(Icons.edit),
          label: const Text("Edit Profile"),
        ),
      ),
    );
  }
}
