import 'package:material_ui/material_ui.dart';

import '../color/color_space.dart';
import '../color/vec3.dart';

/// A square filled with a CIELAB color, for display.
class LabSwatch extends StatelessWidget {
  final Vec3 lab;
  final double size;
  const LabSwatch({super.key, required this.lab, this.size = 48});
  @override
  Widget build(BuildContext context) {
    final c = labToSrgb8(lab);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: Color.fromARGB(255, c[0], c[1], c[2]),
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(6)),
    );
  }
}

String labText(Vec3 lab) =>
    'L* ${lab.x.toStringAsFixed(1)}  a* ${lab.y.toStringAsFixed(1)}  b* ${lab.z.toStringAsFixed(1)}';
