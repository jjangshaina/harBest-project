import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Crop {
  final String id, deviceId, name, cropType;
  final int slot;
  final DateTime? plantingDate;
  final String? imageUrl;

  Crop.fromMap(Map<String, dynamic> m)
      : id = m['crop_id'] as String,
        deviceId = m['device_id'] as String,
        name = (m['name'] as String?) ?? 'My crop',
        cropType = (m['crop_type'] as String?) ?? 'Mustard Green',
        slot = (m['slot'] as int?) ?? 1,
        imageUrl = m['image_url'] as String?,
        plantingDate = DateTime.tryParse('${m['planting_date']}');
}

/// Holds the signed-in user's crops. Pages read from here instead of
/// querying Supabase globally.
class CropService extends ChangeNotifier {
  CropService._();
  static final instance = CropService._();

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
          .eq('owner_uid', uid)
          .eq('status', 'active')
          .order('created_at');
      crops = (rows as List)
          .map((r) => Crop.fromMap(Map<String, dynamic>.from(r)))
          .toList();
      selected = crops.isEmpty
          ? null
          : crops.firstWhere((c) => c.id == selected?.id,
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
    notifyListeners();
  }

  /// Call on logout / account deletion so the next user never sees the
  /// previous user's crop (this is a singleton and outlives the session).
  void clear() {
    crops = [];
    selected = null;
    loaded = false;
    notifyListeners();
  }
}