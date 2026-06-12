import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class QuickStatsRow extends StatelessWidget {
  const QuickStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: const [
          _StatCard(
            value: '2/5',
            label: 'Features\nActive',
            color: AppTheme.primaryCyan,
          ),
          SizedBox(width: 12),
          _StatCard(
            value: '0',
            label: 'Hazards\nNearby',
            color: AppTheme.accentGreen,
          ),
          SizedBox(width: 12),
          _StatCard(
            value: '98%',
            label: 'Alert\nAccuracy',
            color: AppTheme.primaryBlue,
          ),
          SizedBox(width: 12),
          _StatCard(
            value: 'LOW',
            label: 'Risk\nLevel',
            color: AppTheme.accentAmber,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}