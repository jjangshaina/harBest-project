import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart'
    show kRequestTimeout, isConnectionError, ConnectionWatcher;

/// The last data each page loaded, saved on the phone. When there is no
/// internet the pages show it instead, also after the app was closed and
/// opened again offline.
class LastData {
  LastData._();

  static Future<void> save(String key, Object? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_data_$key', jsonEncode(value));
    } catch (e) {
      debugPrint('LastData.save($key) error: $e');
    }
  }

  static Future<dynamic> read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('last_data_$key');
      return raw == null ? null : jsonDecode(raw);
    } catch (e) {
      debugPrint('LastData.read($key) error: $e');
      return null;
    }
  }
}

class Crop {
  final String id, deviceId, ownerUid, name, cropType;
  final int slot;
  final DateTime? plantingDate;
  final String? imageUrl;

  Crop.fromMap(Map<String, dynamic> m)
      : id = m['crop_id'] as String,
        deviceId = m['device_id'] as String,
        ownerUid = (m['owner_uid'] as String?) ?? '',
        name = (m['name'] as String?) ?? 'My crop',
        cropType = (m['crop_type'] as String?) ?? 'Mustard Green',
        slot = (m['slot'] as int?) ?? 1,
        imageUrl = m['image_url'] as String?,
        plantingDate = DateTime.tryParse('${m['planting_date']}');
}

/// Holds the crops the signed-in user may see (their own, or all of them for
/// an admin account; the database decides).
class CropService extends ChangeNotifier {
  CropService._();
  static final instance = CropService._();
  static const _prefKey = 'selected_crop_id';

  final _db = Supabase.instance.client;

  List<Crop> crops = [];
  Crop? selected;
  bool loaded = false;

  /// True when the last [load] could not reach the server. The crops from
  /// before (if any) are kept, so the pages can keep showing the last data
  /// instead of "No crop yet".
  bool offline = false;

  Future<void> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      clear();
      return;
    }
    try {
      final rows = await _db
          .from('crops')
          .select()
          .eq('status', 'active')
          .order('created_at', ascending: true)
          .timeout(kRequestTimeout);
      await _apply(rows as List);
      final wasOffline = offline;
      offline = false;
      LastData.save('crops_$uid', rows);
      if (wasOffline) ConnectionWatcher.instance.reportOnline();
    } catch (e) {
      debugPrint('CropService.load error: $e');
      if (isConnectionError(e)) {
        // Keep what we had. Opened offline with nothing yet: use the crop
        // list saved on the phone, so the pages can show their last data.
        // (The pages confirm whether the internet is really gone before
        // telling the user.)
        offline = true;
        if (crops.isEmpty) {
          final saved = await LastData.read('crops_$uid');
          if (saved is List) {
            try {
              await _apply(saved);
            } catch (e) {
              debugPrint('Saved crop list unreadable: $e');
            }
          }
        }
      } else {
        offline = false;
        crops = [];
        selected = null;
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _apply(List rows) async {
    crops = rows
        .map((r) => Crop.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
    final prefs = await SharedPreferences.getInstance();
    final wantedId = selected?.id ?? prefs.getString(_prefKey);
    selected = crops.isEmpty
        ? null
        : crops.firstWhere((c) => c.id == wantedId,
            orElse: () => crops.first);
  }

  void select(Crop c) {
    selected = c;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefKey, c.id))
        .catchError((_) => false);
    notifyListeners();
  }

  void clear() {
    crops = [];
    selected = null;
    loaded = false;
    offline = false;
    notifyListeners();
  }
}