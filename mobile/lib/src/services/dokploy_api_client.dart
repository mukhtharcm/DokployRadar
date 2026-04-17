import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_models.dart';
import '../models/dokploy_models.dart';

typedef JsonMap = Map<String, dynamic>;

class DokployApiClient {
  DokployApiClient({
    required this.instance,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final DokployInstance instance;
  final http.Client _client;

  Future<InstanceSnapshot> fetchSnapshot({DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    final projects = await _requestInventory();
    final deployments = (await _requestJsonArray('/deployment.allCentralized'))
        .map((item) => DokployCentralizedDeployment.fromJson(_ensureMap(item)))
        .toList();
    final queuedDeployments = await _fetchQueuedDeployments();

    final entries = _buildEntries(
      projects: projects,
      deployments: deployments,
      now: currentTime,
    );

    return InstanceSnapshot(
      instance: instance,
      entries: entries,
      deployments: deployments,
      queuedDeployments: queuedDeployments,
      refreshedAt: currentTime,
      errorMessage: null,
    );
  }

  Future<DokployConnectionSummary> testConnection({DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    final projects = await _requestInventory();
    final deployments = (await _requestJsonArray('/deployment.allCentralized'))
        .map((item) => DokployCentralizedDeployment.fromJson(_ensureMap(item)))
        .toList();

    final entries = _buildEntries(
      projects: projects,
      deployments: deployments,
      now: currentTime,
    );

    return DokployConnectionSummary(
      projectCount: projects.length,
      serviceCount: entries.length,
      deployingCount: entries.where((entry) => entry.isDeploying).length,
      failedCount: entries.where((entry) => entry.isFailing).length,
    );
  }

  Future<List<DokployDeploymentRecord>> fetchDeploymentHistory(MonitoredService service) async {
    final path = switch (service.serviceType) {
      DokployServiceType.application => '/deployment.all',
      DokployServiceType.compose => '/deployment.allByCompose',
      DokployServiceType.mariadb ||
      DokployServiceType.mongo ||
      DokployServiceType.mysql ||
      DokployServiceType.postgres ||
      DokployServiceType.redis ||
      DokployServiceType.libsql => null,
    };

    if (path == null) {
      return const [];
    }

    final query = switch (service.serviceType) {
      DokployServiceType.application => {'applicationId': service.applicationId},
      DokployServiceType.compose => {'composeId': service.applicationId},
      DokployServiceType.mariadb ||
      DokployServiceType.mongo ||
      DokployServiceType.mysql ||
      DokployServiceType.postgres ||
      DokployServiceType.redis ||
      DokployServiceType.libsql => const <String, String>{},
    };

    final history = (await _requestJsonArray(path, queryParameters: query))
        .map((item) => DokployDeploymentRecord.fromJson(_ensureMap(item)))
        .toList();

    history.sort((left, right) {
      final leftDate = left.activityDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate = right.activityDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightDate.compareTo(leftDate);
    });

    return history;
  }

  Future<ServiceInspectorData> fetchInspectorDetail(MonitoredService service) async {
    switch (service.serviceType) {
      case DokployServiceType.application:
        final payload = await _requestJsonObject(
          '/application.one',
          queryParameters: {'applicationId': service.applicationId},
        );
        return ServiceInspectorData(
          sourceType: _normalizedLabel(payload['sourceType']),
          configurationType: _normalizedLabel(payload['buildType']),
          repository: _firstNonEmptyString([
            payload['repository'],
          ]),
          branch: _firstNonEmptyString([
            payload['branch'],
            payload['customGitBranch'],
            payload['bitbucketBranch'],
            payload['giteaBranch'],
            payload['gitlabBranch'],
          ]),
          autoDeployEnabled: _asBool(payload['autoDeploy']),
          previewDeploymentsEnabled: _asBool(payload['isPreviewDeploymentsActive']),
          previewDeploymentCount: _optionalCount(payload['previewDeployments']),
          deploymentCount: _optionalCount(payload['deployments']),
          environmentVariableCount: _asList(payload['env']).length,
          mountCount: _asList(payload['mounts']).length,
          watchPathCount: _asList(payload['watchPaths']).length,
          domainLabels: _domainLabels(payload['domains']),
          portLabels: _portLabels(payload['ports']),
          watchPaths: _stringArray(payload['watchPaths']),
        );
      case DokployServiceType.compose:
        final payload = await _requestJsonObject(
          '/compose.one',
          queryParameters: {'composeId': service.applicationId},
        );
        final composeServiceNames = (await _requestJsonArray(
          '/compose.loadServices',
          queryParameters: {'composeId': service.applicationId},
        ))
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList();
        final renderedCompose = await _requestString(
          '/compose.getConvertedCompose',
          queryParameters: {'composeId': service.applicationId},
        );

        return ServiceInspectorData(
          sourceType: _normalizedLabel(payload['sourceType']),
          configurationType: _normalizedLabel(payload['composeType']),
          repository: _firstNonEmptyString([
            payload['repository'],
          ]),
          branch: _firstNonEmptyString([
            payload['branch'],
            payload['customGitBranch'],
            payload['bitbucketBranch'],
            payload['giteaBranch'],
            payload['gitlabBranch'],
          ]),
          autoDeployEnabled: _asBool(payload['autoDeploy']),
          deploymentCount: _optionalCount(payload['deployments']),
          environmentVariableCount: _asList(payload['env']).length,
          mountCount: _asList(payload['mounts']).length,
          watchPathCount: _asList(payload['watchPaths']).length,
          domainLabels: _domainLabels(payload['domains']),
          portLabels: _portLabels(payload['ports']),
          watchPaths: _stringArray(payload['watchPaths']),
          composeServiceNames: composeServiceNames,
          renderedCompose: renderedCompose.trim().isEmpty ? null : renderedCompose.trim(),
        );
      case DokployServiceType.mariadb:
      case DokployServiceType.mongo:
      case DokployServiceType.mysql:
      case DokployServiceType.postgres:
      case DokployServiceType.redis:
      case DokployServiceType.libsql:
        return ServiceInspectorData.unsupported(service.serviceType);
    }
  }

  Future<List<_InventoryProject>> _requestInventory() async {
    try {
      final payload = await _requestJsonArray('/project.allForPermissions');
      return payload.map((item) => _InventoryProject.fromJson(_ensureMap(item))).toList();
    } on DokployApiException catch (error) {
      if (error.statusCode == 404) {
        final payload = await _requestJsonArray('/project.all');
        return payload.map((item) => _InventoryProject.fromJson(_ensureMap(item))).toList();
      }
      rethrow;
    } on FormatException {
      final payload = await _requestJsonArray('/project.all');
      return payload.map((item) => _InventoryProject.fromJson(_ensureMap(item))).toList();
    }
  }

  Future<List<DokployQueuedDeployment>> _fetchQueuedDeployments() async {
    final payload = await _requestJsonArray('/deployment.queueList');
    final deployments = <DokployQueuedDeployment>[];
    for (var index = 0; index < payload.length; index += 1) {
      final parsed = _parseQueuedDeployment(payload[index], index);
      if (parsed != null) {
        deployments.add(parsed);
      }
    }
    return deployments;
  }

  DokployQueuedDeployment? _parseQueuedDeployment(dynamic rawValue, int fallbackIndex) {
    if (rawValue is! Map) {
      return null;
    }

    final payload = rawValue.cast<String, dynamic>();
    final application = payload['application'] is Map
        ? (payload['application'] as Map).cast<String, dynamic>()
        : null;
    final compose = payload['compose'] is Map
        ? (payload['compose'] as Map).cast<String, dynamic>()
        : null;
    final explicitType = _firstNonEmptyString([payload['type'], payload['serviceType']]);

    final serviceType = compose != null || explicitType == 'compose'
        ? DokployServiceType.compose
        : application != null || explicitType == 'application'
            ? DokployServiceType.application
            : null;

    return DokployQueuedDeployment(
      id: _firstNonEmptyString([
            payload['queueId'],
            payload['jobId'],
            payload['deploymentId'],
            payload['id'],
          ]) ??
          '$fallbackIndex',
      title: _firstNonEmptyString([
            payload['title'],
            payload['jobName'],
            payload['name'],
          ]) ??
          'Queued deployment',
      description: _firstNonEmptyString([payload['description']]),
      serviceId: _firstNonEmptyString([
        compose?['composeId'],
        payload['composeId'],
        application?['applicationId'],
        payload['applicationId'],
        payload['serviceId'],
        payload['id'],
      ]),
      serviceName: _firstNonEmptyString([
        compose?['name'],
        application?['name'],
        payload['serviceName'],
        payload['applicationName'],
        payload['composeName'],
        payload['name'],
      ]),
      appName: _firstNonEmptyString([
        compose?['appName'],
        application?['appName'],
        payload['appName'],
      ]),
      serviceType: serviceType,
      createdAtRaw: _firstNonEmptyString([
        payload['createdAt'],
        payload['queuedAt'],
      ]),
    );
  }

  List<MonitoredService> _buildEntries({
    required List<_InventoryProject> projects,
    required List<DokployCentralizedDeployment> deployments,
    required DateTime now,
  }) {
    final latestDeploymentByAppId = <String, DokployCentralizedDeployment>{};
    final latestDeploymentByComposeId = <String, DokployCentralizedDeployment>{};

    for (final deployment in deployments) {
      final applicationId = deployment.application?.applicationId;
      if (applicationId != null && !latestDeploymentByAppId.containsKey(applicationId)) {
        latestDeploymentByAppId[applicationId] = deployment;
      }

      final composeId = deployment.compose?.composeId;
      if (composeId != null && !latestDeploymentByComposeId.containsKey(composeId)) {
        latestDeploymentByComposeId[composeId] = deployment;
      }
    }

    final flattened = <MonitoredService>[];
    for (final project in projects) {
      for (final environment in project.environments) {
        for (final service in environment.services) {
          flattened.add(
            MonitoredService(
              id: '${instance.id}:${service.type.name}:${service.id}',
              instanceId: instance.id,
              instanceName: instance.name,
              instanceHost: instance.hostLabel,
              projectName: project.name,
              environmentName: environment.name,
              applicationId: service.id,
              name: service.name,
              appName: service.appName,
              applicationStatus: service.status,
              serviceType: service.type,
              latestDeployment: switch (service.type) {
                DokployServiceType.application => latestDeploymentByAppId[service.id],
                DokployServiceType.compose => latestDeploymentByComposeId[service.id],
                DokployServiceType.mariadb ||
                DokployServiceType.mongo ||
                DokployServiceType.mysql ||
                DokployServiceType.postgres ||
                DokployServiceType.redis ||
                DokployServiceType.libsql => null,
              },
            ),
          );
        }
      }
    }

    return DokploySorter.sortServices(
      flattened,
      now: now,
      recentWindow: const Duration(hours: 1),
    );
  }

  Future<List<dynamic>> _requestJsonArray(
    String path, {
    Map<String, String> queryParameters = const {},
  }) async {
    final decoded = await _requestJson(path, queryParameters: queryParameters);
    if (decoded is! List) {
      throw DokployApiException.invalidResponse();
    }
    return decoded;
  }

  Future<JsonMap> _requestJsonObject(
    String path, {
    Map<String, String> queryParameters = const {},
  }) async {
    final decoded = await _requestJson(path, queryParameters: queryParameters);
    if (decoded is! Map) {
      throw DokployApiException.invalidResponse();
    }
    return decoded.cast<String, dynamic>();
  }

  Future<String> _requestString(
    String path, {
    Map<String, String> queryParameters = const {},
  }) async {
    final uri = _endpointUri(path, queryParameters: queryParameters);
    final response = await _get(uri);
    final body = response.body;

    try {
      final decoded = jsonDecode(body);
      if (decoded is String) {
        return decoded;
      }
    } on FormatException {
      return body;
    }

    return body;
  }

  Future<dynamic> _requestJson(
    String path, {
    Map<String, String> queryParameters = const {},
  }) async {
    final uri = _endpointUri(path, queryParameters: queryParameters);
    final response = await _get(uri);

    try {
      return jsonDecode(response.body);
    } on FormatException catch (error) {
      throw DokployApiException(
        'Dokploy returned a response this app does not understand. ${error.message}',
      );
    }
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'accept': 'application/json',
              'x-api-key': instance.apiToken,
              'authorization': 'Bearer ${instance.apiToken}',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DokployApiException.requestFailed(
          statusCode: response.statusCode,
          message: _errorMessage(response.body, response.statusCode),
        );
      }

      return response;
    } on TimeoutException {
      throw DokployApiException('The Dokploy request timed out. Check connectivity and try again.');
    } on http.ClientException catch (error) {
      throw DokployApiException(error.message);
    }
  }

  Uri _endpointUri(
    String path, {
    Map<String, String> queryParameters = const {},
  }) {
    final base = instance.normalizedBaseUri;
    if (base == null) {
      throw DokployApiException.invalidBaseUrl();
    }

    final normalizedSegments = [
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      'api',
      ...path.split('/').where((segment) => segment.isNotEmpty),
    ];

    return base.replace(
      pathSegments: normalizedSegments,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }
}

class DokployApiException implements Exception {
  DokployApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  factory DokployApiException.invalidBaseUrl() {
    return DokployApiException(
      'The Dokploy base URL is invalid. Use the full Dokploy hostname, for example https://dokploy.example.com.',
    );
  }

  factory DokployApiException.invalidResponse() {
    return DokployApiException(
      'The Dokploy instance returned an invalid HTTP response.',
    );
  }

  factory DokployApiException.requestFailed({
    required int statusCode,
    required String message,
  }) {
    return DokployApiException(message, statusCode: statusCode);
  }

  @override
  String toString() => message;
}

class _InventoryProject {
  const _InventoryProject({
    required this.projectId,
    required this.name,
    required this.environments,
  });

  final String projectId;
  final String name;
  final List<_InventoryEnvironment> environments;

  factory _InventoryProject.fromJson(JsonMap json) {
    return _InventoryProject(
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      environments: _asList(json['environments'])
          .map((item) => _InventoryEnvironment.fromJson(_ensureMap(item)))
          .toList(),
    );
  }
}

class _InventoryEnvironment {
  const _InventoryEnvironment({
    required this.environmentId,
    required this.name,
    required this.services,
  });

  final String environmentId;
  final String name;
  final List<_InventoryServiceRecord> services;

  factory _InventoryEnvironment.fromJson(JsonMap json) {
    return _InventoryEnvironment(
      environmentId: json['environmentId'] as String,
      name: json['name'] as String,
      services: [
        ..._parseServiceList(json['applications'], DokployServiceType.application, 'applicationId', 'applicationStatus'),
        ..._parseServiceList(json['compose'], DokployServiceType.compose, 'composeId', 'composeStatus'),
        ..._parseServiceList(json['mariadb'], DokployServiceType.mariadb, 'mariadbId', 'applicationStatus'),
        ..._parseServiceList(json['mongo'], DokployServiceType.mongo, 'mongoId', 'applicationStatus'),
        ..._parseServiceList(json['mysql'], DokployServiceType.mysql, 'mysqlId', 'applicationStatus'),
        ..._parseServiceList(json['postgres'], DokployServiceType.postgres, 'postgresId', 'applicationStatus'),
        ..._parseServiceList(json['redis'], DokployServiceType.redis, 'redisId', 'applicationStatus'),
        ..._parseServiceList(json['libsql'], DokployServiceType.libsql, 'libsqlId', 'applicationStatus'),
      ],
    );
  }
}

class _InventoryServiceRecord {
  const _InventoryServiceRecord({
    required this.id,
    required this.name,
    required this.appName,
    required this.status,
    required this.type,
  });

  final String id;
  final String name;
  final String? appName;
  final DokployApplicationStatus status;
  final DokployServiceType type;
}

List<_InventoryServiceRecord> _parseServiceList(
  dynamic rawValue,
  DokployServiceType type,
  String idKey,
  String statusKey,
) {
  return _asList(rawValue).map((item) => _ensureMap(item)).map((json) {
    final id = json[idKey] as String?;
    final name = json['name'] as String?;
    final status = DokployApplicationStatus.tryParse(json[statusKey] as String?);
    if (id == null || name == null || status == null) {
      return null;
    }
    return _InventoryServiceRecord(
      id: id,
      name: name,
      appName: json['appName'] as String?,
      status: status,
      type: type,
    );
  }).whereType<_InventoryServiceRecord>().toList();
}

JsonMap _ensureMap(dynamic value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  throw const FormatException('Expected JSON object.');
}

List<dynamic> _asList(dynamic value) {
  return value is List ? value : const [];
}

bool? _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return null;
}

int? _optionalCount(dynamic value) {
  if (value == null) {
    return null;
  }
  return _asList(value).length;
}

String? _firstNonEmptyString(Iterable<dynamic> values) {
  for (final value in values) {
    if (value is! String) {
      continue;
    }
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String? _normalizedLabel(dynamic value) {
  final text = value is String ? value.trim() : '';
  if (text.isEmpty) {
    return null;
  }

  return text
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

List<String> _domainLabels(dynamic value) {
  return _asList(value).map((item) {
    if (item is String) {
      return item.trim();
    }
    if (item is Map) {
      return _firstNonEmptyString([
            item['domain'],
            item['host'],
            item['domainName'],
            item['name'],
          ]) ??
          '';
    }
    return '';
  }).where((value) => value.isNotEmpty).toList();
}

List<String> _portLabels(dynamic value) {
  return _asList(value).map((item) {
    if (item is String) {
      return item.trim();
    }
    if (item is! Map) {
      return '';
    }

    final map = item.cast<String, dynamic>();
    final published = _firstNonEmptyString([
      map['publishedPort']?.toString(),
      map['published'],
      map['port'],
    ]);
    final target = _firstNonEmptyString([
      map['targetPort']?.toString(),
      map['containerPort']?.toString(),
      map['target'],
    ]);
    final protocol = _firstNonEmptyString([
      map['protocol'],
    ]);

    final parts = <String>[
      if (published != null && target != null) '$published → $target',
      if (published != null && target == null) published,
      if (protocol != null) protocol.toUpperCase(),
    ];
    return parts.join(' · ');
  }).where((value) => value.isNotEmpty).toList();
}

List<String> _stringArray(dynamic value) {
  return _asList(value)
      .whereType<String>()
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

String _errorMessage(String body, int statusCode) {
  try {
    final payload = jsonDecode(body);
    if (payload is Map) {
      final detail = _firstNonEmptyString([
        payload['detail'],
        payload['message'],
        payload['title'],
        payload['error_name'],
      ]);
      if (detail != null) {
        return detail;
      }
    }
  } on FormatException {
    // Fall through to the plain-text response body.
  }

  final trimmed = body.trim();
  if (trimmed.isNotEmpty) {
    return trimmed;
  }

  return 'Dokploy request failed with HTTP $statusCode.';
}
