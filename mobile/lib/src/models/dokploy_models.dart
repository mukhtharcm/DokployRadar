import 'app_models.dart';

enum DokployServiceType {
  application,
  compose,
  mariadb,
  mongo,
  mysql,
  postgres,
  redis,
  libsql;

  static DokployServiceType? tryParse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'application' => DokployServiceType.application,
      'compose' => DokployServiceType.compose,
      'mariadb' => DokployServiceType.mariadb,
      'mongo' => DokployServiceType.mongo,
      'mysql' => DokployServiceType.mysql,
      'postgres' => DokployServiceType.postgres,
      'redis' => DokployServiceType.redis,
      'libsql' => DokployServiceType.libsql,
      _ => null,
    };
  }

  String get displayName {
    return switch (this) {
      DokployServiceType.application => 'Application',
      DokployServiceType.compose => 'Compose',
      DokployServiceType.mariadb => 'MariaDB',
      DokployServiceType.mongo => 'MongoDB',
      DokployServiceType.mysql => 'MySQL',
      DokployServiceType.postgres => 'PostgreSQL',
      DokployServiceType.redis => 'Redis',
      DokployServiceType.libsql => 'LibSQL',
    };
  }
}

enum DokployApplicationStatus {
  idle,
  running,
  done,
  error;

  static DokployApplicationStatus? tryParse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'idle' => DokployApplicationStatus.idle,
      'running' => DokployApplicationStatus.running,
      'done' => DokployApplicationStatus.done,
      'error' => DokployApplicationStatus.error,
      _ => null,
    };
  }
}

enum DokployDeploymentStatus {
  running,
  done,
  error,
  cancelled;

  static DokployDeploymentStatus? tryParse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'running' => DokployDeploymentStatus.running,
      'done' => DokployDeploymentStatus.done,
      'error' => DokployDeploymentStatus.error,
      'cancelled' => DokployDeploymentStatus.cancelled,
      _ => null,
    };
  }
}

enum MonitoredServiceGroup {
  deploying,
  recent,
  failed,
  steady;
}

enum DokployActivityState {
  queued,
  deploying,
  failed,
  recent,
  cancelled,
  steady;

  String get displayName {
    return switch (this) {
      DokployActivityState.queued => 'Queued',
      DokployActivityState.deploying => 'Deploying',
      DokployActivityState.failed => 'Failed',
      DokployActivityState.recent => 'Completed',
      DokployActivityState.cancelled => 'Cancelled',
      DokployActivityState.steady => 'Older',
    };
  }
}

enum ServiceFilter {
  all,
  deploying,
  recent,
  failed,
  steady;

  String get label {
    return switch (this) {
      ServiceFilter.all => 'All',
      ServiceFilter.deploying => 'Deploying',
      ServiceFilter.recent => 'Recent',
      ServiceFilter.failed => 'Failed',
      ServiceFilter.steady => 'Steady',
    };
  }
}

enum ActivityFilter {
  all,
  active,
  failures,
  completed,
  older;

  String get label {
    return switch (this) {
      ActivityFilter.all => 'All',
      ActivityFilter.active => 'Active',
      ActivityFilter.failures => 'Failures',
      ActivityFilter.completed => 'Completed',
      ActivityFilter.older => 'Older',
    };
  }
}

class DokployConnectionSummary {
  const DokployConnectionSummary({
    required this.projectCount,
    required this.serviceCount,
    required this.deployingCount,
    required this.failedCount,
  });

  final int projectCount;
  final int serviceCount;
  final int deployingCount;
  final int failedCount;
}

class DokployCentralizedProject {
  const DokployCentralizedProject({
    required this.projectId,
    required this.name,
  });

  final String projectId;
  final String name;

  factory DokployCentralizedProject.fromJson(Map<String, dynamic> json) {
    return DokployCentralizedProject(
      projectId: json['projectId'] as String,
      name: json['name'] as String,
    );
  }
}

class DokployCentralizedEnvironment {
  const DokployCentralizedEnvironment({
    required this.environmentId,
    required this.name,
    required this.project,
  });

  final String environmentId;
  final String name;
  final DokployCentralizedProject project;

  factory DokployCentralizedEnvironment.fromJson(Map<String, dynamic> json) {
    return DokployCentralizedEnvironment(
      environmentId: json['environmentId'] as String,
      name: json['name'] as String,
      project: DokployCentralizedProject.fromJson(
        (json['project'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
      ),
    );
  }
}

class DokployCentralizedApplication {
  const DokployCentralizedApplication({
    required this.applicationId,
    required this.name,
    required this.appName,
    required this.environment,
  });

  final String applicationId;
  final String name;
  final String? appName;
  final DokployCentralizedEnvironment environment;

  factory DokployCentralizedApplication.fromJson(Map<String, dynamic> json) {
    return DokployCentralizedApplication(
      applicationId: json['applicationId'] as String,
      name: json['name'] as String,
      appName: json['appName'] as String?,
      environment: DokployCentralizedEnvironment.fromJson(
        (json['environment'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
      ),
    );
  }
}

class DokployCentralizedCompose {
  const DokployCentralizedCompose({
    required this.composeId,
    required this.name,
    required this.appName,
    required this.environment,
  });

  final String composeId;
  final String name;
  final String? appName;
  final DokployCentralizedEnvironment environment;

  factory DokployCentralizedCompose.fromJson(Map<String, dynamic> json) {
    return DokployCentralizedCompose(
      composeId: json['composeId'] as String,
      name: json['name'] as String,
      appName: json['appName'] as String?,
      environment: DokployCentralizedEnvironment.fromJson(
        (json['environment'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
      ),
    );
  }
}

class DokployCentralizedDeployment {
  const DokployCentralizedDeployment({
    required this.deploymentId,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAtRaw,
    required this.startedAtRaw,
    required this.finishedAtRaw,
    required this.errorMessage,
    required this.application,
    required this.compose,
  });

  final String deploymentId;
  final String title;
  final String? description;
  final DokployDeploymentStatus? status;
  final String createdAtRaw;
  final String? startedAtRaw;
  final String? finishedAtRaw;
  final String? errorMessage;
  final DokployCentralizedApplication? application;
  final DokployCentralizedCompose? compose;

  DateTime? get createdAt => parseDokployDate(createdAtRaw);

  DateTime? get startedAt => parseDokployDate(startedAtRaw);

  DateTime? get finishedAt => parseDokployDate(finishedAtRaw);

  DateTime get activityDate => finishedAt ?? startedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory DokployCentralizedDeployment.fromJson(Map<String, dynamic> json) {
    final applicationValue = json['application'];
    final composeValue = json['compose'];

    return DokployCentralizedDeployment(
      deploymentId: json['deploymentId'] as String,
      title: (json['title'] as String?) ?? 'Deployment',
      description: json['description'] as String?,
      status: DokployDeploymentStatus.tryParse(json['status'] as String?),
      createdAtRaw: json['createdAt'] as String,
      startedAtRaw: json['startedAt'] as String?,
      finishedAtRaw: json['finishedAt'] as String?,
      errorMessage: json['errorMessage'] as String?,
      application: applicationValue is Map<dynamic, dynamic>
          ? DokployCentralizedApplication.fromJson(applicationValue.cast<String, dynamic>())
          : null,
      compose: composeValue is Map<dynamic, dynamic>
          ? DokployCentralizedCompose.fromJson(composeValue.cast<String, dynamic>())
          : null,
    );
  }
}

class DokployDeploymentRecord {
  const DokployDeploymentRecord({
    required this.deploymentId,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAtRaw,
    required this.startedAtRaw,
    required this.finishedAtRaw,
    required this.errorMessage,
    required this.logPath,
  });

  final String deploymentId;
  final String title;
  final String? description;
  final DokployDeploymentStatus status;
  final String createdAtRaw;
  final String? startedAtRaw;
  final String? finishedAtRaw;
  final String? errorMessage;
  final String? logPath;

  DateTime? get createdAt => parseDokployDate(createdAtRaw);

  DateTime? get startedAt => parseDokployDate(startedAtRaw);

  DateTime? get finishedAt => parseDokployDate(finishedAtRaw);

  DateTime? get activityDate => finishedAt ?? startedAt ?? createdAt;

  factory DokployDeploymentRecord.fromJson(Map<String, dynamic> json) {
    return DokployDeploymentRecord(
      deploymentId: json['deploymentId'] as String,
      title: (json['title'] as String?) ?? 'Deployment',
      description: json['description'] as String?,
      status: DokployDeploymentStatus.tryParse(json['status'] as String?) ?? DokployDeploymentStatus.done,
      createdAtRaw: json['createdAt'] as String,
      startedAtRaw: json['startedAt'] as String?,
      finishedAtRaw: json['finishedAt'] as String?,
      errorMessage: json['errorMessage'] as String?,
      logPath: json['logPath'] as String?,
    );
  }
}

class DokployQueuedDeployment {
  const DokployQueuedDeployment({
    required this.id,
    required this.title,
    required this.description,
    required this.serviceId,
    required this.serviceName,
    required this.appName,
    required this.serviceType,
    required this.createdAtRaw,
  });

  final String id;
  final String title;
  final String? description;
  final String? serviceId;
  final String? serviceName;
  final String? appName;
  final DokployServiceType? serviceType;
  final String? createdAtRaw;

  DateTime? get createdAt => parseDokployDate(createdAtRaw);
}

class MonitoredService {
  const MonitoredService({
    required this.id,
    required this.instanceId,
    required this.instanceName,
    required this.instanceHost,
    required this.projectName,
    required this.environmentName,
    required this.applicationId,
    required this.name,
    required this.appName,
    required this.applicationStatus,
    required this.serviceType,
    required this.latestDeployment,
  });

  final String id;
  final String instanceId;
  final String instanceName;
  final String instanceHost;
  final String projectName;
  final String environmentName;
  final String applicationId;
  final String name;
  final String? appName;
  final DokployApplicationStatus applicationStatus;
  final DokployServiceType serviceType;
  final DokployCentralizedDeployment? latestDeployment;

  bool get supportsDeploymentHistory {
    return serviceType == DokployServiceType.application || serviceType == DokployServiceType.compose;
  }

  DateTime? get lastActivityDate {
    return latestDeployment?.finishedAt ?? latestDeployment?.startedAt ?? latestDeployment?.createdAt;
  }

  bool get isDeploying {
    return applicationStatus == DokployApplicationStatus.running || latestDeployment?.status == DokployDeploymentStatus.running;
  }

  bool get isFailing {
    return applicationStatus == DokployApplicationStatus.error || latestDeployment?.status == DokployDeploymentStatus.error;
  }

  bool isRecent(DateTime now, Duration recentWindow) {
    final lastDate = lastActivityDate;
    if (lastDate == null || latestDeployment?.status != DokployDeploymentStatus.done) {
      return false;
    }
    return lastDate.isAfter(now.subtract(recentWindow));
  }

  MonitoredServiceGroup group(DateTime now, Duration recentWindow) {
    if (isDeploying) {
      return MonitoredServiceGroup.deploying;
    }
    if (isRecent(now, recentWindow)) {
      return MonitoredServiceGroup.recent;
    }
    if (isFailing) {
      return MonitoredServiceGroup.failed;
    }
    return MonitoredServiceGroup.steady;
  }

  String statusLabel(DateTime now, Duration recentWindow) {
    return switch (group(now, recentWindow)) {
      MonitoredServiceGroup.deploying => 'Deploying',
      MonitoredServiceGroup.recent => 'Recently deployed',
      MonitoredServiceGroup.failed => 'Failed',
      MonitoredServiceGroup.steady => switch (applicationStatus) {
          DokployApplicationStatus.done => 'Ready',
          DokployApplicationStatus.idle => 'Idle',
          DokployApplicationStatus.running => 'Running',
          DokployApplicationStatus.error => 'Error',
        },
    };
  }
}

class DokployActivityItem {
  const DokployActivityItem({
    required this.id,
    required this.instanceId,
    required this.instanceName,
    required this.instanceHost,
    required this.serviceId,
    required this.serviceName,
    required this.appName,
    required this.serviceType,
    required this.projectName,
    required this.environmentName,
    required this.relatedEntryId,
    required this.title,
    required this.description,
    required this.errorMessage,
    required this.state,
    required this.createdAt,
    required this.startedAt,
    required this.finishedAt,
  });

  final String id;
  final String instanceId;
  final String instanceName;
  final String instanceHost;
  final String? serviceId;
  final String serviceName;
  final String? appName;
  final DokployServiceType? serviceType;
  final String? projectName;
  final String? environmentName;
  final String? relatedEntryId;
  final String title;
  final String? description;
  final String? errorMessage;
  final DokployActivityState state;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  DateTime get activityDate {
    return finishedAt ?? startedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool get isActive => state == DokployActivityState.queued || state == DokployActivityState.deploying;

  String get typeLabel => serviceType?.displayName ?? 'Service';

  String get subtitle {
    final parts = <String>[
      if (serviceType != null) serviceType!.displayName,
      instanceName,
      if (projectName != null && projectName!.isNotEmpty) projectName!,
      if (environmentName != null && environmentName!.isNotEmpty) environmentName!,
    ];
    return parts.join(' · ');
  }

  String? get durationLabel {
    final started = startedAt;
    if (started == null) {
      return null;
    }

    final end = finishedAt ?? (state == DokployActivityState.deploying ? DateTime.now() : null);
    if (end == null) {
      return null;
    }

    final duration = end.difference(started);
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    }
    if (duration.inMinutes < 60) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  factory DokployActivityItem.fromDeployment({
    required DokployCentralizedDeployment deployment,
    required InstanceSnapshot snapshot,
    required MonitoredService? relatedEntry,
    required Duration recentWindow,
    required DateTime now,
  }) {
    final serviceType = switch ((deployment.application, deployment.compose)) {
      (final DokployCentralizedApplication _, _) => DokployServiceType.application,
      (_, final DokployCentralizedCompose _) => DokployServiceType.compose,
      _ => relatedEntry?.serviceType,
    };

    final serviceId = deployment.application?.applicationId ?? deployment.compose?.composeId ?? relatedEntry?.applicationId;
    final serviceName = deployment.application?.name ?? deployment.compose?.name ?? relatedEntry?.name ?? 'Unknown Service';
    final appName = deployment.application?.appName ?? deployment.compose?.appName ?? relatedEntry?.appName;
    final projectName = relatedEntry?.projectName
        ?? deployment.application?.environment.project.name
        ?? deployment.compose?.environment.project.name;
    final environmentName = relatedEntry?.environmentName
        ?? deployment.application?.environment.name
        ?? deployment.compose?.environment.name;

    final referenceDate = deployment.finishedAt ?? deployment.startedAt ?? deployment.createdAt;
    final state = switch (deployment.status) {
      DokployDeploymentStatus.running => DokployActivityState.deploying,
      DokployDeploymentStatus.error => DokployActivityState.failed,
      DokployDeploymentStatus.cancelled => DokployActivityState.cancelled,
      DokployDeploymentStatus.done =>
        referenceDate != null && referenceDate.isAfter(now.subtract(recentWindow))
            ? DokployActivityState.recent
            : DokployActivityState.steady,
      null => DokployActivityState.steady,
    };

    return DokployActivityItem(
      id: 'deployment:${snapshot.instance.id}:${deployment.deploymentId}',
      instanceId: snapshot.instance.id,
      instanceName: snapshot.instance.name,
      instanceHost: snapshot.instance.hostLabel,
      serviceId: serviceId,
      serviceName: serviceName,
      appName: appName,
      serviceType: serviceType,
      projectName: projectName,
      environmentName: environmentName,
      relatedEntryId: relatedEntry?.id,
      title: deployment.title,
      description: deployment.description,
      errorMessage: deployment.errorMessage,
      state: state,
      createdAt: deployment.createdAt,
      startedAt: deployment.startedAt,
      finishedAt: deployment.finishedAt,
    );
  }

  factory DokployActivityItem.fromQueued({
    required DokployQueuedDeployment queuedDeployment,
    required InstanceSnapshot snapshot,
    required MonitoredService? relatedEntry,
  }) {
    return DokployActivityItem(
      id: 'queue:${snapshot.instance.id}:${queuedDeployment.id}',
      instanceId: snapshot.instance.id,
      instanceName: snapshot.instance.name,
      instanceHost: snapshot.instance.hostLabel,
      serviceId: queuedDeployment.serviceId ?? relatedEntry?.applicationId,
      serviceName: queuedDeployment.serviceName ?? relatedEntry?.name ?? 'Queued Service',
      appName: queuedDeployment.appName ?? relatedEntry?.appName,
      serviceType: queuedDeployment.serviceType ?? relatedEntry?.serviceType,
      projectName: relatedEntry?.projectName,
      environmentName: relatedEntry?.environmentName,
      relatedEntryId: relatedEntry?.id,
      title: queuedDeployment.title,
      description: queuedDeployment.description,
      errorMessage: null,
      state: DokployActivityState.queued,
      createdAt: queuedDeployment.createdAt,
      startedAt: null,
      finishedAt: null,
    );
  }
}

class InstanceSnapshot {
  const InstanceSnapshot({
    required this.instance,
    required this.entries,
    required this.deployments,
    required this.queuedDeployments,
    required this.refreshedAt,
    required this.errorMessage,
  });

  final DokployInstance instance;
  final List<MonitoredService> entries;
  final List<DokployCentralizedDeployment> deployments;
  final List<DokployQueuedDeployment> queuedDeployments;
  final DateTime refreshedAt;
  final String? errorMessage;

  int get deployingCount => entries.where((entry) => entry.isDeploying).length;

  int recentCount(Duration recentWindow) {
    return entries.where((entry) => entry.isRecent(refreshedAt, recentWindow)).length;
  }

  int get failedCount => entries.where((entry) => entry.isFailing).length;
}

class ServiceInspectorData {
  const ServiceInspectorData({
    this.sourceType,
    this.configurationType,
    this.repository,
    this.branch,
    this.autoDeployEnabled,
    this.previewDeploymentsEnabled,
    this.previewDeploymentCount,
    this.deploymentCount,
    this.environmentVariableCount = 0,
    this.mountCount = 0,
    this.watchPathCount = 0,
    this.domainLabels = const [],
    this.portLabels = const [],
    this.watchPaths = const [],
    this.composeServiceNames = const [],
    this.renderedCompose,
    this.unsupportedMessage,
  });

  final String? sourceType;
  final String? configurationType;
  final String? repository;
  final String? branch;
  final bool? autoDeployEnabled;
  final bool? previewDeploymentsEnabled;
  final int? previewDeploymentCount;
  final int? deploymentCount;
  final int environmentVariableCount;
  final int mountCount;
  final int watchPathCount;
  final List<String> domainLabels;
  final List<String> portLabels;
  final List<String> watchPaths;
  final List<String> composeServiceNames;
  final String? renderedCompose;
  final String? unsupportedMessage;

  bool get hasRichContent {
    return unsupportedMessage == null &&
        (sourceType != null ||
            configurationType != null ||
            repository != null ||
            branch != null ||
            autoDeployEnabled != null ||
            previewDeploymentsEnabled != null ||
            previewDeploymentCount != null ||
            deploymentCount != null ||
            environmentVariableCount > 0 ||
            mountCount > 0 ||
            watchPathCount > 0 ||
            domainLabels.isNotEmpty ||
            portLabels.isNotEmpty ||
            watchPaths.isNotEmpty ||
            composeServiceNames.isNotEmpty ||
            (renderedCompose?.isNotEmpty ?? false));
  }

  factory ServiceInspectorData.unsupported(DokployServiceType serviceType) {
    return ServiceInspectorData(
      unsupportedMessage:
          'Dokploy exposes richer inspector data for applications and compose services. ${serviceType.displayName} services are shown here primarily for status monitoring.',
    );
  }
}

class DokploySorter {
  DokploySorter._();

  static List<MonitoredService> sortServices(
    Iterable<MonitoredService> entries, {
    required DateTime now,
    required Duration recentWindow,
  }) {
    final result = entries.toList();
    result.sort((left, right) {
      final leftGroup = left.group(now, recentWindow);
      final rightGroup = right.group(now, recentWindow);
      if (leftGroup != rightGroup) {
        return leftGroup.index.compareTo(rightGroup.index);
      }

      final leftDate = left.lastActivityDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate = right.lastActivityDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (leftDate != rightDate) {
        return rightDate.compareTo(leftDate);
      }

      final typeCompare = left.serviceType.displayName.toLowerCase().compareTo(right.serviceType.displayName.toLowerCase());
      if (typeCompare != 0) {
        return typeCompare;
      }

      final instanceCompare = left.instanceName.toLowerCase().compareTo(right.instanceName.toLowerCase());
      if (instanceCompare != 0) {
        return instanceCompare;
      }

      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return result;
  }

  static List<DokployActivityItem> sortActivity(Iterable<DokployActivityItem> items) {
    final result = items.toList();
    result.sort((left, right) {
      if (left.state != right.state) {
        return left.state.index.compareTo(right.state.index);
      }

      final dateCompare = right.activityDate.compareTo(left.activityDate);
      if (dateCompare != 0) {
        return dateCompare;
      }

      final instanceCompare = left.instanceName.toLowerCase().compareTo(right.instanceName.toLowerCase());
      if (instanceCompare != 0) {
        return instanceCompare;
      }

      return left.serviceName.toLowerCase().compareTo(right.serviceName.toLowerCase());
    });
    return result;
  }
}

DateTime? parseDokployDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}
