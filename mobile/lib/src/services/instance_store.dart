import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

class InstanceStore {
  InstanceStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _instancesKey = 'dokploy.mobile.instances';
  static const String _refreshIntervalKey = 'dokploy.mobile.refreshIntervalSeconds';
  static const String _recentWindowKey = 'dokploy.mobile.recentWindowMinutes';
  static const String _selectedInstanceKey = 'dokploy.mobile.selectedInstanceId';

  final FlutterSecureStorage _secureStorage;

  Future<List<DokployInstance>> loadInstances() async {
    final raw = await _secureStorage.read(key: _instancesKey);
    return DokployInstance.decodeList(raw);
  }

  Future<void> saveInstances(List<DokployInstance> instances) async {
    final raw = DokployInstance.encodeList(instances);
    await _secureStorage.write(key: _instancesKey, value: raw);
  }

  Future<DashboardSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return DashboardSettings(
      refreshIntervalSeconds: prefs.getInt(_refreshIntervalKey) ?? 60,
      recentWindowMinutes: prefs.getInt(_recentWindowKey) ?? 60,
    );
  }

  Future<void> saveSettings(DashboardSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_refreshIntervalKey, settings.refreshIntervalSeconds);
    await prefs.setInt(_recentWindowKey, settings.recentWindowMinutes);
  }

  Future<String?> loadSelectedInstanceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedInstanceKey);
  }

  Future<void> saveSelectedInstanceId(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_selectedInstanceKey);
      return;
    }
    await prefs.setString(_selectedInstanceKey, value);
  }
}
