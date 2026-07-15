import 'package:flutter/material.dart';
import '../data/local/database_helper.dart';
import 'event_form_screen.dart';
import '../services/sync_manager.dart';

class ViewEventScreen extends StatefulWidget {
  final Map<String, dynamic> program;
  final Map<String, dynamic> event;
  final Map<String, dynamic> stage;

  const ViewEventScreen({
    super.key,
    required this.program,
    required this.event,
    required this.stage,
  });

  @override
  State<ViewEventScreen> createState() => _ViewEventScreenState();
}

class _ViewEventScreenState extends State<ViewEventScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  Map<String, String> _dataValues = {};
  final Map<String, String> _elementLabels = {};
  final List<String> _elementOrder = [];

  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _parseMetadata();
    _loadDataValues();
  }

  void _parseMetadata() {
    try {
      Map<String, String> nameLookup = {};
      if (widget.stage['programStageDataElements'] != null) {
        for (var psde in widget.stage['programStageDataElements']) {
          var de = psde['dataElement'];
          String id = de['id'];
          String label =
              de['formName'] ?? de['displayName'] ?? de['name'] ?? 'Unknown';
          nameLookup[id] = label;
        }
      }

      if (widget.stage['programStageSections'] != null &&
          (widget.stage['programStageSections'] as List).isNotEmpty) {
        for (var sec in widget.stage['programStageSections']) {
          List<dynamic> elements = sec['dataElements'] ?? [];
          for (var de in elements) {
            String id = de['id'];
            String label = nameLookup[id] ?? 'Unknown Element';
            _elementLabels[id] = label;
            _elementOrder.add(id);
          }
        }
      } else {
        nameLookup.forEach((id, label) {
          _elementLabels[id] = label;
          _elementOrder.add(id);
        });
      }
    } catch (e) {
      print("Error parsing event metadata: $e");
    }
  }

  void _loadDataValues() async {
    String eventId = widget.event['event'];
    var valuesList = await _dbHelper.getDataValues(eventId);
    Map<String, String> valuesMap = {};
    for (var v in valuesList) {
      valuesMap[v['dataElement'] as String] = v['value'] as String;
    }
    if (mounted) {
      setState(() {
        _dataValues = valuesMap;
        _isLoading = false;
      });
    }
  }

  void _openEditScreen() async {
    bool? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventFormScreen(
          programId: widget.program['id'],
          stage: widget.stage,
          enrollmentId: widget.event['enrollment'],
          orgUnit: widget.event['orgUnit'],
          existingEventId: widget.event['event'],
        ),
      ),
    );

    if (result == true) {
      _hasChanges = true;
      _isLoading = true;
      setState(() {});
      _loadDataValues();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Event Updated")));
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
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.stage['name'] ?? "Event Details"),
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              onPressed: _triggerSync,
              tooltip: "Sync Now",
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: "Edit Event",
              onPressed: _openEditScreen,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Card(
                    color: Colors.blue[50],
                    child: ListTile(
                      title: Text(
                        "Date: ${widget.event['eventDate']}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text("Status: ${widget.event['status']}"),
                      trailing: const Icon(Icons.event),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Data Values",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  if (_dataValues.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text("No data entered for this event."),
                    )
                  else
                    ..._elementOrder.map((id) {
                      String label = _elementLabels[id] ?? id;
                      String value = _dataValues[id] ?? '';
                      if (value.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openEditScreen,
          icon: const Icon(Icons.edit),
          label: const Text("Edit Event"),
        ),
      ),
    );
  }
}
