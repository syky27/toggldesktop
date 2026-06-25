import 'package:flutter/material.dart';

import '../theme.dart';

/// The Redtick brand mark: a white hourglass glyph on the beveled deep-red
/// rounded tile, optionally followed by the two-tone "Red**tick**" wordmark.
/// Backs the login screen, the desktop rail header, and any splash/about use.
class RedtickLogo extends StatelessWidget {
  const RedtickLogo({
    super.key,
    this.size = 40,
    this.wordmark = false,
    this.wordmarkColor,
  });

  final double size;
  final bool wordmark;
  final Color? wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 1.1,
          colors: [kBrandTileTop, kBrandTileBottom],
          stops: [0.0, 0.72],
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: const Color(0x338C1513),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.05),
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.5, size * 0.54),
          painter: _HourglassPainter(),
        ),
      ),
    );

    if (!wordmark) return tile;

    final wc = wordmarkColor ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        SizedBox(width: size * 0.32),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: size * 0.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.0,
            ),
            children: [
              TextSpan(text: 'Red', style: TextStyle(color: wc)),
              const TextSpan(text: 'tick', style: TextStyle(color: kBrandRed)),
            ],
          ),
        ),
      ],
    );
  }
}

class _HourglassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Two triangles meeting at the waist → hourglass silhouette.
    final glass = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(cx, cy)
      ..close()
      ..moveTo(0, h)
      ..lineTo(w, h)
      ..lineTo(cx, cy)
      ..close();
    canvas.drawPath(glass, white);

    // The falling "sand" dot just below the waist.
    canvas.drawCircle(
      Offset(cx, cy + h * 0.06),
      w * 0.05,
      Paint()..color = kBrandTileBottom,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
