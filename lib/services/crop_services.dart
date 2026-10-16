import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          .order('created_at', ascending: true);
      crops = (rows as List)
          .map((r) => Crop.fromMap(Map<String, dynamic>.from(r)))
          .toList();

      final prefs = await SharedPreferences.getInstance();
      final wantedId = selected?.id ?? prefs.getString(_prefKey);
      selected = crops.isEmpty
          ? null
          : crops.firstWhere((c) => c.id == wantedId,
              orElse: () => crops.first);
    } catch (e) {
      debugPrint('CropService.load error: $e');
      crops = [];
      selected = null;
    }
    loaded = true;
    notifyListeners();
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
    notifyListeners();
  }
}