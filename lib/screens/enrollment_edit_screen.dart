import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/local/database_helper.dart';
import '../services/sync_manager.dart';
import '../services/rule_engine_service.dart'; // Import Rule Engine

class EnrollmentEditScreen extends StatefulWidget {
  final Map<String, dynamic> program;
  final String teiId;
  final String enrollmentId;
  final Map<String, dynamic> initialAttributes;

  const EnrollmentEditScreen({
    super.key,
    required this.program,
    required this.teiId,
    required this.enrollmentId,
    required this.initialAttributes,
  });

  @override
  State<EnrollmentEditScreen> createState() => _EnrollmentEditScreenState();
}

class _EnrollmentEditScreenState extends State<EnrollmentEditScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final RuleEngineService _ruleEngine = RuleEngineService(); // Engine
  final _formKey = GlobalKey<FormState>();

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _fieldDefinitions = {};
  final Map<String, List<dynamic>> _optionSetsMap = {};

  // Rule State
  final List<String> _hiddenFields = [];
  final List<String> _assignedFields = [];

  List<dynamic> _attributes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    await _loadOptionSets();
    _parseAttributes();
    // Run rules after data is loaded
    _runRules();
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

  void _parseAttributes() {
    try {
      Map<String, dynamic> p = jsonDecode(widget.program['json']);
      if (p.containsKey('programTrackedEntityAttributes')) {
        var pteas = p['programTrackedEntityAttributes'] as List;

        _attributes = pteas.map((ptea) {
          var tea = ptea['trackedEntityAttribute'];
          if (tea['valueType'] == null && ptea['valueType'] != null) {
            tea['valueType'] = ptea['valueType'];
          }
          if (tea['optionSet'] == null && ptea['optionSet'] != null) {
            tea['optionSet'] = ptea['optionSet'];
          }
          return tea;
        }).toList();

        for (var attr in _attributes) {
          String id = attr['id'];
          _fieldDefinitions[id] = attr;
          String initialValue = widget.initialAttributes[id] ?? '';
          _controllers[id] = TextEditingController(text: initialValue);
        }
      }
    } catch (e) {
      print("Error parsing attributes: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- RULE ENGINE LOGIC ---
  Future<void> _runRules() async {
    Map<String, dynamic> currentData = {};
    _controllers.forEach((id, controller) {
      currentData[id] = controller.text;
    });

    // For edits, we assume "today" or fetch existing enrollment date if available.
    // Using today for rule evaluation context.
    String evalDate = DateTime.now().toIso8601String().split('T')[0];

    List<RuleEffect> effects = await _ruleEngine.runRules(
      widget.program['id'],
      currentData,
      eventDate: evalDate,
    );

    if (!mounted) return;

    setState(() {
      _hiddenFields.clear();
      _assignedFields.clear();

      for (var effect in effects) {
        if (effect.action == 'HIDEFIELD' && effect.targetId != null) {
          _hiddenFields.add(effect.targetId!);
        } else if (effect.action == 'ASSIGN' && effect.targetId != null) {
          String? newValue = effect.data;
          if (newValue != null && _controllers.containsKey(effect.targetId)) {
            _assignedFields.add(effect.targetId!);
            if (_controllers[effect.targetId]!.text != newValue) {
              _controllers[effect.targetId]!.text = newValue;
            }
          }
        } else if (effect.action == 'SHOWWARNING' ||
            effect.action == 'SHOWERROR') {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(effect.content ?? "Validation Message"),
              backgroundColor: effect.action == 'SHOWERROR'
                  ? Colors.red
                  : Colors.orange,
            ),
          );
        }
      }
    });
  }
  // -------------------------

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
      setState(() => _controllers[id]?.text = formatted);
      _runRules();
    }
  }

  Widget _buildInputWidget(Map<String, dynamic> field) {
    String id = field['id'];
    if (_hiddenFields.contains(id)) {
      return const SizedBox.shrink();
    }

    String label =
        field['formName'] ??
        field['displayName'] ??
        field['name'] ??
        'Unknown Label';
    String valueType = (field['valueType'] ?? 'TEXT').toString().toUpperCase();
    bool isReadOnly = _assignedFields.contains(id);

    if (field['optionSet'] != null) {
      String optionSetId = field['optionSet']['id'];
      List<dynamic> options = _optionSetsMap[optionSetId] ?? [];
      return DropdownButtonFormField<String>(
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
      );
    }

    if (valueType == 'TRUE_ONLY') {
      bool isChecked = _controllers[id]?.text == 'true';
      return Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        setState(
                          () => _controllers[id]?.text = (val == true)
                              ? 'true'
                              : '',
                        );
                        _runRules();
                      },
              ),
            ),
          ],
        ),
      );
    }

    if (['BOOLEAN', 'YES_NO'].contains(valueType)) {
      return DropdownButtonFormField<String>(
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
      );
    }

    if (['DATE', 'DATETIME', 'AGE'].contains(valueType)) {
      return TextFormField(
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
      );
    }

    if ([
      'NUMBER',
      'INTEGER',
      'INTEGER_POSITIVE',
      'INTEGER_ZERO_OR_POSITIVE',
      'PHONE_NUMBER',
    ].contains(valueType)) {
      bool isDecimal = valueType == 'NUMBER';
      return TextFormField(
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
      );
    }

    return TextFormField(
      controller: _controllers[id],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        fillColor: isReadOnly ? Colors.grey[200] : null,
        filled: isReadOnly,
      ),
      readOnly: isReadOnly,
      onChanged: (_) => _runRules(),
    );
  }

  void _updateEnrollment() async {
    if (!_formKey.currentState!.validate()) return;

    var ouRaw = await _dbHelper.getDefaultOrgUnit();
    String orgUnitId = ouRaw != null ? ouRaw['id'] : 'UserOrgUnit';
    String date = DateTime.now().toIso8601String().split('T')[0];

    List<Map<String, dynamic>> attrValues = [];

    _controllers.forEach((id, controller) {
      if (controller.text.isNotEmpty && !_hiddenFields.contains(id)) {
        attrValues.add({
          'trackedEntityInstance': widget.teiId,
          'attribute': id,
          'value': controller.text,
        });
      }
    });

    Map<String, dynamic> teiData = {
      'trackedEntityInstance': widget.teiId,
      'trackedEntityType': 'Unknown',
      'orgUnit': orgUnitId,
      'syncStatus': 'to_post',
    };

    Map<String, dynamic> enrollmentData = {
      'enrollment': widget.enrollmentId,
      'trackedEntityInstance': widget.teiId,
      'program': widget.program['id'],
      'orgUnit': orgUnitId,
      'enrollmentDate': date,
      'status': 'ACTIVE',
      'syncStatus': 'to_post',
    };

    await _dbHelper.saveEnrollmentTransaction(
      teiData,
      enrollmentData,
      attrValues,
    );

    if (!mounted) return;
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
        title: const Text("Edit Enrollment"),
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
                  ..._attributes.map(
                    (attr) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildInputWidget(attr),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _updateEnrollment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Update Enrollment"),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
