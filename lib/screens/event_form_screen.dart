import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/local/database_helper.dart';
import '../core/sync_state.dart';
import '../services/sync_manager.dart';
import '../services/rule_engine_service.dart'; // Import Rule Engine

class EventFormScreen extends StatefulWidget {
  final String programId;
  final Map<String, dynamic> stage;
  final String enrollmentId;
  final String orgUnit;
  final String? existingEventId;
  final DateTime? initialDate;

  const EventFormScreen({
    super.key,
    required this.programId,
    required this.stage,
    required this.enrollmentId,
    required this.orgUnit,
    this.existingEventId,
    this.initialDate,
  });

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final RuleEngineService _ruleEngine = RuleEngineService();
  final _formKey = GlobalKey<FormState>();

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, List<dynamic>> _optionSetsMap = {};

  // Rule State
  final List<String> _hiddenFields = [];
  final List<String> _assignedFields = [];

  // Context for Rules (Attributes)
  Map<String, dynamic> _teiAttributes = {};

  List<dynamic> _sections = [];
  final List<dynamic> _flatDataElements = [];
  final Map<String, dynamic> _elementDefinitions = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    if (widget.existingEventId != null) {
      _checkConflicts();
    }
  }

  void _loadData() async {
    await _loadOptionSets();
    await _loadTeiAttributes(); // Fetch context (Attributes)
    _loadForm();
    if (widget.existingEventId != null) {
      await _loadExistingValues();
    }
    // Run rules after data load
    await _runRules();
    setState(() => _isLoading = false);
  }

  // --- 1. LOAD ATTRIBUTES FOR RULE CONTEXT ---
  Future<void> _loadTeiAttributes() async {
    // We need the TEI ID to find attributes. We get it from the Enrollment.
    var enrollment = await _dbHelper.getEnrollmentById(widget.enrollmentId);
    if (enrollment != null) {
      String teiId = enrollment['trackedEntityInstance'];
      var attrs = await _dbHelper.getTeiAttributes(teiId);
      setState(() {
        _teiAttributes = attrs;
      });
    }
  }

  // --- 2. UPDATED RULE ENGINE LOGIC ---
  Future<void> _runRules() async {
    // A. Start with Attributes (so rules like "A{sex} == Male" work)
    Map<String, dynamic> currentData = Map.from(_teiAttributes);

    // B. Add current Form Data (Data Elements)
    _controllers.forEach((id, controller) {
      currentData[id] = controller.text;
    });

    // C. Determine Event Date
    String evDate;
    if (widget.existingEventId != null) {
      // Ideally fetch from DB, but for rule context, today or initial is fine if not editing date
      evDate = DateTime.now().toIso8601String().split('T')[0];
    } else {
      evDate = (widget.initialDate ?? DateTime.now()).toIso8601String().split(
        'T',
      )[0];
    }

    // D. Execute Rules
    List<RuleEffect> effects = await _ruleEngine.runRules(
      widget.programId,
      currentData,
      eventDate: evDate,
      orgUnit: widget.orgUnit,
      // IMPORTANT: Pass the Stage ID so event rules run!
      programStageId: widget.stage['id'],
    );

    if (!mounted) return;

    setState(() {
      _hiddenFields.clear();
      _assignedFields.clear();

      for (var effect in effects) {
        // HIDEFIELD
        if (effect.action == 'HIDEFIELD' && effect.targetId != null) {
          _hiddenFields.add(effect.targetId!);
        }
        // ASSIGN
        else if (effect.action == 'ASSIGN' && effect.targetId != null) {
          String? newValue = effect.data;
          if (newValue != null && _controllers.containsKey(effect.targetId)) {
            _assignedFields.add(effect.targetId!); // Mark as Read-Only
            if (_controllers[effect.targetId]!.text != newValue) {
              _controllers[effect.targetId]!.text = newValue;
            }
          }
        }
        // WARNINGS / ERRORS
        else if (effect.action == 'SHOWWARNING' ||
            effect.action == 'SHOWERROR') {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(effect.content ?? "Validation Message"),
              backgroundColor: effect.action == 'SHOWERROR'
                  ? Colors.red
                  : Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }
  // -------------------------------

  void _checkConflicts() async {
    var conflict = await _dbHelper.getConflict(widget.existingEventId!);
    if (conflict != null && mounted) {
      _showConflictDialog(conflict['errorMessage'], conflict['serverPayload']);
    }
  }

  void _showConflictDialog(String msg, String details) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sync Error"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("Server Details:", style: TextStyle(fontSize: 12)),
              Text(
                details,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text("I fixed it"),
            onPressed: () async {
              await _dbHelper.resolveConflict(widget.existingEventId!);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadOptionSets() async {
    var sets = await _dbHelper.getOptionSets();
    for (var s in sets) {
      String id = s['id'] as String;
      String json = s['options'] as String;
      List<dynamic> options = jsonDecode(json);
      setState(() {
        _optionSetsMap[id] = options;
      });
    }
  }

  Future<void> _loadExistingValues() async {
    var values = await _dbHelper.getDataValues(widget.existingEventId!);
    for (var v in values) {
      String deId = v['dataElement'];
      String val = v['value'];
      if (_controllers.containsKey(deId)) {
        _controllers[deId]?.text = val;
      }
    }
  }

  void _loadForm() {
    if (widget.stage['programStageDataElements'] != null) {
      for (var psde in widget.stage['programStageDataElements']) {
        var de = psde['dataElement'];
        _elementDefinitions[de['id']] = de;
        _controllers[de['id']] = TextEditingController();
      }
    }

    if (widget.stage['programStageSections'] != null &&
        (widget.stage['programStageSections'] as List).isNotEmpty) {
      _sections = widget.stage['programStageSections'];
    } else {
      if (widget.stage['programStageDataElements'] != null) {
        for (var psde in widget.stage['programStageDataElements']) {
          var de = psde['dataElement'];
          _flatDataElements.add(de);
        }
      }
    }

    if (_sections.isNotEmpty) {
      for (var sec in _sections) {
        List<dynamic> elements = sec['dataElements'] ?? [];
        for (var de in elements) {
          String id = de['id'];
          if (!_controllers.containsKey(id)) {
            _controllers[id] = TextEditingController();
          }
        }
      }
    }
  }

  Future<void> _pickDate(String id) async {
    if (_assignedFields.contains(id)) return;

    FocusScope.of(context).requestFocus(FocusNode());
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      String formatted = picked.toIso8601String().split('T')[0];
      _controllers[id]?.text = formatted;
      _runRules();
    }
  }

  Widget _buildInputWidget(String dataElementId) {
    if (_hiddenFields.contains(dataElementId)) {
      return const SizedBox.shrink();
    }

    var field = _elementDefinitions[dataElementId];
    if (field == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(
          "Missing Meta: $dataElementId",
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    String id = field['id'];
    String label =
        field['formName'] ?? field['displayName'] ?? field['name'] ?? id;
    String valueType = (field['valueType'] ?? 'TEXT').toString().toUpperCase();
    bool isReadOnly = _assignedFields.contains(id);

    // Option Sets
    if (field['optionSet'] != null) {
      String optionSetId = field['optionSet']['id'];
      List<dynamic> options = _optionSetsMap[optionSetId] ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: DropdownButtonFormField<String>(
          initialValue: _controllers[id]?.text.isEmpty ?? true
              ? null
              : _controllers[id]?.text,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            fillColor: isReadOnly ? Colors.grey[200] : null,
            filled: isReadOnly,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Select...')),
            for (var opt in options)
              DropdownMenuItem(
                value: opt['code'] ?? opt['name'],
                child: Text(opt['name']),
              ),
          ],
          onChanged: isReadOnly
              ? null
              : (val) {
                  _controllers[id]?.text = val ?? '';
                  _runRules();
                },
        ),
      );
    }

    // CHECKBOXES (True Only) - Clean UI
    if (valueType == 'TRUE_ONLY') {
      bool isChecked = _controllers[id]?.text == 'true';
      return Container(
        margin: const EdgeInsets.only(bottom: 8.0, top: 4.0),
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ),
            Transform.scale(
              scale: 1.1,
              child: Checkbox(
                value: isChecked,
                activeColor: Colors.blue,
                onChanged: isReadOnly
                    ? null
                    : (val) {
                        setState(() {
                          _controllers[id]?.text = (val == true) ? 'true' : '';
                        });
                        _runRules();
                      },
              ),
            ),
          ],
        ),
      );
    }

    // Boolean
    if (['BOOLEAN', 'YES_NO'].contains(valueType)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: DropdownButtonFormField<String>(
          initialValue: _controllers[id]?.text.isEmpty ?? true
              ? null
              : _controllers[id]?.text,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            fillColor: isReadOnly ? Colors.grey[200] : null,
            filled: isReadOnly,
          ),
          items: const [
            DropdownMenuItem(value: 'true', child: Text('Yes')),
            DropdownMenuItem(value: 'false', child: Text('No')),
          ],
          onChanged: isReadOnly
              ? null
              : (val) {
                  _controllers[id]?.text = val ?? '';
                  _runRules();
                },
        ),
      );
    }

    // Date
    if (['DATE', 'DATETIME'].contains(valueType)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: TextFormField(
          controller: _controllers[id],
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today),
            fillColor: isReadOnly ? Colors.grey[200] : null,
            filled: isReadOnly,
          ),
          readOnly: true,
          onTap: () => _pickDate(id),
        ),
      );
    }

    // Numbers
    if ([
      'NUMBER',
      'INTEGER',
      'INTEGER_POSITIVE',
      'INTEGER_ZERO_OR_POSITIVE',
    ].contains(valueType)) {
      bool isDecimal = valueType == 'NUMBER';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: TextFormField(
          controller: _controllers[id],
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            fillColor: isReadOnly ? Colors.grey[200] : null,
            filled: isReadOnly,
          ),
          readOnly: isReadOnly,
          keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(isDecimal ? r'[0-9.]' : r'[0-9-]'),
            ),
          ],
          onChanged: (_) => _runRules(),
        ),
      );
    }

    // Long Text
    if (valueType == 'LONG_TEXT') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: TextFormField(
          controller: _controllers[id],
          maxLines: 3,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            fillColor: isReadOnly ? Colors.grey[200] : null,
            filled: isReadOnly,
          ),
          readOnly: isReadOnly,
          onChanged: (_) => _runRules(),
        ),
      );
    }

    // Default
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: _controllers[id],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          fillColor: isReadOnly ? Colors.grey[200] : null,
          filled: isReadOnly,
        ),
        readOnly: isReadOnly,
        onChanged: (_) => _runRules(),
      ),
    );
  }

  Widget _buildSection(dynamic section) {
    String title = section['displayName'] ?? 'Section';
    List<dynamic> elements = section['dataElements'] ?? [];
    if (elements.isEmpty) return const SizedBox.shrink();

    bool allHidden = elements.every((e) => _hiddenFields.contains(e['id']));
    if (allHidden) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 20.0),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            color: Colors.blue[50],
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: elements.map((e) {
                return _buildInputWidget(e['id']);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    String eventId =
        widget.existingEventId ??
        List.generate(
          11,
          (i) =>
              'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[Random()
                  .nextInt(62)],
        ).join();

    String dateStr;
    if (widget.existingEventId != null) {
      dateStr = DateTime.now().toIso8601String().split('T')[0];
    } else {
      dateStr = (widget.initialDate ?? DateTime.now()).toIso8601String().split(
        'T',
      )[0];
    }

    SyncStatus status = widget.existingEventId != null
        ? SyncStatus.toUpdate
        : SyncStatus.toPost;

    Map<String, dynamic> eventData = {
      'event': eventId,
      'enrollment': widget.enrollmentId,
      'program': widget.programId,
      'programStage': widget.stage['id'],
      'orgUnit': widget.orgUnit,
      'eventDate': dateStr,
      'status': 'COMPLETED',
      'syncStatus': syncStatusToString(status),
    };

    List<Map<String, dynamic>> dataValues = [];
    _controllers.forEach((id, controller) {
      if (controller.text.isNotEmpty && !_hiddenFields.contains(id)) {
        dataValues.add({
          'event': eventId,
          'dataElement': id,
          'value': controller.text,
        });
      }
    });

    await _dbHelper.saveEventTransaction(eventData, dataValues);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.existingEventId != null ? 'Event Updated!' : 'Event Saved!',
        ),
      ),
    );
    Navigator.pop(context, true);
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
        title: Text(widget.stage['name'] ?? 'Event Entry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _triggerSync,
            tooltip: "Sync Now",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  if (widget.initialDate != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        "Event Date: ${widget.initialDate!.toIso8601String().split('T')[0]}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),

                  if (_sections.isNotEmpty)
                    ..._sections.map((sec) => _buildSection(sec))
                  else
                    ..._flatDataElements.map(
                      (de) => _buildInputWidget(de['id']),
                    ),

                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saveEvent,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      widget.existingEventId != null
                          ? "Update Event"
                          : "Save Event",
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
