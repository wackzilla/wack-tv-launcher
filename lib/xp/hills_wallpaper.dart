/*
 * Wack XP Launcher (FLauncher fork)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';

/// The default wallpaper: a painted green hill under a blue sky, in the spirit of XP's "Bliss".
class HillsWallpaper extends StatelessWidget
{
  const HillsWallpaper({super.key});

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
    child: CustomPaint(painter: _HillsPainter(), size: Size.infinite),
  );
}

class _HillsPainter extends CustomPainter
{
  const _HillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1C5FD1), Color(0xFF4A8EE8), Color(0xFF9CC8F4), Color(0xFFD6EAFB)],
        stops: [0, 0.35, 0.65, 0.8],
      ).createShader(rect));

    final cloud = Paint()
      ..color = const Color(0xD9FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    _cloud(canvas, cloud, Offset(w * 0.22, h * 0.18), w * 0.16, h * 0.05);
    _cloud(canvas, cloud, Offset(w * 0.33, h * 0.24), w * 0.10, h * 0.035);
    _cloud(canvas, cloud, Offset(w * 0.68, h * 0.12), w * 0.13, h * 0.045);
    _cloud(canvas, cloud, Offset(w * 0.82, h * 0.30), w * 0.18, h * 0.05);
    _cloud(canvas, cloud, Offset(w * 0.52, h * 0.38), w * 0.12, h * 0.03);

    // Far hill on the right
    final farHill = Path()
      ..moveTo(w * 0.35, h)
      ..quadraticBezierTo(w * 0.75, h * 0.48, w * 1.1, h * 0.62)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(farHill, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF5E9E3A), Color(0xFF3E7D22)],
      ).createShader(Rect.fromLTWH(0, h * 0.5, w, h * 0.5)));

    // Main hill
    final hill = Path()
      ..moveTo(0, h * 0.72)
      ..cubicTo(w * 0.22, h * 0.52, w * 0.48, h * 0.55, w * 0.7, h * 0.7)
      ..cubicTo(w * 0.82, h * 0.78, w * 0.92, h * 0.8, w, h * 0.78)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF8DCB4A), Color(0xFF5DAA2C), Color(0xFF3C8A1C), Color(0xFF2F6E16)],
        stops: [0, 0.25, 0.6, 1],
      ).createShader(Rect.fromLTWH(0, h * 0.52, w, h * 0.48)));

    // Sunlit crest
    final crest = Path()
      ..moveTo(w * 0.05, h * 0.69)
      ..cubicTo(w * 0.24, h * 0.545, w * 0.46, h * 0.565, w * 0.62, h * 0.65)
      ..cubicTo(w * 0.46, h * 0.6, w * 0.26, h * 0.59, w * 0.05, h * 0.69)
      ..close();
    canvas.drawPath(crest, Paint()
      ..color = const Color(0x66D9F59A)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
  }

  void _cloud(Canvas canvas, Paint paint, Offset center, double rx, double ry) {
    canvas.drawOval(Rect.fromCenter(center: center, width: rx * 2, height: ry * 2), paint);
    canvas.drawOval(Rect.fromCenter(center: center.translate(-rx * 0.45, -ry * 0.4), width: rx, height: ry * 1.6), paint);
    canvas.drawOval(Rect.fromCenter(center: center.translate(rx * 0.35, -ry * 0.5), width: rx * 0.9, height: ry * 1.5), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
