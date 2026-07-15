import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/local/database_helper.dart';
import 'event_form_screen.dart';
import 'view_enrollment_screen.dart';
import 'view_event_screen.dart';
import '../core/sync_state.dart';
import '../services/sync_manager.dart';
import '../services/rule_engine_service.dart'; // Import Engine

class TeiDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> program;
  final String teiId;
  final Map<String, dynamic> attributes;

  const TeiDashboardScreen({
    super.key,
    required this.program,
    required this.teiId,
    required this.attributes,
  });

  @override
  State<TeiDashboardScreen> createState() => _TeiDashboardScreenState();
}

class _TeiDashboardScreenState extends State<TeiDashboardScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final RuleEngineService _ruleEngine = RuleEngineService(); // Engine

  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _enrollment;
  String? _enrollmentId;

  late Map<String, dynamic> _currentAttributes;
  final Map<String, String> _stageNames = {};
  final Map<String, dynamic> _stagesMap = {};

  // Stores IDs of stages to HIDE based on rules
  final List<String> _hiddenStages = [];

  @override
  void initState() {
    super.initState();
    _currentAttributes = widget.attributes;
    _parseMetadata();
    _loadEvents();
    // Run rules to filter stages immediately
    _runDashboardRules();
  }

  // --- RULE LOGIC FOR DASHBOARD ---
  Future<void> _runDashboardRules() async {
    // 1. Prepare Data (Just Attributes)
    Map<String, dynamic> currentData = {};
    _currentAttributes.forEach((key, value) {
      currentData[key] = value.toString();
    });

    // 2. Run Rules (Global context, no specific stage)
    List<RuleEffect> effects = await _ruleEngine.runRules(
      widget.program['id'],
      currentData,
      eventDate: DateTime.now().toIso8601String().split('T')[0],
      programStageId: null,
    );

    if (!mounted) return;

    setState(() {
      _hiddenStages.clear();
      for (var effect in effects) {
        // Capture HIDEPROGRAMSTAGE actions
        if (effect.action == 'HIDEPROGRAMSTAGE' && effect.targetId != null) {
          _hiddenStages.add(effect.targetId!);
        }
      }
    });
  }
  // --------------------------------

  void _parseMetadata() {
    try {
      Map<String, dynamic> p = jsonDecode(widget.program['json']);
      if (p.containsKey('programStages')) {
        for (var stage in p['programStages']) {
          String id = stage['id'];
          String name = stage['name'] ?? 'Unknown Stage';
          _stageNames[id] = name;
          _stagesMap[id] = stage;
        }
      }
    } catch (e) {
      print("Error parsing metadata for Dashboard: $e");
    }
  }

  void _loadEvents() async {
    var enrollment = await _dbHelper.getEnrollment(
      widget.teiId,
      widget.program['id'],
    );
    if (enrollment != null) {
      _enrollment = enrollment;
      _enrollmentId = enrollment['enrollment'];
      var events = await _dbHelper.getEvents(_enrollmentId!);
      setState(() {
        _events = events;
      });
    }
  }

  void _reloadAttributes() async {
    var updatedAttrs = await _dbHelper.getTeiAttributes(widget.teiId);
    setState(() {
      _currentAttributes = updatedAttrs;
    });
    // Re-run rules if attributes changed
    _runDashboardRules();
  }

  void _viewEnrollment() async {
    if (_enrollmentId == null) return;
    bool? didChange = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewEnrollmentScreen(
          program: widget.program,
          teiId: widget.teiId,
          enrollmentId: _enrollmentId!,
          initialAttributes: _currentAttributes,
        ),
      ),
    );
    if (didChange == true) {
      _reloadAttributes();
    }
  }

  void _onEventClick(Map<String, dynamic> event) async {
    String stageId = event['programStage'];
    var stage = _stagesMap[stageId];
    if (stage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: Stage metadata not found")),
      );
      return;
    }
    bool? didChange = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewEventScreen(
          program: widget.program,
          event: event,
          stage: stage,
        ),
      ),
    );
    if (didChange == true) {
      _loadEvents();
    }
  }

  void _showStageSelection() {
    Map<String, dynamic> p = jsonDecode(widget.program['json']);
    List<dynamic> stages = p['programStages'];

    // FILTER STAGES based on Rules and Access
    List<dynamic> allowedStages = stages.where((stage) {
      // 1. Check Write Access
      var access = stage['access'];
      if (access is Map && access['data'] != null) {
        if (access['data']['write'] == false) return false;
      }
      // 2. Check Rules (Is it hidden?)
      if (_hiddenStages.contains(stage['id'])) {
        return false;
      }
      return true;
    }).toList();

    if (allowedStages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No available stages to add.")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: allowedStages.map((stage) {
            return ListTile(
              title: Text(stage['name']),
              onTap: () async {
                Navigator.pop(context);
                await _pickDateAndOpenForm(stage);
              },
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _pickDateAndOpenForm(Map<String, dynamic> stage) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: "Select Event Date",
    );

    if (picked != null) {
      _openEventForm(stage, picked);
    }
  }

  void _openEventForm(Map<String, dynamic> stage, DateTime selectedDate) async {
    if (_enrollmentId == null) return;
    var ouRaw = await _dbHelper.getDefaultOrgUnit();
    String orgUnitId = ouRaw != null ? ouRaw['id'] : 'UserOrgUnit';

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventFormScreen(
          programId: widget.program['id'],
          stage: stage,
          enrollmentId: _enrollmentId!,
          orgUnit: orgUnitId,
          initialDate: selectedDate,
        ),
      ),
    );
    _loadEvents();
  }

  Widget _buildSyncIcon(String? statusRaw) {
    SyncStatus status = parseSyncStatus(statusRaw);
    if (status == SyncStatus.synced) return const SizedBox.shrink();

    Color color = Colors.blue;
    String text = "Not Synced";
    IconData icon = Icons.cloud_upload;

    if (status == SyncStatus.error) {
      color = Colors.red;
      text = "Sync Error";
      icon = Icons.error;
    }

    return Row(
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
    );
  }

  void _triggerSync() {
    SyncManager().startBackgroundSync();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Sync Started...")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Patient Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _triggerSync,
            tooltip: "Sync Now",
          ),
        ],
      ),
      body: Column(
        children: [
          if (_enrollment != null && _enrollment!['syncStatus'] != 'synced')
            Container(
              color: Colors.orange[50],
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 10),
                  const Text(
                    "Enrollment not synced",
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  _buildSyncIcon(_enrollment!['syncStatus']),
                ],
              ),
            ),

          Card(
            margin: const EdgeInsets.all(8.0),
            color: Colors.blue[50],
            elevation: 1,
            child: ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: const Text(
                "View / Edit Enrollment",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.blue,
              ),
              onTap: _viewEnrollment,
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              "History",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) {
                var event = _events[index];
                String date = event['eventDate'] ?? 'No Date';
                String orgUnit =
                    event['orgUnitName'] ??
                    event['orgUnit'] ??
                    'Unknown Facility';
                String stageName =
                    _stageNames[event['programStage']] ?? 'Unknown Stage';

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.history, color: Colors.white),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          date,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          orgUnit,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stageName,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildSyncIcon(event['syncStatus']),
                        ],
                      ),
                    ),
                    isThreeLine: true,
                    onTap: () => _onEventClick(event),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showStageSelection,
        label: const Text("Add New Event"),
        icon: const Icon(Icons.add),
      ),
    );
  }
}
