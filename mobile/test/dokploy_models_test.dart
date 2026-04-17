import 'package:flutter_test/flutter_test.dart';

import 'package:dokploy_radar_mobile/src/models/dokploy_models.dart';

void main() {
  group('MonitoredService', () {
    final now = DateTime(2026, 4, 17, 12, 0);
    const recentWindow = Duration(hours: 1);

    test('classifies running services as deploying', () {
      final service = _makeService(
        applicationStatus: DokployApplicationStatus.running,
      );

      expect(service.group(now, recentWindow), MonitoredServiceGroup.deploying);
    });

    test('classifies finished deployments inside the recent window as recent', () {
      final service = _makeService(
        latestDeployment: _makeDeployment(
          status: DokployDeploymentStatus.done,
          finishedAt: now.subtract(const Duration(minutes: 15)),
        ),
      );

      expect(service.group(now, recentWindow), MonitoredServiceGroup.recent);
    });

    test('classifies error states as failed', () {
      final service = _makeService(
        applicationStatus: DokployApplicationStatus.error,
      );

      expect(service.group(now, recentWindow), MonitoredServiceGroup.failed);
    });

    test('falls back to steady when there is no recent successful deployment', () {
      final service = _makeService(
        latestDeployment: _makeDeployment(
          status: DokployDeploymentStatus.done,
          finishedAt: now.subtract(const Duration(hours: 2)),
        ),
      );

      expect(service.group(now, recentWindow), MonitoredServiceGroup.steady);
    });
  });
}

MonitoredService _makeService({
  DokployApplicationStatus applicationStatus = DokployApplicationStatus.done,
  DokployCentralizedDeployment? latestDeployment,
}) {
  return MonitoredService(
    id: 'instance-1:application:svc-1',
    instanceId: 'instance-1',
    instanceName: 'Production',
    instanceHost: 'dokploy.example.com',
    projectName: 'Acme',
    environmentName: 'prod',
    applicationId: 'svc-1',
    name: 'frontend',
    appName: 'frontend-app',
    applicationStatus: applicationStatus,
    serviceType: DokployServiceType.application,
    latestDeployment: latestDeployment,
  );
}

DokployCentralizedDeployment _makeDeployment({
  required DokployDeploymentStatus status,
  required DateTime finishedAt,
}) {
  return DokployCentralizedDeployment(
    deploymentId: 'dep-1',
    title: 'Deploy frontend',
    description: null,
    status: status,
    createdAtRaw: finishedAt.subtract(const Duration(minutes: 5)).toIso8601String(),
    startedAtRaw: finishedAt.subtract(const Duration(minutes: 4)).toIso8601String(),
    finishedAtRaw: finishedAt.toIso8601String(),
    errorMessage: null,
    application: DokployCentralizedApplication(
      applicationId: 'svc-1',
      name: 'frontend',
      appName: 'frontend-app',
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
