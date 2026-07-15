import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; // Added Import
import '../data/local/database_helper.dart';
import 'registration_screen.dart';
import 'tei_dashboard_screen.dart';
import '../services/sync_manager.dart';

class SearchScreen extends StatefulWidget {
  final Map<String, dynamic> program;
  const SearchScreen({super.key, required this.program});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Map<String, TextEditingController> _controllers = {};

  List<dynamic> _searchableAttributes = [];
  List<String> _displayAttributeIds = [];

  // Stores ID -> Friendly Name (e.g. "C8n6..." -> "Age")
  final Map<String, String> _attributeLabels = {};

  List<Map<String, dynamic>> _searchResults = [];
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  void _loadMetadata() {
    try {
      Map<String, dynamic> p = jsonDecode(widget.program['json']);
      var attributes = p['programTrackedEntityAttributes'] as List;

      // 1. Identify Searchable Attributes
      _searchableAttributes = attributes.where((attr) {
        return attr['searchable'] == true;
      }).toList();

      for (var attr in _searchableAttributes) {
        _controllers[attr['trackedEntityAttribute']['id']] =
            TextEditingController();
      }

      // 2. Identify "Display In List" Attributes
      var displayAttrs = attributes.where((attr) {
        return attr['displayInList'] == true;
      }).toList();

      displayAttrs.sort(
        (a, b) => (a['sortOrder'] ?? 0).compareTo(b['sortOrder'] ?? 0),
      );

      _displayAttributeIds = displayAttrs
          .map((attr) => attr['trackedEntityAttribute']['id'] as String)
          .toList();

      // 3. Populate Label Map for ALL attributes (so we can resolve names even if not configured for display)
      for (var attr in attributes) {
        var tea = attr['trackedEntityAttribute'];
        String id = tea['id'];
        String label =
            tea['formName'] ?? tea['displayName'] ?? tea['name'] ?? id;
        _attributeLabels[id] = label;
      }
    } catch (e) {
      print("Error parsing metadata: $e");
    }
    setState(() {});
  }

  void _performSearch() async {
    Map<String, String> criteria = {};
    _controllers.forEach((id, controller) {
      if (controller.text.isNotEmpty) criteria[id] = controller.text;
    });

    if (criteria.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter at least one search criteria")),
      );
      return;
    }

    var results = await _dbHelper.searchTei(widget.program['id'], criteria);
    setState(() {
      _searchResults = results;
      _hasSearched = true;
    });
  }

  void _goToRegistration() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RegistrationScreen(program: widget.program),
      ),
    );
  }

  void _goToDashboard(Map<String, dynamic> teiData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeiDashboardScreen(
          program: widget.program,
          teiId: teiData['trackedEntityInstance'],
          attributes: teiData['attributes'],
        ),
      ),
    );
  }

  // Sync Trigger
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
        title: Text("Search ${widget.program['name']}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _triggerSync,
            tooltip: "Sync Now",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              "Please search for an existing client before registering.",
            ),
            const SizedBox(height: 10),

            ..._searchableAttributes.map((attr) {
              var tea = attr['trackedEntityAttribute'];
              String label =
                  tea['formName'] ?? tea['displayName'] ?? tea['name'];

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  controller: _controllers[tea['id']],
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
            }),

            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _performSearch,
              child: const Text("Search"),
            ),
            const Divider(),

            Expanded(
              child: _hasSearched && _searchResults.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // UPDATED: SVG Illustration for Empty State
                            SvgPicture.asset(
                              'assets/images/empty_state.svg',
                              height: 150,
                              placeholderBuilder: (BuildContext context) =>
                                  const Icon(
                                    Icons.search_off,
                                    size: 80,
                                    color: Colors.grey,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              "No clients found.",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.person_add),
                              label: const Text("Register New Client"),
                              onPressed: _goToRegistration,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        var item = _searchResults[index];
                        Map<String, dynamic> attrs = item['attributes'];

                        List<Widget> infoLines = [];
                        String titleText = "";

                        // 1. DETERMINE TITLE
                        if (_displayAttributeIds.isNotEmpty) {
                          List<String> parts = [];
                          for (var id in _displayAttributeIds) {
                            if (attrs.containsKey(id) &&
                                attrs[id] != null &&
                                attrs[id].toString().isNotEmpty) {
                              parts.add(attrs[id]);
                            }
                          }
                          titleText = parts.join(' ');
                        }

                        if (titleText.trim().isEmpty) {
                          // Try to find First Name / Last Name if config is missing
                          var names = attrs.entries
                              .where((e) {
                                String name = (_attributeLabels[e.key] ?? "")
                                    .toLowerCase();
                                return name.contains('name');
                              })
                              .map((e) => e.value)
                              .join(' ');

                          titleText = names.isNotEmpty ? names : "Client";
                        }

                        // 2. BUILD ATTRIBUTE LINES
                        int count = 0;
                        attrs.forEach((key, value) {
                          if (count < 4) {
                            String label = _attributeLabels[key] ?? key;

                            infoLines.add(
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2.0,
                                ),
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 14,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: "$label: ",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      TextSpan(text: "$value"),
                                    ],
                                  ),
                                ),
                              ),
                            );
                            count++;
                          }
                        });

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          child: InkWell(
                            onTap: () => _goToDashboard(item),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: Colors.blue,
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Header - Name
                                        Text(
                                          titleText,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // Dynamic Lines
                                        ...infoLines,
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
