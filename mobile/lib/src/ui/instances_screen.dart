import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../models/dokploy_models.dart';
import '../services/dashboard_controller.dart';
import '../utils/formatters.dart';
import 'instance_editor_screen.dart';

class InstancesScreen extends StatelessWidget {
  const InstancesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Instances & settings'),
        actions: [
          IconButton(
            tooltip: 'Add instance',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const InstanceEditorScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            'INSTANCES',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          if (controller.instances.isEmpty)
            _SettingsEmptyState(
              onAddPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const InstanceEditorScreen(),
                  ),
                );
              },
            )
          else
            ...controller.instances.map(
              (instance) {
                final snapshot = controller.snapshots
                    .where((entry) => entry.instance.id == instance.id)
                    .firstOrNull;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _InstanceManagementCard(
                    instance: instance,
                    snapshot: snapshot,
                    recentWindow: controller.settings.recentWindow,
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          Text(
            'MONITORING',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _DropdownSetting(
                    title: 'Refresh interval',
                    subtitle: 'How often the mobile app polls your Dokploy instances.',
                    value: controller.settings.refreshIntervalSeconds,
                    options: const [30, 60, 120, 300],
                    labelBuilder: formatIntervalLabel,
                    onChanged: (value) => unawaited(
                      controller.updateSettings(refreshIntervalSeconds: value),
                    ),
                  ),
                  Divider(
                    height: 28,
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  _DropdownSetting(
                    title: 'Recent deployment window',
                    subtitle: 'How long a finished deployment should stay marked as recent.',
                    value: controller.settings.recentWindowMinutes,
                    options: const [30, 60, 180, 360],
                    labelBuilder: formatRecentWindowLabel,
                    onChanged: (value) => unawaited(
                      controller.updateSettings(recentWindowMinutes: value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            controller.lastRefresh == null
                ? 'No successful refresh yet'
                : 'Last refresh ${formatRelativeTime(controller.lastRefresh)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _InstanceManagementCard extends StatelessWidget {
  const _InstanceManagementCard({
    required this.instance,
    required this.snapshot,
    required this.recentWindow,
  });

  final DokployInstance instance;
  final InstanceSnapshot? snapshot;
  final Duration recentWindow;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<DashboardController>();
    final scheme = Theme.of(context).colorScheme;
    final hasIssue = snapshot?.errorMessage != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (hasIssue ? scheme.error : scheme.primary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasIssue ? Icons.error_rounded : Icons.dns_rounded,
                    color: hasIssue ? scheme.error : scheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instance.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        instance.hostLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: instance.isEnabled,
                  onChanged: (value) => unawaited(
                    controller.toggleInstanceEnabled(instance.id, value),
                  ),
                ),
              ],
            ),
            if (snapshot != null) ...[
              const SizedBox(height: 10),
              Text(
                '${snapshot!.entries.length} services · ${snapshot!.deployingCount} deploying · ${snapshot!.recentCount(recentWindow)} recent · ${snapshot!.failedCount} failed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
              ),
            ],
            if (snapshot?.errorMessage case final String message when message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => InstanceEditorScreen(instance: instance),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(controller.selectInstance(instance.id)),
                  icon: const Icon(Icons.filter_alt_rounded),
                  label: const Text('Focus'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Delete instance?'),
                        content: Text('Remove ${instance.name} from Dokploy Radar mobile?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      await controller.deleteInstance(instance.id);
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownSetting extends StatelessWidget {
  const _DropdownSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int value;
  final List<int> options;
  final String Function(int value) labelBuilder;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: value,
          items: options
              .map(
                (option) => DropdownMenuItem<int>(
                  value: option,
                  child: Text(labelBuilder(option)),
                ),
              )
              .toList(),
          onChanged: (newValue) {
            if (newValue != null) {
              onChanged(newValue);
            }
          },
        ),
      ],
    );
  }
}

class _SettingsEmptyState extends StatelessWidget {
  const _SettingsEmptyState({required this.onAddPressed});

  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No Dokploy instances yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add one or more Dokploy instances to start monitoring deployments from mobile.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add instance'),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
