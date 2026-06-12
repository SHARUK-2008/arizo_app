import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../screens/home_screen.dart';

class FeatureCard extends StatefulWidget {
  final FeatureData feature;
  final AnimationController pulseController;
  final VoidCallback onTap;

  const FeatureCard({
    super.key,
    required this.feature,
    required this.pulseController,
    required this.onTap,
  });

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark1,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: feature.isBuilt
                  ? feature.gradientColors[0].withOpacity(0.25)
                  : AppTheme.borderDark,
              width: feature.isBuilt ? 1.5 : 1,
            ),
          ),
          child: Stack(
            children: [
              // Background glow for built features
              if (feature.isBuilt)
                Positioned(
                  top: -30,
                  right: -30,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: feature.gradientColors[0].withOpacity(0.06),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Icon
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: feature.isBuilt
                                ? LinearGradient(
                              colors: feature.gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                                : null,
                            color: feature.isBuilt
                                ? null
                                : AppTheme.surfaceDark2,
                            border: feature.isBuilt
                                ? null
                                : Border.all(color: AppTheme.borderDark),
                          ),
                          child: Icon(
                            feature.icon,
                            color: feature.isBuilt
                                ? Colors.white
                                : AppTheme.textTertiary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                feature.title,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                feature.subtitle,
                                style: TextStyle(
                                  color: feature.isBuilt
                                      ? feature.gradientColors[0]
                                      : AppTheme.textTertiary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Status badge
                        _StatusBadge(
                          isBuilt: feature.isBuilt,
                          isLive: feature.isLive,
                          pulseController: widget.pulseController,
                          color: feature.gradientColors[0],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      feature.description,
                      style: TextStyle(
                        color: feature.isBuilt
                            ? AppTheme.textSecondary
                            : AppTheme.textTertiary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Tags
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: feature.tags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: feature.isBuilt
                                ? feature.gradientColors[0].withOpacity(0.1)
                                : AppTheme.surfaceDark2,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: feature.isBuilt
                                  ? feature.gradientColors[0].withOpacity(0.25)
                                  : AppTheme.borderDark,
                            ),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: feature.isBuilt
                                  ? feature.gradientColors[0]
                                  : AppTheme.textTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    if (!feature.isBuilt) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            color: AppTheme.textTertiary,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Building Day 2–5',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (feature.isBuilt) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: feature.gradientColors,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Launch Feature',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 15,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isBuilt;
  final bool isLive;
  final AnimationController pulseController;
  final Color color;

  const _StatusBadge({
    required this.isBuilt,
    required this.isLive,
    required this.pulseController,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!isBuilt) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.borderDark),
        ),
        child: Text(
          'SOON',
          style: TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1 + 0.05 * pulseController.value),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: color.withOpacity(0.3 + 0.1 * pulseController.value),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'READY',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}