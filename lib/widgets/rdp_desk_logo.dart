import 'package:flutter/material.dart';

/// Vector mark: remote window, SSH prompt, live-session dot.
class RdpDeskLogo extends StatelessWidget {
  const RdpDeskLogo({super.key, this.size = 48, this.showShadow = true});

  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: RdpDeskLogoPainter(showShadow: showShadow && size >= 24),
      ),
    );
  }
}

class RdpDeskWordmark extends StatelessWidget {
  const RdpDeskWordmark({super.key, this.logoSize = 48});

  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final titleSize = logoSize * 0.42;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RdpDeskLogo(size: logoSize),
        SizedBox(width: logoSize * 0.28),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'mori',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: titleSize,
                  color: Colors.white,
                  height: 1,
                  letterSpacing: 0.2,
                ),
              ),
              TextSpan(
                text: 'xtrem',
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: titleSize,
                  color: Colors.white,
                  height: 1,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RdpDeskLogoPainter extends CustomPainter {
  const RdpDeskLogoPainter({this.showShadow = true});

  final bool showShadow;

  static const _shell = Color(0xFF2A2B30);
  static const _shellTop = Color(0xFF35363C);
  static const _window = Color(0xFF1A1C20);
  static const _title = Color(0xFF5B9BD5);
  static const _prompt = Color(0xFFE6B422);
  static const _live = Color(0xFF3D9970);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final origin = Offset((size.width - s) / 2, (size.height - s) / 2);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);

    final shell = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.22),
    );
    canvas.clipRRect(shell);

    canvas.drawRRect(
      shell,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_shellTop, _shell],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );

    canvas.drawRRect(
      shell.deflate(s * 0.01),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018
        ..color = const Color(0x28FFFFFF),
    );

    final windowRect = Rect.fromLTWH(s * 0.16, s * 0.18, s * 0.68, s * 0.58);
    final window = RRect.fromRectAndRadius(windowRect, Radius.circular(s * 0.085));

    if (showShadow) {
      canvas.drawRRect(
        window.shift(Offset(0, s * 0.018)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
      );
    }

    canvas.drawRRect(window, Paint()..color = _window);

    canvas.save();
    canvas.clipRRect(window);
    canvas.drawRect(
      Rect.fromLTWH(windowRect.left, windowRect.top, windowRect.width, s * 0.09),
      Paint()..color = _title,
    );
    canvas.restore();

    final stroke = Paint()
      ..color = _prompt
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * 0.055).clamp(1.6, 8.0).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final chevron = Path()
      ..moveTo(s * 0.28, s * 0.40)
      ..lineTo(s * 0.405, s * 0.50)
      ..lineTo(s * 0.28, s * 0.60);
    canvas.drawPath(chevron, stroke);
    canvas.drawLine(Offset(s * 0.46, s * 0.585), Offset(s * 0.64, s * 0.585), stroke);

    canvas.drawCircle(Offset(s * 0.735, s * 0.665), s * 0.038, Paint()..color = _live);
    canvas.restore();
  }

  @override
  bool shouldRepaint(RdpDeskLogoPainter oldDelegate) => oldDelegate.showShadow != showShadow;
}
