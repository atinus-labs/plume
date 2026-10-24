/// Small, strict-cast-friendly helpers for reading decoded JSON.
library;

typedef JsonMap = Map<String, Object?>;

/// Returns [value] as a JSON object, or null when it is not one.
JsonMap? asJsonMap(Object? value) => value is Map ? value.cast<String, Object?>() : null;

extension JsonRead on JsonMap {
  /// A string field. Numbers are stringified because Google APIs encode
  /// 64-bit integers as strings and the reverse occasionally happens.
  String? str(String key) {
    final v = this[key];
    if (v is String) return v;
    if (v is num) return v.toString();
    return null;
  }

  /// An integer field, accepting both JSON numbers and numeric strings.
  int? integer(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  JsonMap? obj(String key) => asJsonMap(this[key]);

  List<JsonMap> objList(String key) {
    final v = this[key];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) e.cast<String, Object?>(),
    ];
  }

  List<String> strList(String key) {
    final v = this[key];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is String) e,
    ];
  }
}
