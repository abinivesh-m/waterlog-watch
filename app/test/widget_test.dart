import 'package:flutter_test/flutter_test.dart';
import 'package:waterlog_watch/main.dart';

void main() {
  test('severity colours are distinct', () {
    final colors = {for (var s = 1; s <= 5; s++) severityColor(s)};
    expect(colors.length, 5);
  });
}
