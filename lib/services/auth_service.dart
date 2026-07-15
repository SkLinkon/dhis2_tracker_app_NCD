import 'package:dio/dio.dart';
import '../core/dhis_client.dart';
import '../data/local/database_helper.dart';

class AuthService {
  final DhisClient _client = DhisClient();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Returns true if login successful, false otherwise.
  Future<bool> login(String username, String password) async {
    try {
      // 1. Create the Basic Auth Token
      String authHeader = _client.getBasicAuth(username, password);

      // 2. Call DHIS2 /api/me endpoint
      // WE MUST REQUEST FIELDS: userRoles and userGroups to match DatabaseHelper expectations
      String fields =
          'id,username,firstName,surname,userCredentials[username,userRoles[id,name]],userGroups[id,name]';

      Response response = await _client.dio.get(
        '/api/me',
        queryParameters: {'fields': fields},
        options: Options(headers: {'Authorization': authHeader}),
      );

      if (response.statusCode == 200) {
        // 3. Login Successful - Save User AND Roles/Groups to Local SQLite DB
        print("Login Successful. Saving user data...");

        // CRITICAL: We await this to ensure data is committed before returning true
        await _dbHelper.saveUser(response.data, password);

        // Verify the save worked immediately (Double-check)
        final savedUser = await _dbHelper.getUser();
        if (savedUser != null) {
          print("User data persisted successfully.");
          return true;
        } else {
          print("Error: User data verification failed.");
          return false;
        }
      } else {
        print("Login Failed: ${response.statusCode}");
        return false;
      }
    } on DioException catch (e) {
      print("Network Error: ${e.message}");
      return false;
    } catch (e) {
      print("Unexpected Error during login: $e");
      return false;
    }
  }

  /// Check if a user is already logged in (Offline support)
  Future<bool> isLoggedIn() async {
    try {
      // Retrieve the user from the persistent SQLite database
      final user = await _dbHelper.getUser();

      if (user != null) {
        print("Session restored for user: ${user['username']}");
        return true;
      } else {
        print("No active session found.");
        return false;
      }
    } catch (e) {
      print("Error checking session: $e");
      return false;
    }
  }

  /// Optional: Helper to clear session (Logout)
  Future<void> logout() async {
    await _dbHelper.resetDatabase();
  }
}
