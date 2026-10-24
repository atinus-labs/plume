import 'package:plume_core/plume_core.dart';

/// A [TokenSource] that hands out `token-1`, `token-2`... advancing on
/// each [invalidate].
class FakeTokenSource implements TokenSource {
  FakeTokenSource({this.failWith});

  int generation = 1;
  int invalidations = 0;
  int calls = 0;
  MailException? failWith;

  String get current => 'token-$generation';

  @override
  Future<String> accessToken() async {
    calls++;
    final f = failWith;
    if (f != null) throw f;
    return current;
  }

  @override
  void invalidate() {
    invalidations++;
    generation++;
  }
}
