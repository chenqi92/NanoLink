import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../design/nano_tokens.dart';
import '../widgets/nano/nano_card.dart';
import 'add_server_page.dart';

/// First-run screen: brand intro + feature highlights + "add server" CTA.
class ServerWelcomeScreen extends StatelessWidget {
  const ServerWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final features = <List<dynamic>>[
      [
        Icons.dashboard_rounded,
        'welcome.featureMetricsTitle'.tr(),
        'welcome.featureMetricsDesc'.tr()
      ],
      [
        Icons.terminal_rounded,
        'welcome.featureTerminalTitle'.tr(),
        'welcome.featureTerminalDesc'.tr()
      ],
      [
        Icons.notifications_active_rounded,
        'welcome.featureAuditTitle'.tr(),
        'welcome.featureAuditDesc'.tr()
      ],
    ];
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 8),
                    child: Column(
                      crossAxisAlignment: t.isIOS
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        _BrandMark(size: t.isIOS ? 72 : 64, t: t),
                        const SizedBox(height: 26),
                        Text('NanoLink',
                            textAlign:
                                t.isIOS ? TextAlign.center : TextAlign.start,
                            style: TextStyle(
                                fontSize: t.isIOS ? 32 : 36,
                                fontWeight: t.displayWeight,
                                letterSpacing: t.displayTracking,
                                height: 1.1,
                                color: t.fg)),
                        const SizedBox(height: 10),
                        Text('welcome.tagline'.tr(),
                            textAlign:
                                t.isIOS ? TextAlign.center : TextAlign.start,
                            style: TextStyle(
                                fontSize: 15.5, color: t.fg3, height: 1.5)),
                        const SizedBox(height: 28),
                        for (final f in features)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: NanoCard(
                              outlined: true,
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  NanoIconBox(f[0] as IconData,
                                      size: 40, iconSize: 20, fg: t.accent),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(f[1] as String,
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: t.fg)),
                                        const SizedBox(height: 2),
                                        Text(f[2] as String,
                                            style: TextStyle(
                                                fontSize: 13, color: t.fg3)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AddServerPage()),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 22),
                          label: Text('welcome.addServer'.tr(),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.accent,
                            foregroundColor: t.onAccent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(t.buttonRadius),
                            ),
                          ),
                        ),
                      ),
                      if (t.isIOS)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text('welcome.chooseMethodHint'.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: t.fg4)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand mark: gradient rounded square containing a 4-rounded-square grid
/// glyph with a small accent dot, matching MDBrand / IOSBrand in the mockups.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size, required this.t});

  final double size;
  final NanoTokens t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.accent, t.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * (t.isIOS ? 0.22 : 0.32)),
        boxShadow: t.isIOS
            ? [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Center(
        child: CustomPaint(
          size: Size.square(size * 0.55),
          // Mark color rides on the gradient (white on iOS, deep blue on MD).
          painter: _BrandGlyphPainter(mark: t.onAccent, dot: t.accent),
        ),
      ),
    );
  }
}

/// Paints the 4-square grid + accent dot from a 24x24 design viewBox.
class _BrandGlyphPainter extends CustomPainter {
  const _BrandGlyphPainter({required this.mark, required this.dot});

  final Color mark;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0; // viewBox 24 -> px scale
    final r = Radius.circular(1.5 * s);
    final paint = Paint()..isAntiAlias = true;

    void square(double x, double y, double opacity) {
      paint.color = mark.withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * s, y * s, 8 * s, 8 * s),
          r,
        ),
        paint,
      );
    }

    square(3, 3, 1.0);
    square(13, 3, 0.55);
    square(3, 13, 0.55);
    square(13, 13, 0.9);

    paint.color = dot;
    canvas.drawCircle(Offset(17 * s, 17 * s), 1.5 * s, paint);
  }

  @override
  bool shouldRepaint(_BrandGlyphPainter old) =>
      old.mark != mark || old.dot != dot;
}
