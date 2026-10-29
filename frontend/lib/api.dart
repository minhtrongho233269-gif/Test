import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Api {
  static const base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://phamnguyentuandat-2380614580-api.onrender.com',
  );
  static const storage = FlutterSecureStorage();
  String? token;
  bool get configured {
    final uri = Uri.tryParse(base);
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' ||
            (const bool.fromEnvironment('ALLOW_LOCAL_HTTP') &&
                uri.scheme == 'http'));
  }

  Future<dynamic> call(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    if (!configured) {
      throw Exception(
        'Cần cấu hình API_BASE_URL; HTTP nội bộ cần ALLOW_LOCAL_HTTP=true.',
      );
    }
    final request = http.Request(method, Uri.parse('$base$path'));
    request.headers.addAll({
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    });
    if (data != null) request.body = jsonEncode(data);
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 60)),
    );
    final dynamic body = response.body.isEmpty
        ? null
        : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body?['message'] ?? 'Không kết nối được máy chủ');
    }
    return body;
  }

  Future<void> logout() async {
    token = null;
    await storage.deleteAll();
  }
}
