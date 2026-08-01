import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/pages/user_account.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_harbest_1/firebase_options.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://vdginsecbpsqdayqugtg.supabase.co',
    anonKey: 'sb_publishable_SCZV5hZeFBgFChWKvkE1Ig_4_4P1kOH',
  );

  runApp(const UserDashboard());
}

class UserDashboard extends StatelessWidget {
  const UserDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Sans-Serif'),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  final _supabase = Supabase.instance.client;

  Map<String, dynamic> _sensorData = {};
  bool _isLoading = true;
  String? _error;

  late final RealtimeChannel _sensorChannel;
  Timer? _refreshTimer;

  // Fetch latest sensor data on init and set up realtime subscription
  @override
  void initState() {
    super.initState();
    _fetchSensorData();
    _subscribeToSensor();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchSensorData(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _supabase.removeChannel(_sensorChannel);
    super.dispose();
  }
  // Fetch latest sensor data from Supabase and update state
  Future<void> _fetchSensorData() async {
    try {
      final response = await _supabase
          .from('sensor_readings')
          .select()
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      debugPrint("Raw response: $response");
      if (!mounted) return;

      if (response == null) {
        setState(() {
          _error = "No sensor data found. Start your Raspberry Pi!";
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _sensorData = Map<String, dynamic>.from(response);
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "No sensor data found. Start your Raspberry Pi!";
        _isLoading = false;
      });
      debugPrint("Supabase fetch error: $e");
    }
  }
  // Set up Supabase realtime subscription to listen for new sensor readings and update state in real-time
  void _subscribeToSensor() {
    _sensorChannel = _supabase
        .channel('sensor_readings_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sensor_readings',
          callback: (payload) {
            debugPrint("Supabase live update: ${payload.newRecord}");
            if (!mounted) return;
            setState(() {
              _sensorData = Map<String, dynamic>.from(payload.newRecord);
              _error = null;
            });
          },
        )
        .subscribe((status, [error]) {
          debugPrint("Realtime status: $status");
          if (error != null) debugPrint("Realtime error: $error");
        });
  }

  // crop health and nutrient recommendation 
  Widget _buildTopInsightCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         
        Expanded(
          flex: 2,
          child: Container(
            height: 150,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                // ignore: deprecated_member_use
                color: Colors.green.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [               
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "${_sensorData['crop_health'] ?? '0'}",
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(221, 80, 80, 80),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Crop Health",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Nutrient Recommendation card
        Expanded(
          flex: 3,
          child: Container(
            height: 150,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                
                color: Colors.green.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Nutrient Recommendation",
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  _sensorData['nutrient_rec'] ??'No recommendations available',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color.fromARGB(221, 80, 80, 80),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // show loading / error / data states
  Widget _buildSensorGrid() {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Show error state with retry button if no data found
    if (_error != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 60, color: Colors.grey),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _fetchSensorData();
                },
                icon: const Icon(Icons.refresh),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7CB342),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 15,
      mainAxisSpacing: 15,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        SensorCard(
          value: "${_sensorData['temperature'] ?? '0'}°C",
          label: 'Temperature',
          color: const Color.fromARGB(255, 175, 119, 84),
          icon: Icons.thermostat,
        ),
        SensorCard(
          value: "${_sensorData['humidity'] ?? '0'}%",
          label: 'Humidity',
          color: Colors.blueAccent,
          icon: Icons.water_drop_rounded,
        ),
        SensorCard(
          value: "${_sensorData['nitrogen'] ?? '0'}",
          label: 'Nitrogen (N)',
          icon: Icons.grass,
          color: Colors.greenAccent,
          showProgress: false,
        ),
        SensorCard(
          value: "${_sensorData['phosphorus'] ?? '0'}",
          label: 'Phosphorus (P)',
          icon: Icons.nature,
          color: const Color.fromARGB(255, 129, 67, 105),
          showProgress: false,
        ),
        SensorCard(
          value: "${_sensorData['potassium'] ?? '0'}",
          label: 'Potassium (K)',
          icon: Icons.local_florist,
          color: Colors.green,
          showProgress: false,
        ),
        SensorCard(
          value: "${_sensorData['heat_index'] ?? '0'}",
          label: 'Heat Index',
          color: Colors.redAccent,
          icon: Icons.wb_sunny,
          showProgress: false,
        ),
        SensorCard(
          value: "${_sensorData['pH'] ?? '0'}",
          label: 'Soil pH',
          color: Colors.purpleAccent,
          showProgress: false,
        ),
        SensorCard(
          value: "${_sensorData['moisture'] ?? '0'}%",
          label: 'Soil Moisture',
          color: Colors.amber,
          showProgress: false,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Green Header
          Container(
            padding: const EdgeInsets.only(
              top: 60,
              left: 20,
              right: 20,
              bottom: 20,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF7CB342),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'HarBest: Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.person_outline,
                    color: Color.fromARGB(255, 58, 53, 53),
                    size: 30,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UserAccount()),
                    );
                  },
                ),
              ],
            ),
          ),

          // Scrollable body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Crop Health & Nutrient Recommendation
                  _buildTopInsightCards(),

                  const SizedBox(height: 25),

                  // Sensor Overview
                  const Text(
                    'Sensor Overview',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),

                  _buildSensorGrid(),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Navigation Bar
      bottomNavigationBar: Container(
        height: 90,
        decoration: const BoxDecoration(
          color: Color(0xFF7CB342),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(50),
            topRight: Radius.circular(50),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            Icon(Icons.home_rounded, color: Colors.white, size: 35),
            Icon(Icons.sensors_rounded, color: Colors.white, size: 35),
            Icon(Icons.eco, color: Color(0xFF0F1F04), size: 50),
            Icon(Icons.analytics_rounded, color: Colors.white, size: 35),
            Icon(Icons.notifications_rounded, color: Colors.white, size: 35),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
class SensorCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color color;
  final bool showProgress;

  const SensorCard({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    this.icon,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (value.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Show either a progress indicator or the sensor icon
                if (showProgress)
                  const CircularProgressIndicator(value: 0.75, strokeWidth: 5)
                else if (icon != null)
                  Icon(icon, color: color, size: 30),
              ],
            ),
            const SizedBox(height: 10),
            
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

