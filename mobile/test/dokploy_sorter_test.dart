import 'package:flutter_test/flutter_test.dart';

import 'package:dokploy_radar_mobile/src/models/dokploy_models.dart';

void main() {
  group('DokploySorter', () {
    final now = DateTime(2026, 4, 17, 12, 0);
    const recentWindow = Duration(hours: 1);

    test('sorts services by status priority before name', () {
      final services = [
        _service(
          id: 'steady',
          name: 'steady',
          latestDeployment: _deployment(
            id: 'steady',
            status: DokployDeploymentStatus.done,
            finishedAt: now.subtract(const Duration(hours: 2)),
          ),
        ),
        _service(
          id: 'recent',
          name: 'recent',
          latestDeployment: _deployment(
            id: 'recent',
            status: DokployDeploymentStatus.done,
            finishedAt: now.subtract(const Duration(minutes: 20)),
          ),
        ),
        _service(
          id: 'deploying',
          name: 'deploying',
          applicationStatus: DokployApplicationStatus.running,
        ),
      ];

      final sorted = DokploySorter.sortServices(
        services,
        now: now,
        recentWindow: recentWindow,
      );

      expect(sorted.map((service) => service.id), ['deploying', 'recent', 'steady']);
    });

    test('sorts activity by priority then recency', () {
      final items = [
        DokployActivityItem(
          id: 'recent',
          instanceId: 'instance-1',
          instanceName: 'Production',
          instanceHost: 'dokploy.example.com',
          serviceId: 'svc-1',
          serviceName: 'frontend',
          appName: 'frontend-app',
          serviceType: DokployServiceType.application,
          projectName: 'Acme',
          environmentName: 'prod',
          relatedEntryId: 'svc-1',
          title: 'Done',
          description: null,
          errorMessage: null,
          state: DokployActivityState.recent,
          createdAt: now.subtract(const Duration(minutes: 10)),
          startedAt: now.subtract(const Duration(minutes: 9)),
          finishedAt: now.subtract(const Duration(minutes: 8)),
        ),
        DokployActivityItem(
          id: 'queued',
          instanceId: 'instance-1',
          instanceName: 'Production',
          instanceHost: 'dokploy.example.com',
          serviceId: 'svc-2',
          serviceName: 'api',
          appName: 'api-app',
          serviceType: DokployServiceType.application,
          projectName: 'Acme',
          environmentName: 'prod',
          relatedEntryId: 'svc-2',
          title: 'Queued',
          description: null,
          errorMessage: null,
          state: DokployActivityState.queued,
          createdAt: now.subtract(const Duration(minutes: 1)),
          startedAt: null,
          finishedAt: null,
        ),
      ];

      final sorted = DokploySorter.sortActivity(items);

      expect(sorted.map((item) => item.id), ['queued', 'recent']);
    });
  });
}

MonitoredService _service({
  required String id,
  required String name,
  DokployApplicationStatus applicationStatus = DokployApplicationStatus.done,
  DokployCentralizedDeployment? latestDeployment,
}) {
  return MonitoredService(
    id: id,
    instanceId: 'instance-1',
    instanceName: 'Production',
    instanceHost: 'dokploy.example.com',
    projectName: 'Acme',
    environmentName: 'prod',
    applicationId: id,
    name: name,
    appName: '$name-app',
    applicationStatus: applicationStatus,
    serviceType: DokployServiceType.application,
    latestDeployment: latestDeployment,
  );
}

DokployCentralizedDeployment _deployment({
  required String id,
  required DokployDeploymentStatus status,
  required DateTime finishedAt,
}) {
  return DokployCentralizedDeployment(
    deploymentId: 'dep-$id',
    title: 'Deploy $id',
    description: null,
    status: status,
    createdAtRaw: finishedAt.subtract(const Duration(minutes: 5)).toIso8601String(),
    startedAtRaw: finishedAt.subtract(const Duration(minutes: 4)).toIso8601String(),
    finishedAtRaw: finishedAt.toIso8601String(),
    errorMessage: null,
    application: DokployCentralizedApplication(
      applicationId: id,
      name: id,
      appName: '$id-app',
      environment: DokployCentralizedEnvironment(
        environmentId: 'env-1',
        name: 'prod',
        project: const DokployCentralizedProject(
          projectId: 'proj-1',
          name: 'Acme',
        ),
      ),
    ),
    compose: null,
  );
}
