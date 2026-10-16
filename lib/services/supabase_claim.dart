import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Makes sure the user's Firebase token carries role=authenticated,
/// which Supabase needs before it will accept the token.
Future<void> ensureSupabaseClaim() async {
  
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final result = await user.getIdTokenResult();
    if (result.claims?['role'] == 'authenticated') return;

    final res = await Supabase.instance.client.functions.invoke(
      'set-role-claim',
      headers: {'x-firebase-token': result.token ?? ''},
    );
    if (res.status == 200) {
      await user.getIdToken(true); // refresh so the new claim is included
    } else {
      debugPrint('set-role-claim failed: ${res.status} ${res.data}');
    }
  } catch (e) {
    debugPrint('ensureSupabaseClaim error: $e');
  }
}
