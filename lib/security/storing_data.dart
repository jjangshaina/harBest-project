import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoringData {
  // Create storage instance
  final _storage = const FlutterSecureStorage();

  // Save the login status (true = logged in, false = logged out)
  Future<void> setLoginStatus(bool isLoggedIn) async {
    await _storage.write(key: 'isLoggedIn', value: isLoggedIn.toString());
  }

  // Read the login status
  Future<String?> getLoginStatus() async {
    return await _storage.read(key: 'isLoggedIn');
  }

  // Clear everything on logout
  Future<void> logout() async {
    await _storage.deleteAll();
  }
}