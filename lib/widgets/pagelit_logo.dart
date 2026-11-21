import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Resolution-independent vector rendering of the Pagelit brand logo.
///
/// Reproduces the official icon artwork (royal blue backdrop with radial light
/// rays, red folded-corner PDF sheet, twin yellow highlighter arcs, and crisp
/// bold white "PDF" wordmark) using [CustomPaint] so it remains razor-sharp at
/// any screen density or size.
class PagelitLogo extends StatelessWidget {
  const PagelitLogo({
    super.key,
    this.size = 112,
    this.borderRadius,
  });

  final double size;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? size * 0.25;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _PagelitLogoPainter(),
        ),
      ),
    );
  }
}

class _PagelitLogoPainter extends CustomPainter {
  static const _bgCenter = Color(0xFF4A4AE0);
  static const _bgBase = Color(0xFF3E3DCD);
  static const _bgEdge = Color(0xFF3534C2);

  static const _sheetTop = Color(0xFFE83B28);
  static const _sheetBottom = Color(0xFFDE301E);
  static const _foldShadow = Color(0xFFB52214);
  static const _yellow = Color(0xFFFFE033);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100.0;
    canvas.save();
    canvas.scale(scale, size.height / 100.0);

    // 1. Royal-blue background with subtle radial depth.
    const fullRect = Rect.fromLTWH(0, 0, 100, 100);
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.72,
        colors: [_bgCenter, _bgBase, _bgEdge],
        stops: [0.0, 0.55, 1.0],
      ).createShader(fullRect);
    canvas.drawRect(fullRect, bgPaint);

    // 2. Eight subtle radial light beams behind the document sheet.
    final rayPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.48,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(fullRect);

    const innerR = 14.0;
    const outerR = 48.0;
    const halfSpreadInner = 0.09;
    const halfSpreadOuter = 0.20;
    for (int i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + i * (math.pi / 4);
      final rayPath = Path()
        ..moveTo(
          50 + innerR * math.cos(angle - halfSpreadInner),
          50 + innerR * math.sin(angle - halfSpreadInner),
        )
        ..lineTo(
          50 + outerR * math.cos(angle - halfSpreadOuter),
          50 + outerR * math.sin(angle - halfSpreadOuter),
        )
        ..lineTo(
          50 + outerR * math.cos(angle + halfSpreadOuter),
          50 + outerR * math.sin(angle + halfSpreadOuter),
        )
        ..lineTo(
          50 + innerR * math.cos(angle + halfSpreadInner),
          50 + innerR * math.sin(angle + halfSpreadInner),
        )
        ..close();
      canvas.drawPath(rayPath, rayPaint);
    }

    // 3. Red PDF document sheet with cut top-right corner and soft shadow.
    const left = 26.0;
    const top = 20.0;
    const right = 74.0;
    const bottom = 80.0;
    const cornerR = 4.5;
    const foldSize = 16.0;
    const foldLeft = right - foldSize; // 58.0
    const foldBottom = top + foldSize; // 36.0

    final sheetPath = Path()
      ..moveTo(left + cornerR, top)
      ..lineTo(foldLeft, top)
      ..lineTo(right, foldBottom)
      ..lineTo(right, bottom - cornerR)
      ..quadraticBezierTo(right, bottom, right - cornerR, bottom)
      ..lineTo(left + cornerR, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - cornerR)
      ..lineTo(left, top + cornerR)
      ..quadraticBezierTo(left, top, left + cornerR, top)
      ..close();

    // Soft drop shadow beneath the sheet.
    canvas.drawPath(
      sheetPath.shift(const Offset(0, 1.6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
    );

    final sheetPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_sheetTop, _sheetBottom],
      ).createShader(const Rect.fromLTRB(left, top, right, bottom));
    canvas.drawPath(sheetPath, sheetPaint);

    // 4. Diagonal cast shadow directly below the folded corner.
    final foldShadowPath = Path()
      ..moveTo(foldLeft + 1.5, foldBottom - 1.5)
      ..lineTo(right, foldBottom)
      ..lineTo(right, foldBottom + foldSize)
      ..close();
    canvas.drawPath(
      foldShadowPath,
      Paint()..color = _foldShadow.withValues(alpha: 0.65),
    );

    // 5. Crisp white folded corner flap with smooth rounded inner corner.
    final foldPath = Path()
      ..moveTo(foldLeft, top)
      ..lineTo(foldLeft, foldBottom - cornerR)
      ..quadraticBezierTo(
        foldLeft,
        foldBottom,
        foldLeft + cornerR,
        foldBottom,
      )
      ..lineTo(right, foldBottom)
      ..close();
    canvas.drawPath(foldPath, Paint()..color = Colors.white);

    // 6. Twin yellow highlighter arcs across the middle of the sheet.
    final upperArc = Path()
      ..moveTo(33.2, 50.6)
      ..quadraticBezierTo(49.5, 47.4, 66.8, 49.4);
    canvas.drawPath(
      upperArc,
      Paint()
        ..color = _yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    final lowerArc = Path()
      ..moveTo(36.8, 53.6)
      ..quadraticBezierTo(49.2, 50.8, 61.5, 51.8);
    canvas.drawPath(
      lowerArc,
      Paint()
        ..color = _yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();

    // 7. Bold white "PDF" wordmark painted in native pixel space for optimal hinting.
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'PDF',
        style: TextStyle(
          color: Colors.white,
          fontSize: size.width * 0.175,
          fontWeight: FontWeight.w800,
          fontFamily: AppTheme.fontFamily,
          fontFamilyFallback: AppTheme.fontFamilyFallback,
          letterSpacing: size.width * 0.008,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(
      (size.width - textPainter.width) / 2,
      size.height * 0.665 - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant _PagelitLogoPainter oldDelegate) => false;
}
