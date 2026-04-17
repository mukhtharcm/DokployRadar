import 'dart:convert';

class DashboardSettings {
  const DashboardSettings({
    this.refreshIntervalSeconds = 60,
    this.recentWindowMinutes = 60,
  });

  final int refreshIntervalSeconds;
  final int recentWindowMinutes;

  Duration get refreshInterval => Duration(seconds: refreshIntervalSeconds);

  Duration get recentWindow => Duration(minutes: recentWindowMinutes);

  DashboardSettings copyWith({
    int? refreshIntervalSeconds,
    int? recentWindowMinutes,
  }) {
    return DashboardSettings(
      refreshIntervalSeconds:
          refreshIntervalSeconds ?? this.refreshIntervalSeconds,
      recentWindowMinutes: recentWindowMinutes ?? this.recentWindowMinutes,
    );
  }
}

class DokployInstance {
  const DokployInstance({
    required this.id,
    required this.name,
    required this.baseUrlString,
    required this.apiToken,
    this.isEnabled = true,
  });

  final String id;
  final String name;
  final String baseUrlString;
  final String apiToken;
  final bool isEnabled;

  DokployInstance copyWith({
    String? id,
    String? name,
    String? baseUrlString,
    String? apiToken,
    bool? isEnabled,
  }) {
    return DokployInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrlString: baseUrlString ?? this.baseUrlString,
      apiToken: apiToken ?? this.apiToken,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Uri? get normalizedBaseUri {
    final trimmed = baseUrlString.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }

    final normalizedPath = uri.path == '/'
        ? ''
        : uri.path.replaceFirst(RegExp(r'/$'), '');
    return uri.replace(path: normalizedPath);
  }

  String get hostLabel => normalizedBaseUri?.host ?? baseUrlString.trim();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrlString': baseUrlString,
      'apiToken': apiToken,
      'isEnabled': isEnabled,
    };
  }

  factory DokployInstance.fromJson(Map<String, dynamic> json) {
    return DokployInstance(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrlString: json['baseUrlString'] as String,
      apiToken: json['apiToken'] as String,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  static String encodeList(List<DokployInstance> instances) {
    return jsonEncode(instances.map((instance) => instance.toJson()).toList());
  }

  static List<DokployInstance> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <DokployInstance>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <DokployInstance>[];
    }

    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map((entry) => DokployInstance.fromJson(entry.cast<String, dynamic>()))
        .toList(growable: true);
  }
}
