import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../models/dokploy_models.dart';
import '../services/dashboard_controller.dart';
import '../utils/formatters.dart';
import '../widgets/status_pill.dart';
import 'instances_screen.dart';
import 'service_detail_screen.dart';

enum _DashboardTab { overview, services, activity }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _serviceSearchController =
      TextEditingController();
  final TextEditingController _activitySearchController =
      TextEditingController();

  int _currentIndex = 0;

  @override
  void dispose() {
    _serviceSearchController.dispose();
    _activitySearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();
    final selectedInstance = controller.selectedInstance;
    final subtitle = selectedInstance?.name ?? 'All instances';
    final initializationError = controller.initializationError;
    final lastRefreshLabel = controller.lastRefresh == null
        ? 'Waiting for first refresh'
        : 'Updated ${formatRelativeTime(controller.lastRefresh)}';

    if (!controller.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dokploy Radar'),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.isRefreshing
                ? null
                : () => unawaited(controller.refresh()),
            icon: controller.isRefreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Instances and settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const InstancesScreen(),
                ),
              );
            },
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: switch (_DashboardTab.values[_currentIndex]) {
        _DashboardTab.overview => _OverviewTab(
          controller: controller,
          initializationError: initializationError,
          lastRefreshLabel: lastRefreshLabel,
          onOpenInstances: _openInstances,
          onOpenService: _openService,
          onFocusInstance: (instanceId) {
            unawaited(controller.selectInstance(instanceId));
            setState(() => _currentIndex = _DashboardTab.services.index);
          },
        ),
        _DashboardTab.services => _ServicesTab(
          controller: controller,
          initializationError: initializationError,
          searchController: _serviceSearchController,
          onOpenInstances: _openInstances,
          onOpenService: _openService,
        ),
        _DashboardTab.activity => _ActivityTab(
          controller: controller,
          initializationError: initializationError,
          searchController: _activitySearchController,
          onOpenInstances: _openInstances,
          onOpenService: _openService,
        ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_rounded),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'Activity',
          ),
        ],
      ),
    );
  }

  void _openInstances() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const InstancesScreen()));
  }

  void _openService(
    MonitoredService service,
    DokployInstance instance,
    Duration recentWindow,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceDetailScreen(
          service: service,
          instance: instance,
          recentWindow: recentWindow,
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.controller,
    required this.initializationError,
    required this.lastRefreshLabel,
    required this.onOpenInstances,
    required this.onOpenService,
    required this.onFocusInstance,
  });

  final DashboardController controller;
  final String? initializationError;
  final String lastRefreshLabel;
  final VoidCallback onOpenInstances;
  final void Function(
    MonitoredService service,
    DokployInstance instance,
    Duration recentWindow,
  )
  onOpenService;
  final void Function(String instanceId) onFocusInstance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator.adaptive(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _StatusHeader(
            subtitle: lastRefreshLabel,
            actionLabel: controller.instances.isEmpty
                ? 'Add instance'
                : 'Manage',
            onAction: onOpenInstances,
          ),
          if (initializationError case final String message
              when message.isNotEmpty) ...[
            const SizedBox(height: 16),
            _InitializationIssueBanner(
              message: message,
              onOpenInstances: onOpenInstances,
            ),
          ],
          if (controller.issueSnapshots.isNotEmpty) ...[
            const SizedBox(height: 16),
            _IssueBanner(
              snapshots: controller.issueSnapshots,
              onRetry: controller.refresh,
            ),
          ],
          const SizedBox(height: 18),
          if (controller.instances.isEmpty)
            _EmptyStateCard(
              icon: Icons.radar_rounded,
              title: 'Add your first Dokploy instance',
              description:
                  'Connect a Dokploy API token to start tracking deployments, failures, and recent rollouts from mobile.',
              primaryLabel: 'Add instance',
              onPrimaryPressed: onOpenInstances,
            )
          else ...[
            // Gradient stats banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary,
                    scheme.primary.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.20),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.radar_rounded,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${controller.activeInstancesCount} instance${controller.activeInstancesCount == 1 ? '' : 's'} monitored',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _BannerStat(
                        value: '${controller.deployingCount}',
                        label: 'Deploying',
                      ),
                      _BannerStat(
                        value: '${controller.recentCount}',
                        label: 'Recent',
                      ),
                      _BannerStat(
                        value: '${controller.failedCount}',
                        label: 'Failed',
                      ),
                      _BannerStat(
                        value: '${controller.queuedCount}',
                        label: 'Queued',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Instances',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...controller.snapshots.map(
              (snapshot) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InstanceSnapshotCard(
                  snapshot: snapshot,
                  recentWindow: controller.settings.recentWindow,
                  onTap: () => onFocusInstance(snapshot.instance.id),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Recent service highlights',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...controller.allServices
                .take(6)
                .map(
                  (service) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ServiceCard(
                      service: service,
                      recentWindow: controller.settings.recentWindow,
                      onTap: () {
                        final instance = controller.instances
                            .where((item) => item.id == service.instanceId)
                            .firstOrNull;
                        if (instance != null) {
                          onOpenService(
                            service,
                            instance,
                            controller.settings.recentWindow,
                          );
                        }
                      },
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _ServicesTab extends StatelessWidget {
  const _ServicesTab({
    required this.controller,
    required this.initializationError,
    required this.searchController,
    required this.onOpenInstances,
    required this.onOpenService,
  });

  final DashboardController controller;
  final String? initializationError;
  final TextEditingController searchController;
  final VoidCallback onOpenInstances;
  final void Function(
    MonitoredService service,
    DokployInstance instance,
    Duration recentWindow,
  )
  onOpenService;

  @override
  Widget build(BuildContext context) {
    final services = controller.filteredServices;

    searchController.value = searchController.value.copyWith(
      text: controller.serviceSearch,
      selection: TextSelection.collapsed(
        offset: controller.serviceSearch.length,
      ),
      composing: TextRange.empty,
    );

    return RefreshIndicator.adaptive(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _ScopeSelector(controller: controller),
          const SizedBox(height: 16),
          _SearchField(
            controller: searchController,
            hintText: 'Search services, projects, or instances',
            onChanged: controller.updateServiceSearch,
          ),
          const SizedBox(height: 12),
          _ServiceFilterRow(controller: controller),
          if (initializationError case final String message
              when message.isNotEmpty) ...[
            const SizedBox(height: 16),
            _InitializationIssueBanner(
              message: message,
              onOpenInstances: onOpenInstances,
            ),
          ],
          if (controller.issueSnapshots.isNotEmpty) ...[
            const SizedBox(height: 16),
            _IssueBanner(
              snapshots: controller.issueSnapshots,
              onRetry: controller.refresh,
            ),
          ],
          const SizedBox(height: 18),
          if (controller.instances.isEmpty)
            _EmptyStateCard(
              icon: Icons.dns_rounded,
              title: 'No instances connected',
              description:
                  'Add at least one Dokploy instance before browsing services.',
              primaryLabel: 'Add instance',
              onPrimaryPressed: onOpenInstances,
            )
          else if (services.isEmpty)
            _EmptyStateCard(
              icon: Icons.search_off_rounded,
              title: 'No matching services',
              description:
                  'Try another search term or switch to a different status filter.',
              primaryLabel: 'Clear filters',
              onPrimaryPressed: () {
                controller.updateServiceSearch('');
                controller.updateServiceFilter(ServiceFilter.all);
              },
            )
          else ...[
            ...services.map(
              (service) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ServiceCard(
                  service: service,
                  recentWindow: controller.settings.recentWindow,
                  onTap: () {
                    final instance = controller.instances
                        .where((item) => item.id == service.instanceId)
                        .firstOrNull;
                    if (instance != null) {
                      onOpenService(
                        service,
                        instance,
                        controller.settings.recentWindow,
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.controller,
    required this.initializationError,
    required this.searchController,
    required this.onOpenInstances,
    required this.onOpenService,
  });

  final DashboardController controller;
  final String? initializationError;
  final TextEditingController searchController;
  final VoidCallback onOpenInstances;
  final void Function(
    MonitoredService service,
    DokployInstance instance,
    Duration recentWindow,
  )
  onOpenService;

  @override
  Widget build(BuildContext context) {
    final items = controller.filteredActivity;

    searchController.value = searchController.value.copyWith(
      text: controller.activitySearch,
      selection: TextSelection.collapsed(
        offset: controller.activitySearch.length,
      ),
      composing: TextRange.empty,
    );

    return RefreshIndicator.adaptive(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _ScopeSelector(controller: controller),
          const SizedBox(height: 16),
          _SearchField(
            controller: searchController,
            hintText: 'Search activity, service names, or instances',
            onChanged: controller.updateActivitySearch,
          ),
          const SizedBox(height: 12),
          _ActivityFilterRow(controller: controller),
          if (initializationError case final String message
              when message.isNotEmpty) ...[
            const SizedBox(height: 16),
            _InitializationIssueBanner(
              message: message,
              onOpenInstances: onOpenInstances,
            ),
          ],
          if (controller.issueSnapshots.isNotEmpty) ...[
            const SizedBox(height: 16),
            _IssueBanner(
              snapshots: controller.issueSnapshots,
              onRetry: controller.refresh,
            ),
          ],
          const SizedBox(height: 18),
          if (controller.instances.isEmpty)
            _EmptyStateCard(
              icon: Icons.history_toggle_off_rounded,
              title: 'No activity yet',
              description:
                  'Activity appears after you connect a Dokploy instance and Dokploy returns deployment events.',
              primaryLabel: 'Add instance',
              onPrimaryPressed: onOpenInstances,
            )
          else if (items.isEmpty)
            _EmptyStateCard(
              icon: Icons.filter_alt_off_rounded,
              title: 'No matching activity',
              description:
                  'Try a broader search or switch to a different activity filter.',
              primaryLabel: 'Clear filters',
              onPrimaryPressed: () {
                controller.updateActivitySearch('');
                controller.updateActivityFilter(ActivityFilter.all);
              },
            )
          else ...[
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ActivityCard(
                  item: item,
                  onTap: () async {
                    final relatedService = controller.serviceForActivity(item);
                    await showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (sheetContext) => _ActivityDetailsSheet(
                        item: item,
                        relatedService: relatedService,
                        onInspectService: relatedService == null
                            ? null
                            : () {
                                Navigator.of(sheetContext).pop();
                                final instance = controller.instances
                                    .where(
                                      (entry) =>
                                          entry.id == relatedService.instanceId,
                                    )
                                    .firstOrNull;
                                if (instance != null) {
                                  onOpenService(
                                    relatedService,
                                    instance,
                                    controller.settings.recentWindow,
                                  );
                                }
                              },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _BannerStat extends StatelessWidget {
  const _BannerStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.instances.length <= 1) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: Text(
              'All',
              style: TextStyle(
                color: controller.selectedInstanceId == null
                    ? scheme.onPrimary
                    : scheme.onSurface,
              ),
            ),
            selected: controller.selectedInstanceId == null,
            onSelected: (_) => unawaited(controller.selectInstance(null)),
          ),
          const SizedBox(width: 8),
          ...controller.instances.map(
            (instance) {
              final isSelected = controller.selectedInstanceId == instance.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    instance.name,
                    style: TextStyle(
                      color: isSelected ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) => unawaited(
                    controller.selectInstance(
                      isSelected ? null : instance.id,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}

class _ServiceFilterRow extends StatelessWidget {
  const _ServiceFilterRow({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final recentWindow = controller.settings.recentWindow;
    final services = controller.allServices.where((service) {
      if (controller.selectedInstanceId != null) {
        return service.instanceId == controller.selectedInstanceId;
      }
      return true;
    }).toList();

    int countFor(ServiceFilter filter) {
      return switch (filter) {
        ServiceFilter.all => services.length,
        ServiceFilter.deploying =>
          services
              .where(
                (service) =>
                    service.group(now, recentWindow) ==
                    MonitoredServiceGroup.deploying,
              )
              .length,
        ServiceFilter.recent =>
          services
              .where(
                (service) =>
                    service.group(now, recentWindow) ==
                    MonitoredServiceGroup.recent,
              )
              .length,
        ServiceFilter.failed =>
          services
              .where(
                (service) =>
                    service.group(now, recentWindow) ==
                    MonitoredServiceGroup.failed,
              )
              .length,
        ServiceFilter.steady =>
          services
              .where(
                (service) =>
                    service.group(now, recentWindow) ==
                    MonitoredServiceGroup.steady,
              )
              .length,
      };
    }

    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ServiceFilter.values.map((filter) {
          final isSelected = controller.serviceFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                '${filter.label} (${countFor(filter)})',
                style: TextStyle(
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => controller.updateServiceFilter(filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActivityFilterRow extends StatelessWidget {
  const _ActivityFilterRow({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.allActivity.where((item) {
      if (controller.selectedInstanceId != null) {
        return item.instanceId == controller.selectedInstanceId;
      }
      return true;
    }).toList();

    int countFor(ActivityFilter filter) {
      return switch (filter) {
        ActivityFilter.all => items.length,
        ActivityFilter.active =>
          items
              .where(
                (item) =>
                    item.state == DokployActivityState.queued ||
                    item.state == DokployActivityState.deploying,
              )
              .length,
        ActivityFilter.failures =>
          items
              .where((item) => item.state == DokployActivityState.failed)
              .length,
        ActivityFilter.completed =>
          items
              .where((item) => item.state == DokployActivityState.recent)
              .length,
        ActivityFilter.older =>
          items
              .where(
                (item) =>
                    item.state == DokployActivityState.steady ||
                    item.state == DokployActivityState.cancelled,
              )
              .length,
      };
    }

    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ActivityFilter.values.map((filter) {
          final isSelected = controller.activityFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                '${filter.label} (${countFor(filter)})',
                style: TextStyle(
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => controller.updateActivityFilter(filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _IssueBanner extends StatelessWidget {
  const _IssueBanner({required this.snapshots, required this.onRetry});

  final List<InstanceSnapshot> snapshots;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_rounded, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Instance issues',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
            const SizedBox(height: 10),
            ...snapshots.map(
              (snapshot) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${snapshot.instance.name}: ${snapshot.errorMessage}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitializationIssueBanner extends StatelessWidget {
  const _InitializationIssueBanner({
    required this.message,
    required this.onOpenInstances,
  });

  final String message;
  final VoidCallback onOpenInstances;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sd_storage_rounded, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saved data issue',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpenInstances,
                  child: const Text('Instances'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstanceSnapshotCard extends StatelessWidget {
  const _InstanceSnapshotCard({
    required this.snapshot,
    required this.recentWindow,
    required this.onTap,
  });

  final InstanceSnapshot snapshot;
  final Duration recentWindow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = snapshot.errorMessage != null
        ? scheme.error
        : !snapshot.instance.isEnabled
        ? scheme.secondary
        : snapshot.deployingCount > 0
        ? scheme.primary
        : snapshot.failedCount > 0
        ? scheme.error
        : Colors.green.shade600;

    final statusLabel = snapshot.errorMessage != null
        ? 'Issue'
        : !snapshot.instance.isEnabled
        ? 'Paused'
        : snapshot.deployingCount > 0
        ? 'Deploying'
        : snapshot.failedCount > 0
        ? 'Needs attention'
        : 'Healthy';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snapshot.instance.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  StatusPill(
                    label: statusLabel,
                    color: statusColor,
                    icon: Icons.circle_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                snapshot.instance.hostLabel,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (snapshot.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  snapshot.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '${snapshot.entries.length} services · ${snapshot.failedCount} failed · ${snapshot.deployingCount} deploying',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.recentWindow,
    required this.onTap,
  });

  final MonitoredService service;
  final Duration recentWindow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final group = service.group(now, recentWindow);
    final color = colorForServiceGroup(group, Theme.of(context).colorScheme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      service.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label: service.statusLabel(now, recentWindow),
                    color: color,
                    icon: iconForServiceGroup(group),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${service.projectName} / ${service.environmentName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (service.lastActivityDate != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Last activity ${formatRelativeTime(service.lastActivityDate)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item, required this.onTap});

  final DokployActivityItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorForActivityState(
      item.state,
      Theme.of(context).colorScheme,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.serviceName,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label: item.state.displayName,
                    color: color,
                    icon: iconForActivityState(item.state),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  formatRelativeTime(item.activityDate),
                  if (item.durationLabel != null) item.durationLabel!,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityDetailsSheet extends StatelessWidget {
  const _ActivityDetailsSheet({
    required this.item,
    required this.relatedService,
    required this.onInspectService,
  });

  final DokployActivityItem item;
  final MonitoredService? relatedService;
  final VoidCallback? onInspectService;

  @override
  Widget build(BuildContext context) {
    final color = colorForActivityState(
      item.state,
      Theme.of(context).colorScheme,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusPill(
              label: item.state.displayName,
              color: color,
              icon: iconForActivityState(item.state),
            ),
            const SizedBox(height: 16),
            Text(
              item.serviceName,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              item.subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _MetricChip(label: formatFullDateTime(item.activityDate)),
            if (item.durationLabel != null) ...[
              const SizedBox(height: 8),
              _MetricChip(label: 'Duration ${item.durationLabel!}'),
            ],
            if (item.description case final String description
                when description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(description),
            ],
            if (item.errorMessage case final String errorMessage
                when errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (onInspectService != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onInspectService,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Inspect service'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimaryPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimaryPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onPrimaryPressed,
              icon: const Icon(Icons.add_rounded),
              label: Text(primaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
