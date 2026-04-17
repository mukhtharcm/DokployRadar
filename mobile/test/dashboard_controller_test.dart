import 'package:dokploy_radar_mobile/src/models/app_models.dart';
import 'package:dokploy_radar_mobile/src/services/dashboard_controller.dart';
import 'package:dokploy_radar_mobile/src/services/instance_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initialize handles immutable empty stored instance lists', () async {
    final controller = DashboardController(
      store: _FakeInstanceStore(instances: const []),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.isInitialized, isTrue);
    expect(controller.initializationError, isNull);
    expect(controller.instances, isEmpty);
  });

  test('initialize surfaces storage failures instead of hanging', () async {
    final controller = DashboardController(store: _ThrowingInstanceStore());
    addTearDown(controller.dispose);

    FlutterErrorDetails? reportedError;
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      reportedError = details;
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await controller.initialize();

    expect(controller.isInitialized, isTrue);
    expect(controller.initializationError, contains('boom'));
    expect(reportedError?.exception, isA<StateError>());
  });
}

class _FakeInstanceStore extends InstanceStore {
  _FakeInstanceStore({required this.instances});

  final List<DokployInstance> instances;

  @override
  Future<List<DokployInstance>> loadInstances() async => instances;

  @override
  Future<DashboardSettings> loadSettings() async => const DashboardSettings();

  @override
  Future<String?> loadSelectedInstanceId() async => null;

  @override
  Future<void> saveInstances(List<DokployInstance> instances) async {}

  @override
  Future<void> saveSettings(DashboardSettings settings) async {}

  @override
  Future<void> saveSelectedInstanceId(String? value) async {}
}

class _ThrowingInstanceStore extends _FakeInstanceStore {
  _ThrowingInstanceStore() : super(instances: const []);

  @override
  Future<List<DokployInstance>> loadInstances() async {
    throw StateError('boom');
  }
}
