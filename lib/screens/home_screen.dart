import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/models.dart';
import 'analyze_screen.dart';
import 'calibration_screen.dart';
import 'card_screen.dart';
import 'log_screen.dart';
import 'timer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final s = AppServices.instance;
  String _test = 'nitrate';
  CurveRecord? _curve;

  @override
  void initState() {
    super.initState();
    _loadCurve();
  }

  Future<void> _loadCurve() async {
    final id = s.activeCurveId;
    final c = id == null ? null : await s.db.curve(id);
    if (mounted) setState(() => _curve = c);
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _loadCurve();
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null || !mounted) return;
    _go(AnalyzeScreen(
        photoPath: x.path, request: const MeasureRequest.reading(), captureDelaySeconds: 0));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dev = s.devTimeSeconds;
    return Scaffold(
      appBar: AppBar(title: const Text('Nitrate Strip Reader')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _test,
            decoration: const InputDecoration(labelText: 'Test', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'nitrate', child: Text('Nitrate (0–50 mg/L NO3-N)')),
            ],
            onChanged: (v) => setState(() => _test = v ?? 'nitrate'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text('Development time', style: t.titleMedium)),
                IconButton(
                    onPressed: () => setState(() => s.devTimeSeconds = dev - 5),
                    icon: const Icon(Icons.remove)),
                Text('$dev s', style: t.titleLarge),
                IconButton(
                    onPressed: () => setState(() => s.devTimeSeconds = dev + 5),
                    icon: const Icon(Icons.add)),
              ]),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.show_chart),
              title: Text(_curve == null ? 'No calibration curve selected' : 'Curve: ${_curve!.name}'),
              subtitle: Text(_curve == null
                  ? 'Calibrate with known standards before taking readings.'
                  : (_curve!.lot.isEmpty ? 'Tap to manage curves' : 'Lot ${_curve!.lot}')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go(const CalibrationScreen()),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '1. Dip the strip for about 1 second and shake off the excess.\n'
            '2. Tap Start straight away.\n'
            '3. Lay the strip pad-up in the slot on the reference card while the timer runs.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            onPressed: () => _go(const TimerScreen(request: MeasureRequest.reading())),
            icon: const Icon(Icons.play_arrow, size: 32),
            label: Text('Start', style: t.titleLarge?.copyWith(color: Colors.white)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Analyze an existing photo'),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('Reading log'),
            onTap: () => _go(const LogScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Calibration curves'),
            onTap: () => _go(const CalibrationScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Reference card (print)'),
            onTap: () => _go(const CardScreen()),
          ),
        ],
      ),
    );
  }
}
