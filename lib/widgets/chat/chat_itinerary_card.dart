import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/chat_dates.dart';
import '../../data/chat_plan.dart';
import '../../theme/caliu_colors.dart';

/// Widget d'itinerari dins del xat (H.U #13, tasca #141): els passos del pla
/// en ordre, amb l'hora, el lloc i el desplaçament entre ells. Cada pas que
/// té esdeveniment obre la seva fitxa.
class ChatItineraryCard extends StatelessWidget {
  const ChatItineraryCard({
    super.key,
    required this.plan,
    required this.onOpenStep,
    this.onOpenRoute,
    this.now,
  });

  final ChatPlan plan;
  final ValueChanged<ChatPlanStep> onOpenStep;

  /// Com obrir la ruta a Google Maps. Per defecte, el navegador o l'app.
  final Future<void> Function(Uri uri)? onOpenRoute;

  /// Per als tests; per defecte, `DateTime.now()`.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final date = plan.date ?? plan.steps.first.start?.toLocal();
    final count = plan.steps.length;
    final subtitle = [
      if (date != null) chatDayLabel(date, now ?? DateTime.now()),
      count == 1 ? '1 parada' : '$count parades',
    ].join(' · ');
    final route = plan.directionsUri;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: CaliuColors.red.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route, color: CaliuColors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Itinerari',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: CaliuColors.maroonDeep,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: CaliuColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (index, step) in plan.steps.indexed) ...[
              if (index > 0 && _travelText(step) != null)
                _TravelRow(text: _travelText(step)!),
              _StepTile(
                key: ValueKey('plan-step-${step.order}'),
                step: step,
                onTap: step.canOpen ? () => onOpenStep(step) : null,
              ),
            ],
            if (route != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('plan-route'),
                  onPressed: () => (onOpenRoute ?? _launch)(route),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Veure la ruta a Google Maps'),
                  style: TextButton.styleFrom(
                    foregroundColor: CaliuColors.red,
                  ),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<void> _launch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// "400 m · 5 min a peu", "1,2 km · 15 min a peu". Null si no se sap.
  static String? _travelText(ChatPlanStep step) {
    final km = step.distanceKm;
    final minutes = step.travelMinutes;
    final parts = <String>[
      if (km != null)
        km < 1
            ? '${(km * 1000).round()} m'
            : '${km.toStringAsFixed(1).replaceAll('.', ',')} km',
      if (minutes != null) '$minutes min a peu',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _TravelRow extends StatelessWidget {
  const _TravelRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 2),
      child: Row(
        children: [
          const Icon(
            Icons.directions_walk,
            size: 14,
            color: CaliuColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(color: CaliuColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({super.key, required this.step, this.onTap});

  final ChatPlanStep step;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final start = step.start?.toLocal();
    final end = step.end?.toLocal();
    final hours = [
      if (start != null) chatTime(start),
      if (end != null) chatTime(end),
    ].join(' – ');
    final place = step.place;

    return Semantics(
      button: onTap != null,
      label: onTap != null ? 'Veure fitxa de ${step.title}' : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: CaliuColors.red,
                foregroundColor: Colors.white,
                child: Text(
                  '${step.order}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hours.isNotEmpty)
                      Text(
                        hours,
                        style: const TextStyle(
                          color: CaliuColors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      step.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: CaliuColors.maroonDeep,
                      ),
                    ),
                    if (place.isNotEmpty)
                      Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CaliuColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: CaliuColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
