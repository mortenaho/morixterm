import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'morixtrem_logo.dart';

const _green = Color(0xFF3D9970);
const _ssh = Color(0xFFE6B422);
const _rdp = Color(0xFF5B9BD5);

/// The Start tab landing experience.
class WelcomePane extends StatefulWidget {
  const WelcomePane({
    super.key,
    required this.onNewSession,
    this.onOpenFiles,
  });

  final VoidCallback onNewSession;
  final VoidCallback? onOpenFiles;

  @override
  State<WelcomePane> createState() => _WelcomePaneState();
}

class _WelcomePaneState extends State<WelcomePane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0A0C10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _WelcomeAtmosphere(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 820;
                return AnimatedBuilder(
                  animation: _intro,
                  builder: (context, _) {
                    final t = Curves.easeOutCubic.transform(_intro.value);
                    return Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - t) * 18),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: wide ? 48 : 28,
                            vertical: wide ? 40 : 28,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 920),
                              child: wide
                                  ? _WideWelcome(
                                      onNewSession: widget.onNewSession,
                                      onOpenFiles: widget.onOpenFiles,
                                    )
                                  : _NarrowWelcome(
                                      onNewSession: widget.onNewSession,
                                      onOpenFiles: widget.onOpenFiles,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WideWelcome extends StatelessWidget {
  const _WideWelcome({required this.onNewSession, this.onOpenFiles});

  final VoidCallback onNewSession;
  final VoidCallback? onOpenFiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 6, child: _HeroCopy(onNewSession: onNewSession)),
        const SizedBox(width: 36),
        Expanded(
          flex: 5,
          child: _FeatureStage(onOpenFiles: onOpenFiles),
        ),
      ],
    );
  }
}

class _NarrowWelcome extends StatelessWidget {
  const _NarrowWelcome({required this.onNewSession, this.onOpenFiles});

  final VoidCallback onNewSession;
  final VoidCallback? onOpenFiles;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroCopy(onNewSession: onNewSession),
          const SizedBox(height: 28),
          _FeatureStage(onOpenFiles: onOpenFiles),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.onNewSession});

  final VoidCallback onNewSession;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const MorixtermWordmark(logoSize: 72),
        const SizedBox(height: 28),
        const Text(
          'Remote sessions,\nmade elegant.',
          style: TextStyle(
            fontSize: 38,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'SSH shells, RDP desktops, and file transfers —\n'
          'all in one focused workspace.',
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Color(0xFF9AA3B2),
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _PrimaryCta(
              label: 'New Session',
              icon: Icons.add_circle_outline,
              onTap: onNewSession,
            ),
            const _HintChip(label: 'Pick a bookmark on the left to reconnect'),
          ],
        ),
        const SizedBox(height: 22),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ProtocolPill(label: 'SSH', color: _ssh),
            _ProtocolPill(label: 'RDP', color: _rdp),
            _ProtocolPill(label: 'SFTP / SCP', color: _green),
          ],
        ),
      ],
    );
  }
}

class _FeatureStage extends StatelessWidget {
  const _FeatureStage({this.onOpenFiles});

  final VoidCallback? onOpenFiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _TerminalPreview(),
        const SizedBox(height: 16),
        const _FeatureTile(
          icon: Icons.terminal_rounded,
          title: 'Interactive shell',
          subtitle: 'Themes, search, and multi-tab terminals',
          accent: _ssh,
        ),
        const SizedBox(height: 10),
        const _FeatureTile(
          icon: Icons.desktop_windows_outlined,
          title: 'Remote desktop',
          subtitle: 'Launch RDP sessions beside your shells',
          accent: _rdp,
        ),
        const SizedBox(height: 10),
        _FeatureTile(
          icon: Icons.folder_open_rounded,
          title: 'File browser',
          subtitle: 'Browse, upload, copy, and chmod remotely',
          accent: _green,
          onTap: onOpenFiles,
        ),
      ],
    );
  }
}

class _TerminalPreview extends StatelessWidget {
  const _TerminalPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF151922), Color(0xFF0E1117)],
        ),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(Color(0xFFFF5F57)),
              SizedBox(width: 6),
              _Dot(Color(0xFFFFBD2E)),
              SizedBox(width: 6),
              _Dot(Color(0xFF28C840)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'session · ssh',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7A8494),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                'CONNECTED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _green,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.55,
              ),
              children: [
                TextSpan(
                    text: 'mori',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                TextSpan(
                    text: 'xterm',
                    style: TextStyle(color: Color(0xFF7EC8FF))),
                TextSpan(
                    text: '  ·  connect · manage · explore\n',
                    style: TextStyle(color: Color(0xFF6B7380))),
                TextSpan(
                    text: '➜  ',
                    style: TextStyle(color: _ssh)),
                TextSpan(
                    text: 'ssh ',
                    style: TextStyle(color: Color(0xFF9CDCFE))),
                TextSpan(
                    text: 'user@server',
                    style: TextStyle(color: Color(0xFFCE9178))),
                TextSpan(
                    text: '\n✔  shell ready  ·  files sidebar open',
                    style: TextStyle(color: _green)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatefulWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;

  @override
  State<_FeatureTile> createState() => _FeatureTileState();
}

class _FeatureTileState extends State<_FeatureTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _hover ? const Color(0xFF171B22) : const Color(0xFF12151B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _hover
              ? widget.accent.withValues(alpha: 0.45)
              : const Color(0x22FFFFFF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 18, color: widget.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF8B93A1),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onTap != null)
            Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: widget.accent.withValues(alpha: 0.8)),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.onTap == null
          ? child
          : GestureDetector(onTap: widget.onTap, child: child),
    );
  }
}

class _PrimaryCta extends StatefulWidget {
  const _PrimaryCta({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<_PrimaryCta> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: _hover
                  ? const [Color(0xFF4DB88A), Color(0xFF2F8F66)]
                  : const [Color(0xFF3D9970), Color(0xFF2A7A57)],
            ),
            boxShadow: [
              BoxShadow(
                color: _green.withValues(alpha: _hover ? 0.45 : 0.28),
                blurRadius: _hover ? 22 : 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF9AA3B2)),
      ),
    );
  }
}

class _ProtocolPill extends StatelessWidget {
  const _ProtocolPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _WelcomeAtmosphere extends StatefulWidget {
  const _WelcomeAtmosphere();

  @override
  State<_WelcomeAtmosphere> createState() => _WelcomeAtmosphereState();
}

class _WelcomeAtmosphereState extends State<_WelcomeAtmosphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final drift = math.sin(_pulse.value * math.pi) * 24;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _GridPainter(opacity: 0.045)),
            Positioned(
              left: -80 + drift,
              top: -40,
              child: _GlowBlob(
                size: 340,
                color: const Color(0xFF1B7A5A).withValues(alpha: 0.22),
              ),
            ),
            Positioned(
              right: -60 - drift,
              top: 80,
              child: _GlowBlob(
                size: 300,
                color: const Color(0xFF5B9BD5).withValues(alpha: 0.18),
              ),
            ),
            Positioned(
              right: 120,
              bottom: -100,
              child: _GlowBlob(
                size: 280,
                color: const Color(0xFFE6B422).withValues(alpha: 0.08),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x000A0C10), Color(0xCC0A0C10)],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.opacity});
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
