import 'package:flutter/material.dart';

import '../models/dokploy_models.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

Color colorForServiceGroup(MonitoredServiceGroup group, ColorScheme scheme) {
  return switch (group) {
    MonitoredServiceGroup.deploying => scheme.primary,
    MonitoredServiceGroup.recent => Colors.green.shade600,
    MonitoredServiceGroup.failed => scheme.error,
    MonitoredServiceGroup.steady => scheme.secondary,
  };
}

Color colorForActivityState(DokployActivityState state, ColorScheme scheme) {
  return switch (state) {
    DokployActivityState.queued => Colors.orange.shade700,
    DokployActivityState.deploying => scheme.primary,
    DokployActivityState.failed => scheme.error,
    DokployActivityState.recent => Colors.green.shade600,
    DokployActivityState.cancelled => Colors.orange.shade800,
    DokployActivityState.steady => scheme.secondary,
  };
}

IconData iconForServiceGroup(MonitoredServiceGroup group) {
  return switch (group) {
    MonitoredServiceGroup.deploying => Icons.sync_rounded,
    MonitoredServiceGroup.recent => Icons.check_circle_rounded,
    MonitoredServiceGroup.failed => Icons.error_rounded,
    MonitoredServiceGroup.steady => Icons.check_circle_outline_rounded,
  };
}

IconData iconForActivityState(DokployActivityState state) {
  return switch (state) {
    DokployActivityState.queued => Icons.schedule_rounded,
    DokployActivityState.deploying => Icons.sync_rounded,
    DokployActivityState.failed => Icons.error_rounded,
    DokployActivityState.recent => Icons.task_alt_rounded,
    DokployActivityState.cancelled => Icons.cancel_rounded,
    DokployActivityState.steady => Icons.history_rounded,
  };
}

IconData iconForServiceType(DokployServiceType type) {
  return switch (type) {
    DokployServiceType.application => Icons.apps_rounded,
    DokployServiceType.compose => Icons.inventory_2_rounded,
    DokployServiceType.mariadb ||
    DokployServiceType.mongo ||
    DokployServiceType.mysql ||
    DokployServiceType.postgres ||
    DokployServiceType.redis ||
    DokployServiceType.libsql => Icons.storage_rounded,
  };
}
