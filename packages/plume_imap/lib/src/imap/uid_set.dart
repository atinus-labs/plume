/// An immutable set of message UIDs (or sequence numbers) stored as sorted,
/// non-overlapping ranges, rendered in IMAP's compressed form
/// (`1:5,8,10:12`). Used for commands and for persisted sync state.
final class UidSet {
  const UidSet._(this._ranges);

  /// The empty set.
  static const empty = UidSet._([]);

  factory UidSet.of(Iterable<int> values) {
    final sorted = values.where((v) => v > 0).toSet().toList()..sort();
    final ranges = <(int, int)>[];
    for (final v in sorted) {
      if (ranges.isNotEmpty && ranges.last.$2 + 1 == v) {
        ranges[ranges.length - 1] = (ranges.last.$1, v);
      } else {
        ranges.add((v, v));
      }
    }
    return UidSet._(List.unmodifiable(ranges));
  }

  /// `first:last`, both inclusive.
  factory UidSet.range(int first, int last) =>
      first > last || last < 1 ? empty : UidSet._(List.unmodifiable([(first < 1 ? 1 : first, last)]));

  /// Parses `1:5,8` (no `*`). Malformed pieces are skipped.
  factory UidSet.parse(String text) {
    final values = <(int, int)>[];
    for (final piece in text.split(',')) {
      final p = piece.trim();
      if (p.isEmpty) continue;
      final colon = p.indexOf(':');
      if (colon < 0) {
        final v = int.tryParse(p);
        if (v != null && v > 0) values.add((v, v));
      } else {
        final a = int.tryParse(p.substring(0, colon));
        final b = int.tryParse(p.substring(colon + 1));
        if (a != null && b != null && a > 0 && b > 0) values.add(a <= b ? (a, b) : (b, a));
      }
    }
    return _normalize(values);
  }

  static UidSet _normalize(List<(int, int)> input) {
    if (input.isEmpty) return empty;
    final sorted = [...input]..sort((a, b) => a.$1.compareTo(b.$1));
    final out = <(int, int)>[];
    for (final r in sorted) {
      if (out.isNotEmpty && r.$1 <= out.last.$2 + 1) {
        if (r.$2 > out.last.$2) out[out.length - 1] = (out.last.$1, r.$2);
      } else {
        out.add(r);
      }
    }
    return UidSet._(List.unmodifiable(out));
  }

  final List<(int, int)> _ranges;

  bool get isEmpty => _ranges.isEmpty;
  bool get isNotEmpty => _ranges.isNotEmpty;

  int get length {
    var n = 0;
    for (final r in _ranges) {
      n += r.$2 - r.$1 + 1;
    }
    return n;
  }

  /// Smallest member; throws when empty.
  int get min => _ranges.first.$1;

  /// Largest member; throws when empty.
  int get max => _ranges.last.$2;

  List<(int, int)> get ranges => _ranges;

  bool contains(int value) {
    var lo = 0;
    var hi = _ranges.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final r = _ranges[mid];
      if (value < r.$1) {
        hi = mid - 1;
      } else if (value > r.$2) {
        lo = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  /// Members in ascending order.
  Iterable<int> get values sync* {
    for (final r in _ranges) {
      for (var v = r.$1; v <= r.$2; v++) {
        yield v;
      }
    }
  }

  UidSet union(UidSet other) => _normalize([..._ranges, ...other._ranges]);

  UidSet difference(UidSet other) {
    if (other.isEmpty || isEmpty) return this;
    final out = <(int, int)>[];
    var j = 0;
    for (final r in _ranges) {
      var start = r.$1;
      final end = r.$2;
      while (j < other._ranges.length && other._ranges[j].$2 < start) {
        j++;
      }
      var k = j;
      while (start <= end) {
        if (k >= other._ranges.length || other._ranges[k].$1 > end) {
          out.add((start, end));
          break;
        }
        final o = other._ranges[k];
        if (o.$1 > start) out.add((start, o.$1 - 1));
        start = o.$2 + 1;
        k++;
      }
    }
    return UidSet._(List.unmodifiable(out));
  }

  UidSet intersection(UidSet other) => difference(difference(other));

  UidSet adding(Iterable<int> values) => union(UidSet.of(values));
  UidSet removing(Iterable<int> values) => difference(UidSet.of(values));

  /// Members greater than or equal to [floor].
  UidSet from(int floor) => floor <= 1 ? this : difference(UidSet.range(1, floor - 1));

  /// Splits into sets whose compressed form is at most [maxChars] long, so
  /// that commands stay within server line limits.
  List<UidSet> chunks({int maxChars = 4000}) {
    if (isEmpty) return const [];
    final out = <UidSet>[];
    var current = <(int, int)>[];
    var size = 0;
    for (final r in _ranges) {
      final piece = r.$1 == r.$2 ? '${r.$1}' : '${r.$1}:${r.$2}';
      if (current.isNotEmpty && size + piece.length + 1 > maxChars) {
        out.add(UidSet._(List.unmodifiable(current)));
        current = [];
        size = 0;
      }
      current.add(r);
      size += piece.length + 1;
    }
    if (current.isNotEmpty) out.add(UidSet._(List.unmodifiable(current)));
    return out;
  }

  /// The newest [count] members.
  UidSet newest(int count) {
    if (count <= 0) return empty;
    final out = <(int, int)>[];
    var left = count;
    for (var i = _ranges.length - 1; i >= 0 && left > 0; i--) {
      final r = _ranges[i];
      final n = r.$2 - r.$1 + 1;
      if (n <= left) {
        out.add(r);
        left -= n;
      } else {
        out.add((r.$2 - left + 1, r.$2));
        left = 0;
      }
    }
    return UidSet._(List.unmodifiable(out.reversed.toList()));
  }

  @override
  String toString() => _ranges.map((r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}:${r.$2}').join(',');

  @override
  bool operator ==(Object other) {
    if (other is! UidSet || other._ranges.length != _ranges.length) return false;
    for (var i = 0; i < _ranges.length; i++) {
      if (other._ranges[i] != _ranges[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_ranges);
}
