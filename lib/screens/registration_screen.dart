import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/local/database_helper.dart';
import 'tei_dashboard_screen.dart';
import '../services/sync_manager.dart';
import '../services/rule_engine_service.dart';

class RegistrationScreen extends StatefulWidget {
  final Map<String, dynamic> program;
  const RegistrationScreen({super.key, required this.program});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final RuleEngineService _ruleEngine = RuleEngineService();
  final _formKey = GlobalKey<FormState>();

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, List<dynamic>> _optionSetsMap = {};

  final List<String> _hiddenFields = [];
  final List<String> _hiddenSections = []; // NEW: Track hidden sections
  final List<String> _assignedFields = [];

  DateTime _enrollmentDate = DateTime.now();
  String _orgUnitName = "Loading...";
  String _orgUnitId = "";

  List<dynamic> _attributes = [];
  // NEW: Map Attribute ID -> Section ID
  final Map<String, String> _attributeSectionMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    await _loadOrgUnit();
    await _loadOptionSets();
    _parseAttributes();
    _runRules();
  }

  // --- RULE LOGIC ---
  Future<void> _runRules() async {
    Map<String, dynamic> currentData = {};
    _controllers.forEach((id, controller) {
      currentData[id] = controller.text;
    });

    List<RuleEffect> effects = await _ruleEngine.runRules(
      widget.program['id'],
      currentData,
      eventDate: _enrollmentDate.toIso8601String().split('T')[0],
      orgUnit: _orgUnitId,
      programStageId: null,
    );

    if (!mounted) return;

    setState(() {
      _hiddenFields.clear();
      _hiddenSections.clear(); // Reset sections
      _assignedFields.clear();

      for (var effect in effects) {
        if (effect.action == 'HIDEFIELD' && effect.targetId != null) {
          _hiddenFields.add(effect.targetId!);
        }
        // Handle HIDESECTION
        else if (effect.action == 'HIDESECTION' && effect.targetId != null) {
          _hiddenSections.add(effect.targetId!);
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
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  Future<void> _loadOrgUnit() async {
    var ou = await _dbHelper.getDefaultOrgUnit();
    if (ou != null) {
      setState(() {
        _orgUnitName = ou['name'];
        _orgUnitId = ou['id'];
      });
    } else {
      setState(() {
        _orgUnitName = "User Org Unit";
        _orgUnitId = "UserOrgUnit";
      });
    }
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

      // 1. Map Attributes to Sections (if sections exist)
      if (p.containsKey('programSections')) {
        var sections = p['programSections'] as List;
        for (var sec in sections) {
          String secId = sec['id'];
          List<dynamic> trackdedEntityAttributes =
              sec['trackedEntityAttributes'] ?? [];
          for (var tea in trackdedEntityAttributes) {
            _attributeSectionMap[tea['id']] = secId;
          }
        }
      }

      // 2. Parse Attributes
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
          _controllers[id] = TextEditingController();
        }
      }
    } catch (e) {
      print("Error parsing attributes: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickEnrollmentDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _enrollmentDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _enrollmentDate = picked;
      });
      _runRules();
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
      setState(() => _controllers[id]?.text = formatted);
      _runRules();
    }
  }

  Widget _buildInputWidget(Map<String, dynamic> field) {
    String id = field['id'];

    // RULE 1: Hide Field directly
    if (_hiddenFields.contains(id)) return const SizedBox.shrink();

    // RULE 2: Hide Field if its Section is hidden
    String? sectionId = _attributeSectionMap[id];
    if (sectionId != null && _hiddenSections.contains(sectionId)) {
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

    if (['DATE', 'DATETIME', 'AGE'].contains(valueType)) {
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

    if ([
      'NUMBER',
      'INTEGER',
      'INTEGER_POSITIVE',
      'INTEGER_ZERO_OR_POSITIVE',
      'PHONE_NUMBER',
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

  void _saveAndContinue() async {
    if (!_formKey.currentState!.validate()) return;

    String teiId = List.generate(
      11,
      (i) =>
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[Random()
              .nextInt(62)],
    ).join();
    String enrollmentId = List.generate(
      11,
      (i) =>
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[Random()
              .nextInt(62)],
    ).join();
    String date = _enrollmentDate.toIso8601String().split('T')[0];

    String teiType = await _dbHelper.getTeiTypeFromProgram(
      widget.program['id'],
    );

    List<Map<String, dynamic>> attrValues = [];
    Map<String, dynamic> attrMapForDash = {};

    _controllers.forEach((id, controller) {
      if (controller.text.isNotEmpty && !_hiddenFields.contains(id)) {
        attrValues.add({
          'trackedEntityInstance': teiId,
          'attribute': id,
          'value': controller.text,
        });
        attrMapForDash[id] = controller.text;
      }
    });

    Map<String, dynamic> teiData = {
      'trackedEntityInstance': teiId,
      'trackedEntityType': teiType,
      'orgUnit': _orgUnitId,
      'syncStatus': 'to_post',
    };

    Map<String, dynamic> enrollmentData = {
      'enrollment': enrollmentId,
      'trackedEntityInstance': teiId,
      'program': widget.program['id'],
      'orgUnit': _orgUnitId,
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => TeiDashboardScreen(
          program: widget.program,
          teiId: teiId,
          attributes: attrMapForDash,
        ),
      ),
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
        title: const Text("New Registration"),
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
                  Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Registration Details",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const Divider(),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.grey),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Organization Unit",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      _orgUnitName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _pickEnrollmentDate,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Enrollment Date",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      Text(
                                        _enrollmentDate.toIso8601String().split(
                                          'T',
                                        )[0],
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Text(
                    "Client Profile",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ..._attributes.map((attr) => _buildInputWidget(attr)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveAndContinue,
                      child: const Text("Register New Client"),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
