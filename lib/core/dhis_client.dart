import 'dart:convert';
import 'package:dio/dio.dart';

class DhisClient {
  // 1. Create a Singleton instance
  static final DhisClient _instance = DhisClient._internal();

  // 2. Factory constructor returns the same instance every time
  factory DhisClient() {
    return _instance;
  }

  final Dio _dio = Dio();

  // GENERIC: Start with an empty URL.
  String baseUrl = '';

  // 3. Private constructor for initialization
  DhisClient._internal() {
    _dio.options.baseUrl = baseUrl;

    // UPDATED: Increased timeouts to 10 MINUTES (600 seconds)
    // This allows large batches of data to download without cutting off.
    _dio.options.connectTimeout = const Duration(seconds: 600);
    _dio.options.receiveTimeout = const Duration(seconds: 600);

    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Dio get dio => _dio;

  // 4. Method to update the Base URL dynamically
  void setBaseUrl(String url) {
    if (url.isEmpty) return;

    // Remove trailing slash if present to avoid double slashes later
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    baseUrl = url;
    _dio.options.baseUrl = baseUrl;
    print("DHIS2 URL set to: $baseUrl");
  }

  // Helper to create Basic Auth Header
  String getBasicAuth(String username, String password) {
    String basicAuth =
        'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    return basicAuth;
  }
}
