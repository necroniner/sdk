/// Tests for type inference.
library ddc.test.inferred_type_test;

import 'dart:convert';

import 'package:unittest/compact_vm_config.dart';
import 'package:unittest/unittest.dart';

import 'package:ddc/src/testing.dart';
import 'package:ddc/src/report.dart';

main() {
  useCompactVMConfiguration();
  test('toJson/parse', () {
    var results = testChecker({
      '/main.dart': '''
          import 'package:foo/bar.dart';

          test1() {
            x = /*severe:StaticTypeError*/"hi";
          }
      ''',
      'package:foo/bar.dart': '''
          int x;
          test2() {
            dynamic y = /*config:Box*/x;
          }
      ''',
    });

    var summary1 = checkerResultsToSummary(results);
    expect(summary1.loose['main'].messages.length, 1);
    expect(summary1.packages['foo'].libraries['bar'].messages.length, 1);

    var summary2 = GlobalSummary.parse(summary1.toJsonMap());
    expect(summary2.loose['main'].messages.length, 1);
    expect(summary2.packages['foo'].libraries['bar'].messages.length, 1);
  });
}
