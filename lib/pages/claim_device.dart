import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/pages/add_crop.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/app_text_field.dart';

class ClaimDevicePage extends StatefulWidget {
  const ClaimDevicePage({super.key});

  @override
  State<ClaimDevicePage> createState() => _ClaimDevicePageState();
}

class _ClaimDevicePageState extends State<ClaimDevicePage> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      AppSnack.show(context, 'Enter the device code.',
          type: AppSnackType.error);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final res = await Supabase.instance.client.rpc('claim_device', params: {
        'p_code': code,
        'p_name': _nameController.text.trim(),
      });
      final deviceId = res as String;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AddCropPage(deviceId: deviceId)),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        e.message.contains('Invalid or already-used')
            ? 'That code is not valid, or it was already used.'
            : 'Could not claim the device. Please try again.',
        type: AppSnackType.error,
      );
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(context, 'Something went wrong. Please try again.',
          type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(title: 'Add your device', showBack: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the code that came with your HarBest device. '
                    'It links the device to your account.',
                    style: AppText.subtitle,
                  ),
                  const SizedBox(height: 20),
                  AppFormField(
                    label: 'Device code',
                    controller: _codeController,
                  ),
                  const SizedBox(height: 18),
                  AppFormField(
                    label: 'Device name (optional)',
                    controller: _nameController,
                  ),
                  const SizedBox(height: 32),
                  AppButton(
                    label: 'Claim device',
                    expanded: true,
                    loading: _isSubmitting,
                    onPressed: _claim,
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