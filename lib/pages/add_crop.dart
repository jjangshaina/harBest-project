import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/app_text_field.dart';

class AddCropPage extends StatefulWidget {
  final String deviceId;

  /// When set, saving also marks this crop as harvested, in the same database
  /// call that inserts the new one (start_new_crop). Used by the "Start new
  /// crop" link of the harvest reminder.
  final String? replacingCropId;

  /// Name suggested in the field, for example "Mustard no.2".
  final String? initialName;

  const AddCropPage({
    super.key,
    required this.deviceId,
    this.replacingCropId,
    this.initialName,
  });

  @override
  State<AddCropPage> createState() => _AddCropPageState();
}

class _AddCropPageState extends State<AddCropPage> {
  late final _nameController = TextEditingController(
    text: widget.initialName ?? 'Mustard no.1',
  );
  DateTime _plantingDate = DateTime.now();
  bool _isSaving = false;

  bool get _replacing => widget.replacingCropId != null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmt(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plantingDate,
      firstDate: now.subtract(const Duration(days: 120)),
      lastDate: now,
    );
    if (picked != null) setState(() => _plantingDate = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (name.isEmpty) {
      AppSnack.show(context, 'Give your crop a name.',
          type: AppSnackType.error);
      return;
    }
    if (uid == null) {
      AppSnack.show(context, 'Please log in again.', type: AppSnackType.error);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final db = Supabase.instance.client;
      String? newId;
      if (_replacing) {
        // One call: the old crop becomes "harvested" and the new crop is
        // inserted as "active". If either part fails, neither is saved.
        final res = await db.rpc('start_new_crop', params: {
          'p_old_crop': widget.replacingCropId,
          'p_name': name,
          'p_planting': _fmt(_plantingDate),
        });
        newId = res as String?;
      } else {
        await db.from('crops').insert({
          'owner_uid': uid,
          'device_id': widget.deviceId,
          'name': name,
          'crop_type': 'Mustard Green',
          'planting_date': _fmt(_plantingDate),
        });
      }
      await CropService.instance.load();
      // Open the new crop right away.
      final fresh = CropService.instance.crops.where((c) => c.id == newId);
      if (fresh.isNotEmpty) CropService.instance.select(fresh.first);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('AddCrop error: $e');
      if (!mounted) return;
      AppSnack.show(context, 'Could not save the crop. Please try again.',
          type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            title: _replacing ? 'Start a new crop' : 'Add your crop',
            showBack: true,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _replacing
                        ? 'Your previous crop will be marked as harvested. '
                            'Choose the name and planting date of the new one.'
                        : 'Your device is linked. Tell us about the crop it will monitor.',
                    style: AppText.subtitle,
                  ),
                  const SizedBox(height: 20),
                  AppFormField(
                    label: 'Crop name',
                    controller: _nameController,
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: _pickDate,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: AppColors.fieldLight,
                        borderRadius: BorderRadius.circular(AppRadius.field),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Planting date: ${_fmt(_plantingDate)}',
                                style: AppText.body),
                          ),
                          const Icon(AppIcons.timeline,
                              size: 20, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Crop type: Mustard Green',
                      style: AppText.subtitle),
                  const SizedBox(height: 32),
                  AppButton(
                    label: _replacing ? 'Start new crop' : 'Save crop',
                    expanded: true,
                    loading: _isSaving,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}