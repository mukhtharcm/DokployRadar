import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../models/dokploy_models.dart';
import '../services/dokploy_api_client.dart';
import '../utils/formatters.dart';
import '../widgets/status_pill.dart';

class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({
    super.key,
    required this.service,
    required this.instance,
    required this.recentWindow,
  });

  final MonitoredService service;
  final DokployInstance instance;
  final Duration recentWindow;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late Future<List<DokployDeploymentRecord>> _historyFuture;
  late Future<ServiceInspectorData> _inspectorFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final client = DokployApiClient(instance: widget.instance);
    _historyFuture = client.fetchDeploymentHistory(widget.service);
    _inspectorFuture = client.fetchInspectorDetail(widget.service);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait<void>([
      _historyFuture.then((_) {}),
      _inspectorFuture.then((_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.service.group(DateTime.now(), widget.recentWindow);
    final color = colorForServiceGroup(group, Theme.of(context).colorScheme);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.service.name),
        actions: [
          IconButton(
            tooltip: 'Refresh details',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.service.name,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        StatusPill(
                          label: widget.service.statusLabel(DateTime.now(), widget.recentWindow),
                          color: color,
                          icon: iconForServiceGroup(group),
                        ),
                      ],
                    ),
                    if (widget.service.appName case final String appName when appName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        appName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(label: widget.service.serviceType.displayName),
                        _InfoChip(label: widget.service.instanceName),
                        _InfoChip(label: widget.service.projectName),
                        _InfoChip(label: widget.service.environmentName),
                        _InfoChip(
                          label: widget.service.lastActivityDate == null
                              ? 'No recent deployment'
                              : 'Last activity ${formatRelativeTime(widget.service.lastActivityDate)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'Inspector',
              subtitle: 'Configuration and runtime details pulled from Dokploy.',
            ),
            const SizedBox(height: 12),
            FutureBuilder<ServiceInspectorData>(
              future: _inspectorFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingCard(label: 'Loading inspector details…');
                }
                if (snapshot.hasError) {
                  return _ErrorCard(message: snapshot.error.toString());
                }

                final inspector = snapshot.data!;
                if (inspector.unsupportedMessage case final String message when message.isNotEmpty) {
                  return _InfoCard(
                    title: 'Limited detail',
                    message: message,
                  );
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KeyValueWrap(
                          pairs: {
                            'Source': inspector.sourceType,
                            'Config': inspector.configurationType,
                            'Repository': inspector.repository,
                            'Branch': inspector.branch,
                            'Auto deploy': yesNoLabel(inspector.autoDeployEnabled),
                            'Preview deploys': yesNoLabel(inspector.previewDeploymentsEnabled),
                            'Deployments': inspector.deploymentCount?.toString(),
                            'Previews': inspector.previewDeploymentCount?.toString(),
                            'Env vars': '${inspector.environmentVariableCount}',
                            'Mounts': '${inspector.mountCount}',
                            'Watch paths': '${inspector.watchPathCount}',
                          },
                        ),
                        if (inspector.domainLabels.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _ChipSection(title: 'Domains', values: inspector.domainLabels),
                        ],
                        if (inspector.portLabels.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _ChipSection(title: 'Ports', values: inspector.portLabels),
                        ],
                        if (inspector.watchPaths.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _ChipSection(title: 'Watch paths', values: inspector.watchPaths),
                        ],
                        if (inspector.composeServiceNames.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _ChipSection(title: 'Compose services', values: inspector.composeServiceNames),
                        ],
                        if (inspector.renderedCompose case final String compose when compose.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Rendered compose'),
                            subtitle: const Text('Tap to inspect the generated compose output'),
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: SelectableText(
                                  compose,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontFamily: 'monospace',
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'Deployment history',
              subtitle: 'Recent runs and their outcomes for this service.',
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<DokployDeploymentRecord>>(
              future: _historyFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingCard(label: 'Loading deployment history…');
                }
                if (snapshot.hasError) {
                  return _ErrorCard(message: snapshot.error.toString());
                }

                final history = snapshot.data!;
                if (history.isEmpty) {
                  return const _InfoCard(
                    title: 'No history returned',
                    message: 'Dokploy did not return deployment records for this service yet.',
                  );
                }

                return Column(
                  children: history.map((record) {
                    final statusColor = switch (record.status) {
                      DokployDeploymentStatus.running => Theme.of(context).colorScheme.primary,
                      DokployDeploymentStatus.done => Colors.green.shade600,
                      DokployDeploymentStatus.error => Theme.of(context).colorScheme.error,
                      DokployDeploymentStatus.cancelled => Colors.orange.shade700,
                    };

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      record.title,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  StatusPill(
                                    label: record.status.name.toUpperCase(),
                                    color: statusColor,
                                    icon: switch (record.status) {
                                      DokployDeploymentStatus.running => Icons.sync_rounded,
                                      DokployDeploymentStatus.done => Icons.check_circle_rounded,
                                      DokployDeploymentStatus.error => Icons.error_rounded,
                                      DokployDeploymentStatus.cancelled => Icons.cancel_rounded,
                                    },
                                  ),
                                ],
                              ),
                              if (record.description case final String description when description.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(description),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _InfoChip(label: 'Created ${formatFullDateTime(record.createdAt)}'),
                                  if (record.startedAt != null)
                                    _InfoChip(label: 'Started ${formatFullDateTime(record.startedAt)}'),
                                  if (record.finishedAt != null)
                                    _InfoChip(label: 'Finished ${formatFullDateTime(record.finishedAt)}'),
                                ],
                              ),
                              if (record.errorMessage case final String errorMessage when errorMessage.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  errorMessage,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
      ],
    );
  }
}

class _KeyValueWrap extends StatelessWidget {
  const _KeyValueWrap({required this.pairs});

  final Map<String, String?> pairs;

  @override
  Widget build(BuildContext context) {
    final visiblePairs = pairs.entries.where((entry) => entry.value != null && entry.value!.trim().isNotEmpty);
    if (visiblePairs.isEmpty) {
      return Text(
        'Dokploy did not return structured inspector fields for this service.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: visiblePairs
          .map(
            (entry) => _InfoChip(label: '${entry.key}: ${entry.value!}'),
          )
          .toList(),
    );
  }
}

class _ChipSection extends StatelessWidget {
  const _ChipSection({
    required this.title,
    required this.values,
  });

  final String title;
  final List<String> values;

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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((value) => _InfoChip(label: value)).toList(),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircularProgressIndicator.adaptive(),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_rounded, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}
