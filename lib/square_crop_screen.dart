import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'theme/caliu_colors.dart';

/// Retalla una imatge en quadrat abans de pujar-la com a foto de perfil
/// (tasca #150, H.U #35). L'usuari la mou i hi fa zoom dins del marc; en
/// prémer "Fet" es retorna el quadrat en PNG.
class SquareCropScreen extends StatefulWidget {
  const SquareCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  /// Costat, en píxels, de la imatge resultant.
  static const outputSize = 512.0;

  @override
  State<SquareCropScreen> createState() => _SquareCropScreenState();
}

class _SquareCropScreenState extends State<SquareCropScreen> {
  final _boundaryKey = GlobalKey();
  bool _saving = false;

  Future<void> _done(double side) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(
        pixelRatio: SquareCropScreen.outputSize / side,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted) return;
      Navigator.of(context).pop(data!.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No s\'ha pogut retallar la imatge')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Retalla la foto'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = (constraints.biggest.shortestSide - 48).clamp(
              120.0,
              360.0,
            );
            return Column(
              children: [
                const SizedBox(height: 16),
                const Text(
                  'Mou i amplia la foto perquè quedi dins del quadrat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                Expanded(
                  child: Center(
                    child: SizedBox.square(
                      dimension: side,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            key: _boundaryKey,
                            child: ClipRect(
                              child: InteractiveViewer(
                                key: const Key('crop-viewer'),
                                minScale: 1,
                                maxScale: 5,
                                child: Image.memory(
                                  widget.imageBytes,
                                  width: side,
                                  height: side,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          ),
                          // Guia: el cercle és el que es veurà com a avatar.
                          IgnorePointer(
                            child: CustomPaint(painter: _CircleGuidePainter()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancel·la'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _done(side),
                          style: FilledButton.styleFrom(
                            backgroundColor: CaliuColors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(_saving ? 'Retallant…' : 'Fet'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Enfosqueix les cantonades i dibuixa el cercle de l'avatar.
class _CircleGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      circle,
    );
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawPath(
      circle,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
