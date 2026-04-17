import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/app_models.dart';
import '../models/dokploy_models.dart';
import 'dokploy_api_client.dart';
import 'instance_store.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({required InstanceStore store}) : _store = store;

  final InstanceStore _store;
  final Uuid _uuid = const Uuid();

  DashboardSettings _settings = const DashboardSettings();
  List<DokployInstance> _instances = [];
  List<InstanceSnapshot> _snapshots = [];
  bool _isInitialized = false;
  bool _isRefreshing = false;
  DateTime? _lastRefresh;
  String? _selectedInstanceId;
  String? _initializationError;
  String _serviceSearch = '';
  String _activitySearch = '';
  ServiceFilter _serviceFilter = ServiceFilter.all;
  ActivityFilter _activityFilter = ActivityFilter.all;
  Timer? _refreshTimer;

  bool get isInitialized => _isInitialized;

  bool get isRefreshing => _isRefreshing;

  DateTime? get lastRefresh => _lastRefresh;

  DashboardSettings get settings => _settings;

  String? get initializationError => _initializationError;

  List<DokployInstance> get instances => List.unmodifiable(_instances);

  List<InstanceSnapshot> get snapshots => List.unmodifiable(_snapshots);

  String? get selectedInstanceId => _selectedInstanceId;

  DokployInstance? get selectedInstance {
    final selectedId = _selectedInstanceId;
    if (selectedId == null) {
      return null;
    }
    return _instances
        .where((instance) => instance.id == selectedId)
        .cast<DokployInstance?>()
        .firstOrNull;
  }

  String get serviceSearch => _serviceSearch;

  String get activitySearch => _activitySearch;

  ServiceFilter get serviceFilter => _serviceFilter;

  ActivityFilter get activityFilter => _activityFilter;

  List<InstanceSnapshot> get issueSnapshots {
    return _snapshots
        .where((snapshot) => snapshot.errorMessage != null)
        .toList();
  }

  int get activeInstancesCount =>
      _instances.where((instance) => instance.isEnabled).length;

  int get deployingCount =>
      allServices.where((service) => service.isDeploying).length;

  int get recentCount {
    final now = DateTime.now();
    return allServices
        .where((service) => service.isRecent(now, _settings.recentWindow))
        .length;
  }

  int get failedCount =>
      allServices.where((service) => service.isFailing).length;

  int get queuedCount => allActivity
      .where((item) => item.state == DokployActivityState.queued)
      .length;

  List<MonitoredService> get allServices {
    return DokploySorter.sortServices(
      _snapshots.expand((snapshot) => snapshot.entries),
      now: DateTime.now(),
      recentWindow: _settings.recentWindow,
    );
  }

  List<DokployActivityItem> get allActivity {
    final entryLookup = {
      for (final service in allServices) _activityLookupKey(service): service,
    };

    final items = <DokployActivityItem>[];
    final now = DateTime.now();
    for (final snapshot in _snapshots) {
      for (final deployment in snapshot.deployments) {
        items.add(
          DokployActivityItem.fromDeployment(
            deployment: deployment,
            snapshot: snapshot,
            relatedEntry:
                entryLookup[_activityLookupKeyForDeployment(
                  snapshot.instance.id,
                  deployment,
                )],
            recentWindow: _settings.recentWindow,
            now: now,
          ),
        );
      }
      for (final queued in snapshot.queuedDeployments) {
        items.add(
          DokployActivityItem.fromQueued(
            queuedDeployment: queued,
            snapshot: snapshot,
            relatedEntry:
                entryLookup[_activityLookupKeyForQueue(
                  snapshot.instance.id,
                  queued,
                )],
          ),
        );
      }
    }

    final uniqueById = <String, DokployActivityItem>{
      for (final item in items) item.id: item,
    };
    return DokploySorter.sortActivity(uniqueById.values);
  }

  List<MonitoredService> get filteredServices {
    final now = DateTime.now();
    final search = _serviceSearch.trim().toLowerCase();
    return allServices.where((service) {
      if (_selectedInstanceId != null &&
          service.instanceId != _selectedInstanceId) {
        return false;
      }

      final matchesSearch =
          search.isEmpty ||
          [
            service.name,
            service.appName ?? '',
            service.projectName,
            service.environmentName,
            service.instanceName,
            service.instanceHost,
            service.serviceType.displayName,
          ].any((value) => value.toLowerCase().contains(search));
      if (!matchesSearch) {
        return false;
      }

      return switch (_serviceFilter) {
        ServiceFilter.all => true,
        ServiceFilter.deploying =>
          service.group(now, _settings.recentWindow) ==
              MonitoredServiceGroup.deploying,
        ServiceFilter.recent =>
          service.group(now, _settings.recentWindow) ==
              MonitoredServiceGroup.recent,
        ServiceFilter.failed =>
          service.group(now, _settings.recentWindow) ==
              MonitoredServiceGroup.failed,
        ServiceFilter.steady =>
          service.group(now, _settings.recentWindow) ==
              MonitoredServiceGroup.steady,
      };
    }).toList();
  }

  List<DokployActivityItem> get filteredActivity {
    final search = _activitySearch.trim().toLowerCase();
    return allActivity.where((item) {
      if (_selectedInstanceId != null &&
          item.instanceId != _selectedInstanceId) {
        return false;
      }

      final matchesSearch =
          search.isEmpty ||
          [
            item.serviceName,
            item.appName ?? '',
            item.instanceName,
            item.projectName ?? '',
            item.environmentName ?? '',
            item.title,
            item.description ?? '',
            item.typeLabel,
          ].any((value) => value.toLowerCase().contains(search));
      if (!matchesSearch) {
        return false;
      }

      return switch (_activityFilter) {
        ActivityFilter.all => true,
        ActivityFilter.active =>
          item.state == DokployActivityState.queued ||
              item.state == DokployActivityState.deploying,
        ActivityFilter.failures => item.state == DokployActivityState.failed,
        ActivityFilter.completed => item.state == DokployActivityState.recent,
        ActivityFilter.older =>
          item.state == DokployActivityState.steady ||
              item.state == DokployActivityState.cancelled,
      };
    }).toList();
  }

  MonitoredService? serviceForActivity(DokployActivityItem item) {
    final relatedId = item.relatedEntryId;
    if (relatedId == null) {
      return null;
    }
    return allServices
        .where((service) => service.id == relatedId)
        .cast<MonitoredService?>()
        .firstOrNull;
  }

  Future<void> initialize() async {
    _initializationError = null;

    try {
      _settings = await _store.loadSettings();
      _instances = await _store.loadInstances();
      _sortInstances();
      _selectedInstanceId = await _store.loadSelectedInstanceId();
      if (_selectedInstanceId != null &&
          !_instances.any((instance) => instance.id == _selectedInstanceId)) {
        _selectedInstanceId = null;
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dokploy_radar_mobile',
          context: ErrorDescription(
            'while initializing the dashboard controller',
          ),
        ),
      );

      _instances = <DokployInstance>[];
      _snapshots = <InstanceSnapshot>[];
      _selectedInstanceId = null;
      _initializationError =
          'Could not load saved app data. ${error.toString()}';
    }

    _isInitialized = true;
    _restartRefreshLoop();
    notifyListeners();

    if (_initializationError == null &&
        _instances.any((instance) => instance.isEnabled)) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    if (_isRefreshing) {
      return;
    }

    _isRefreshing = true;
    notifyListeners();

    final now = DateTime.now();
    final existingByInstance = {
      for (final snapshot in _snapshots) snapshot.instance.id: snapshot,
    };
    final activeInstances = _instances
        .where((instance) => instance.isEnabled)
        .toList();

    if (activeInstances.isEmpty) {
      _snapshots = _instances
          .where((instance) => !instance.isEnabled)
          .map(
            (instance) => InstanceSnapshot(
              instance: instance,
              entries: const [],
              deployments: const [],
              queuedDeployments: const [],
              refreshedAt: now,
              errorMessage: null,
            ),
          )
          .toList();
      _lastRefresh = now;
      _isRefreshing = false;
      notifyListeners();
      return;
    }

    final refreshed = await Future.wait(
      activeInstances.map((instance) async {
        try {
          return await DokployApiClient(
            instance: instance,
          ).fetchSnapshot(now: now);
        } catch (error) {
          final fallback = existingByInstance[instance.id];
          return InstanceSnapshot(
            instance: instance,
            entries: fallback?.entries ?? const [],
            deployments: fallback?.deployments ?? const [],
            queuedDeployments: fallback?.queuedDeployments ?? const [],
            refreshedAt: now,
            errorMessage: error.toString(),
          );
        }
      }),
    );

    final disabledSnapshots = _instances
        .where((instance) => !instance.isEnabled)
        .map(
          (instance) => InstanceSnapshot(
            instance: instance,
            entries: const [],
            deployments: const [],
            queuedDeployments: const [],
            refreshedAt: now,
            errorMessage: null,
          ),
        )
        .toList();

    _snapshots = [...refreshed, ...disabledSnapshots]
      ..sort(
        (left, right) => left.instance.name.toLowerCase().compareTo(
          right.instance.name.toLowerCase(),
        ),
      );
    _lastRefresh = now;
    _isRefreshing = false;
    notifyListeners();
  }

  Future<DokployConnectionSummary> testConnection({
    required String name,
    required String baseUrlString,
    required String apiToken,
    String? existingId,
  }) async {
    final draft = DokployInstance(
      id: existingId ?? _uuid.v4(),
      name: name.trim(),
      baseUrlString: baseUrlString.trim(),
      apiToken: apiToken.trim(),
    );
    return DokployApiClient(instance: draft).testConnection();
  }

  Future<void> saveInstance({
    required String name,
    required String baseUrlString,
    required String apiToken,
    String? editingId,
    bool? isEnabled,
  }) async {
    final normalizedName = name.trim();
    final normalizedUrl = baseUrlString.trim();
    final normalizedToken = apiToken.trim();

    if (normalizedName.isEmpty ||
        normalizedUrl.isEmpty ||
        normalizedToken.isEmpty) {
      return;
    }

    final existingIndex = editingId == null
        ? -1
        : _instances.indexWhere((instance) => instance.id == editingId);
    if (existingIndex >= 0) {
      _instances[existingIndex] = _instances[existingIndex].copyWith(
        name: normalizedName,
        baseUrlString: normalizedUrl,
        apiToken: normalizedToken,
        isEnabled: isEnabled ?? _instances[existingIndex].isEnabled,
      );
    } else {
      _instances.add(
        DokployInstance(
          id: _uuid.v4(),
          name: normalizedName,
          baseUrlString: normalizedUrl,
          apiToken: normalizedToken,
          isEnabled: isEnabled ?? true,
        ),
      );
    }

    _clearInitializationError();
    _sortInstances();
    await _store.saveInstances(_instances);
    notifyListeners();
    await refresh();
  }

  Future<void> deleteInstance(String id) async {
    _instances.removeWhere((instance) => instance.id == id);
    _snapshots.removeWhere((snapshot) => snapshot.instance.id == id);
    if (_selectedInstanceId == id) {
      _selectedInstanceId = null;
      await _store.saveSelectedInstanceId(null);
    }
    _clearInitializationError();
    await _store.saveInstances(_instances);
    notifyListeners();
  }

  Future<void> toggleInstanceEnabled(String id, bool isEnabled) async {
    final index = _instances.indexWhere((instance) => instance.id == id);
    if (index < 0) {
      return;
    }
    _instances[index] = _instances[index].copyWith(isEnabled: isEnabled);
    _clearInitializationError();
    await _store.saveInstances(_instances);
    notifyListeners();
    await refresh();
  }

  Future<void> selectInstance(String? id) async {
    _selectedInstanceId = id;
    _clearInitializationError();
    await _store.saveSelectedInstanceId(id);
    notifyListeners();
  }

  void updateServiceSearch(String value) {
    _serviceSearch = value;
    notifyListeners();
  }

  void updateActivitySearch(String value) {
    _activitySearch = value;
    notifyListeners();
  }

  void updateServiceFilter(ServiceFilter value) {
    _serviceFilter = value;
    notifyListeners();
  }

  void updateActivityFilter(ActivityFilter value) {
    _activityFilter = value;
    notifyListeners();
  }

  Future<void> updateSettings({
    int? refreshIntervalSeconds,
    int? recentWindowMinutes,
  }) async {
    _settings = _settings.copyWith(
      refreshIntervalSeconds: refreshIntervalSeconds,
      recentWindowMinutes: recentWindowMinutes,
    );
    _clearInitializationError();
    await _store.saveSettings(_settings);
    _restartRefreshLoop();
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _sortInstances() {
    _instances = [..._instances]
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
  }

  void _clearInitializationError() {
    _initializationError = null;
  }

  void _restartRefreshLoop() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_settings.refreshInterval, (_) {
      unawaited(refresh());
    });
  }

  String _activityLookupKey(MonitoredService service) {
    return '${service.instanceId}:${service.serviceType.name}:${service.applicationId}';
  }

  String _activityLookupKeyForDeployment(
    String instanceId,
    DokployCentralizedDeployment deployment,
  ) {
    if (deployment.application != null) {
      return '$instanceId:${DokployServiceType.application.name}:${deployment.application!.applicationId}';
    }
    if (deployment.compose != null) {
      return '$instanceId:${DokployServiceType.compose.name}:${deployment.compose!.composeId}';
    }
    return '$instanceId:unknown:${deployment.deploymentId}';
  }

  String _activityLookupKeyForQueue(
    String instanceId,
    DokployQueuedDeployment queuedDeployment,
  ) {
    final typeName = queuedDeployment.serviceType?.name ?? 'unknown';
    final serviceId = queuedDeployment.serviceId ?? queuedDeployment.id;
    return '$instanceId:$typeName:$serviceId';
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
