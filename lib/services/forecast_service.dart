import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the newest forecast run written by harbest_forecast_pipeline.py.
/// `summary` is the whole forecast_output.json.
class ForecastService {
  ForecastService._();

  static Future<Map<String, dynamic>?> latest(String deviceId) async {
    final rows = await Supabase.instance.client
        .from('forecast_runs')
        .select('summary')
        .eq('device_id', deviceId)
        .order('made_at', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return Map<String, dynamic>.from(rows.first['summary'] as Map);
  }
}
