import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../core/sync_state.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'dhis2_offline.db');
    return await openDatabase(
      path,
      version: 6, // INCREMENTED VERSION
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _createAllTables(db);
    // Add columns if missing in older versions (basic logic)
    if (oldVersion < 6) {
      // Re-creating program_rules is safer since we just sync it
      await db.execute("DROP TABLE IF EXISTS program_rules");
      await db.execute(
        'CREATE TABLE IF NOT EXISTS program_rules (id TEXT PRIMARY KEY, programId TEXT, programStageId TEXT, priority INTEGER, condition TEXT, actions JSON)',
      );
    }
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS user (id TEXT PRIMARY KEY, username TEXT, firstName TEXT, surname TEXT, password TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS user_roles (id TEXT PRIMARY KEY, userId TEXT, name TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS user_groups (id TEXT PRIMARY KEY, userId TEXT, name TEXT)',
    );

    await db.execute(
      'CREATE TABLE IF NOT EXISTS organisation_units (id TEXT PRIMARY KEY, name TEXT, level INTEGER, parent TEXT, path TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS option_sets (id TEXT PRIMARY KEY, name TEXT, options JSON)',
    );
    // UPDATED: Added programStageId
    await db.execute(
      'CREATE TABLE IF NOT EXISTS program_rules (id TEXT PRIMARY KEY, programId TEXT, programStageId TEXT, priority INTEGER, condition TEXT, actions JSON)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS program_rule_variables (id TEXT PRIMARY KEY, programId TEXT, name TEXT, dataElement TEXT, trackedEntityAttribute TEXT, sourceType TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS programs (id TEXT PRIMARY KEY, name TEXT, json JSON)',
    );

    await db.execute(
      'CREATE TABLE IF NOT EXISTS tracked_entity_instances (trackedEntityInstance TEXT PRIMARY KEY, trackedEntityType TEXT, orgUnit TEXT, syncStatus TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS tracked_entity_attributes (id INTEGER PRIMARY KEY AUTOINCREMENT, trackedEntityInstance TEXT, attribute TEXT, value TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS enrollments (enrollment TEXT PRIMARY KEY, trackedEntityInstance TEXT, program TEXT, orgUnit TEXT, enrollmentDate TEXT, status TEXT, syncStatus TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS events (event TEXT PRIMARY KEY, enrollment TEXT, program TEXT, programStage TEXT, orgUnit TEXT, eventDate TEXT, status TEXT, syncStatus TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS data_values (id INTEGER PRIMARY KEY AUTOINCREMENT, event TEXT, dataElement TEXT, value TEXT)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS sync_conflicts (id INTEGER PRIMARY KEY AUTOINCREMENT, resourceType TEXT, resourceId TEXT, errorCode TEXT, errorMessage TEXT, serverPayload TEXT, createdAt TEXT)',
    );
  }

  // --- METHODS ---

  Future<void> saveUser(Map<String, dynamic> user, String password) async {
    final db = await database;
    await db.transaction((txn) async {
      String userId = user['id'];
      await txn.insert('user', {
        'id': userId,
        'username': user['userCredentials']['username'],
        'firstName': user['firstName'],
        'surname': user['surname'],
        'password': password,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete('user_roles', where: 'userId = ?', whereArgs: [userId]);
      await txn.delete('user_groups', where: 'userId = ?', whereArgs: [userId]);

      List<dynamic> roles = user['userCredentials']['userRoles'] ?? [];
      for (var role in roles) {
        await txn.insert('user_roles', {
          'id': role['id'],
          'userId': userId,
          'name': role['name'],
        });
      }
      List<dynamic> groups = user['userGroups'] ?? [];
      for (var group in groups) {
        await txn.insert('user_groups', {
          'id': group['id'],
          'userId': userId,
          'name': group['name'],
        });
      }
    });
  }

  Future<Map<String, dynamic>?> getUser() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('user');
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<Map<String, dynamic>?> getDefaultOrgUnit() async {
    final db = await database;
    List<Map<String, dynamic>> res = await db.query(
      'organisation_units',
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<void> saveMetadata(
    List<dynamic> programs,
    List<dynamic> orgUnits,
    List<dynamic> optionSets,
    List<dynamic> rules,
    List<dynamic> ruleVariables,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var p in programs) {
        await txn.insert('programs', {
          'id': p['id'],
          'name': p['name'],
          'json': jsonEncode(p),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (var ou in orgUnits) {
        await txn.insert('organisation_units', {
          'id': ou['id'],
          'name': ou['name'],
          'level': ou['level'],
          'parent': ou['parent']?['id'],
          'path': ou['path'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (var os in optionSets) {
        await txn.insert('option_sets', {
          'id': os['id'],
          'name': os['name'],
          'options': jsonEncode(os['options']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (var r in rules) {
        // UPDATED: Save programStageId
        await txn.insert('program_rules', {
          'id': r['id'],
          'programId': r['program']?['id'],
          'programStageId': r['programStage']?['id'], // Saves Stage ID or Null
          'priority': r['priority'],
          'condition': r['condition'],
          'actions': jsonEncode(r['programRuleActions']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (var rv in ruleVariables) {
        await txn.insert('program_rule_variables', {
          'id': rv['id'],
          'programId': rv['program']?['id'],
          'name': rv['name'],
          'dataElement': rv['dataElement']?['id'],
          'trackedEntityAttribute': rv['trackedEntityAttribute']?['id'],
          'sourceType': rv['programRuleVariableSourceType'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getPrograms() async {
    final db = await database;
    return await db.query('programs');
  }

  Future<List<Map<String, dynamic>>> getOptionSets() async {
    final db = await database;
    return await db.query('option_sets');
  }

  Future<void> saveServerTeis(List<dynamic> teis) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var tei in teis) {
        String teiId = tei['trackedEntityInstance'];
        await txn.insert('tracked_entity_instances', {
          'trackedEntityInstance': teiId,
          'trackedEntityType': tei['trackedEntityType'],
          'orgUnit': tei['orgUnit'],
          'syncStatus': 'synced',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete(
          'tracked_entity_attributes',
          where: 'trackedEntityInstance = ?',
          whereArgs: [teiId],
        );
        List<dynamic> attrs = tei['attributes'] ?? [];
        for (var attr in attrs) {
          await txn.insert('tracked_entity_attributes', {
            'trackedEntityInstance': teiId,
            'attribute': attr['attribute'],
            'value': attr['value'],
          });
        }
        List<dynamic> enrollments = tei['enrollments'] ?? [];
        for (var enr in enrollments) {
          String enrId = enr['enrollment'];
          await txn.insert('enrollments', {
            'enrollment': enrId,
            'trackedEntityInstance': teiId,
            'program': enr['program'],
            'orgUnit': enr['orgUnit'],
            'enrollmentDate': enr['enrollmentDate'],
            'status': enr['status'],
            'syncStatus': 'synced',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          List<dynamic> events = enr['events'] ?? [];
          for (var evt in events) {
            String evtId = evt['event'];
            await txn.insert('events', {
              'event': evtId,
              'enrollment': enrId,
              'program': evt['program'],
              'programStage': evt['programStage'],
              'orgUnit': evt['orgUnit'],
              'eventDate': evt['eventDate'],
              'status': evt['status'],
              'syncStatus': 'synced',
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            await txn.delete(
              'data_values',
              where: 'event = ?',
              whereArgs: [evtId],
            );
            List<dynamic> dvs = evt['dataValues'] ?? [];
            for (var dv in dvs) {
              await txn.insert('data_values', {
                'event': evtId,
                'dataElement': dv['dataElement'],
                'value': dv['value'],
              });
            }
          }
        }
      }
    });
  }

  Future<void> saveEnrollmentTransaction(
    Map<String, dynamic> tei,
    Map<String, dynamic> enrollment,
    List<Map<String, dynamic>> attributes,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'tracked_entity_instances',
        tei,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'enrollments',
        enrollment,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'tracked_entity_attributes',
        where: 'trackedEntityInstance = ?',
        whereArgs: [tei['trackedEntityInstance']],
      );
      for (var attr in attributes) {
        await txn.insert('tracked_entity_attributes', attr);
      }
    });
  }

  Future<void> saveEventTransaction(
    Map<String, dynamic> event,
    List<Map<String, dynamic>> dataValues,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      String eventId = event['event'];
      await txn.insert(
        'events',
        event,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('data_values', where: 'event = ?', whereArgs: [eventId]);
      for (var dv in dataValues) {
        await txn.insert(
          'data_values',
          dv,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> searchTei(
    String programId,
    Map<String, String> searchCriteria,
  ) async {
    final db = await database;
    if (searchCriteria.isEmpty) return [];
    String sql = '''
      SELECT DISTINCT t.trackedEntityInstance, t.orgUnit 
      FROM tracked_entity_instances t
      JOIN enrollments e ON t.trackedEntityInstance = e.trackedEntityInstance
      WHERE e.program = ?
    ''';
    List<dynamic> args = [programId];
    for (var entry in searchCriteria.entries) {
      sql += '''
        AND t.trackedEntityInstance IN (
          SELECT trackedEntityInstance FROM tracked_entity_attributes 
          WHERE attribute = ? AND value LIKE ?
        )
      ''';
      args.add(entry.key);
      args.add('%${entry.value}%');
    }
    List<Map<String, dynamic>> rawResults = await db.rawQuery(sql, args);
    List<Map<String, dynamic>> fullResults = [];
    for (var row in rawResults) {
      String teiId = row['trackedEntityInstance'];
      Map<String, dynamic> attrMap = await getTeiAttributes(teiId);
      fullResults.add({
        'trackedEntityInstance': teiId,
        'orgUnit': row['orgUnit'],
        'attributes': attrMap,
      });
    }
    return fullResults;
  }

  Future<Map<String, dynamic>> getTeiAttributes(String teiId) async {
    final db = await database;
    var result = await db.query(
      'tracked_entity_attributes',
      where: 'trackedEntityInstance = ?',
      whereArgs: [teiId],
    );
    Map<String, dynamic> attrs = {};
    for (var row in result) {
      attrs[row['attribute'] as String] = row['value'];
    }
    return attrs;
  }

  Future<List<Map<String, dynamic>>> getPendingEvents() async {
    final db = await database;
    return await db.query(
      'events',
      where: 'syncStatus IN (?, ?)',
      whereArgs: ['to_post', 'to_update'],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingEnrollments() async {
    final db = await database;
    return await db.query(
      'enrollments',
      where: 'syncStatus IN (?, ?)',
      whereArgs: ['to_post', 'to_update'],
    );
  }

  Future<List<Map<String, dynamic>>> getAllPendingEvents() async {
    final db = await database;
    return await db.query(
      'events',
      where: 'syncStatus != ?',
      whereArgs: ['synced'],
    );
  }

  Future<List<Map<String, dynamic>>> getAllPendingEnrollments() async {
    final db = await database;
    return await db.query(
      'enrollments',
      where: 'syncStatus != ?',
      whereArgs: ['synced'],
    );
  }

  Future<List<Map<String, dynamic>>> getDataValues(String eventId) async {
    final db = await database;
    return await db.query(
      'data_values',
      where: 'event = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> updateSyncStatus(
    String table,
    String idColumn,
    String id,
    SyncStatus status,
  ) async {
    final db = await database;
    await db.update(
      table,
      {'syncStatus': syncStatusToString(status)},
      where: '$idColumn = ?',
      whereArgs: [id],
    );
  }

  Future<void> markEventSynced(String eventId) async {
    await updateSyncStatus('events', 'event', eventId, SyncStatus.synced);
  }

  Future<void> markEnrollmentSynced(String enrollmentId) async {
    await updateSyncStatus(
      'enrollments',
      'enrollment',
      enrollmentId,
      SyncStatus.synced,
    );
    final db = await database;
    var enr = await db.query(
      'enrollments',
      columns: ['trackedEntityInstance'],
      where: 'enrollment = ?',
      whereArgs: [enrollmentId],
    );
    if (enr.isNotEmpty) {
      String teiId = enr.first['trackedEntityInstance'] as String;
      await db.update(
        'tracked_entity_instances',
        {'syncStatus': 'synced'},
        where: 'trackedEntityInstance = ?',
        whereArgs: [teiId],
      );
    }
  }

  Future<void> saveConflict(
    String resourceType,
    String resourceId,
    String errorMsg,
    String payload,
  ) async {
    final db = await database;
    await db.insert('sync_conflicts', {
      'resourceType': resourceType,
      'resourceId': resourceId,
      'errorCode': '409',
      'errorMessage': errorMsg,
      'serverPayload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });
    String table = resourceType == 'event' ? 'events' : 'enrollments';
    String idCol = resourceType == 'event' ? 'event' : 'enrollment';
    await updateSyncStatus(table, idCol, resourceId, SyncStatus.error);
  }

  Future<Map<String, dynamic>?> getConflict(String resourceId) async {
    final db = await database;
    List<Map<String, dynamic>> res = await db.query(
      'sync_conflicts',
      where: 'resourceId = ?',
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<void> resolveConflict(String resourceId) async {
    final db = await database;
    await db.delete(
      'sync_conflicts',
      where: 'resourceId = ?',
      whereArgs: [resourceId],
    );
    var evt = await db.query(
      'events',
      where: 'event = ?',
      whereArgs: [resourceId],
    );
    if (evt.isNotEmpty) {
      await updateSyncStatus(
        'events',
        'event',
        resourceId,
        SyncStatus.toUpdate,
      );
    } else {
      await updateSyncStatus(
        'enrollments',
        'enrollment',
        resourceId,
        SyncStatus.toUpdate,
      );
    }
  }

  Future<String> getTeiTypeFromProgram(String programId) async {
    final db = await database;
    var res = await db.query(
      'programs',
      where: 'id = ?',
      whereArgs: [programId],
    );
    if (res.isNotEmpty) {
      try {
        var json = jsonDecode(res.first['json'] as String);
        return json['trackedEntityType']?['id'] ?? 'Unknown';
      } catch (e) {
        return 'Unknown';
      }
    }
    return 'Unknown';
  }

  Future<Map<String, dynamic>?> getEnrollment(
    String teiId,
    String programId,
  ) async {
    final db = await database;
    var res = await db.query(
      'enrollments',
      where: 'trackedEntityInstance = ? AND program = ?',
      whereArgs: [teiId, programId],
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<Map<String, dynamic>?> getEnrollmentById(String enrollmentId) async {
    final db = await database;
    var res = await db.query(
      'enrollments',
      where: 'enrollment = ?',
      whereArgs: [enrollmentId],
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<List<Map<String, dynamic>>> getEvents(String enrollmentId) async {
    final db = await database;
    return await db.rawQuery(
      'SELECT e.*, o.name as orgUnitName FROM events e LEFT JOIN organisation_units o ON e.orgUnit = o.id WHERE e.enrollment = ? ORDER BY e.eventDate DESC',
      [enrollmentId],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedEvents() async {
    final db = await database;
    return await db.query(
      'events',
      where: 'syncStatus = ?',
      whereArgs: ['to_post'],
    );
  }

  Future<void> resetDatabase() async {
    final db = await database;
    await db.delete('user');
    await db.delete('user_roles');
    await db.delete('user_groups');
    await db.delete('programs');
    await db.delete('organisation_units');
    await db.delete('option_sets');
    await db.delete('program_rules');
    await db.delete('program_rule_variables');
    await db.delete('tracked_entity_instances');
    await db.delete('tracked_entity_attributes');
    await db.delete('enrollments');
    await db.delete('events');
    await db.delete('data_values');
    await db.delete('sync_conflicts');
  }
}
