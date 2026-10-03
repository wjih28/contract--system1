import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// لوحة توقيع يدوي باللمس، تُصدّر التوقيع كصورة PNG (base64)
class SignaturePad extends StatefulWidget {
  final double height;
  const SignaturePad({super.key, this.height = 180});

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void clear() => setState(_strokes.clear);

  /// تصدير التوقيع بخط داكن على خلفية شفافة ليظهر في ملف PDF
  Future<String?> exportBase64() async {
    if (isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const scale = 2.0;
    canvas.scale(scale);
    _paintStrokes(canvas, const Color(0xFF0F1B2E));
    final img = await recorder
        .endRecording()
        .toImage((_size.width * scale).ceil(), (_size.height * scale).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return base64Encode(data.buffer.asUint8List());
  }

  void _paintStrokes(Canvas canvas, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in _strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _size = Size(c.maxWidth, widget.height);
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3E8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned(
                left: 20,
                right: 20,
                bottom: 36,
                child: Container(height: 1, color: const Color(0x331F3151)),
              ),
              if (isEmpty)
                const Center(
                  child: Text(
                    'وقّع هنا بإصبعك',
                    style: TextStyle(color: Color(0x881F3151), fontSize: 13),
                  ),
                ),
              GestureDetector(
                onPanStart: (d) =>
                    setState(() => _strokes.add([d.localPosition])),
                onPanUpdate: (d) =>
                    setState(() => _strokes.last.add(d.localPosition)),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _PadPainter(this),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _PadPainter extends CustomPainter {
  final SignaturePadState state;
  _PadPainter(this.state);

  @override
  void paint(Canvas canvas, Size size) =>
      state._paintStrokes(canvas, const Color(0xFF0F1B2E));

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
