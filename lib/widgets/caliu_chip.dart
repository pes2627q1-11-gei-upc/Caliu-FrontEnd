import 'package:flutter/material.dart';
import '../theme/caliu_colors.dart';

class CaliuChip extends StatelessWidget {
  const CaliuChip({
    super.key,
    required this.label,
    this.filled = true,
  });

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? CaliuColors.chip : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: filled
            ? null
            : Border.all(color: CaliuColors.chip.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? Colors.white : CaliuColors.chip,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
