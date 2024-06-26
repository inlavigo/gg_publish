// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_git/gg_git_test_helpers.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:gg_version/gg_version.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

// .............................................................................
/// A Mock for the http.Client class using Mocktail
class MockClient extends Mock implements http.Client {}

void main() {
  final messages = <String>[];
  late CommandRunner<dynamic> runner;
  late IsLatestStatePublished isLatestStatePublished;
  late Directory tmp;
  late Directory d;
  late http.Client httpClient;

  // ...........................................................................
  Future<void> initIsLatestStatePublished() async {
    isLatestStatePublished = IsLatestStatePublished(
      ggLog: messages.add,
      publishedVersion: PublishedVersion(
        ggLog: messages.add,
        httpClient: httpClient,
      ),
      consistentVersion: ConsistentVersion(
        ggLog: messages.add,
      ),
    );
    runner.addCommand(isLatestStatePublished);
  }

  // ...........................................................................
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp();
    d = Directory('${tmp.path}/test');
    await d.create();

    messages.clear();
    runner = CommandRunner<dynamic>('test', 'test');
    httpClient = MockClient();
    await initIsLatestStatePublished();
  });

  // ...........................................................................
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('IsLatestStatePublished', () {
    group('constructor', () {
      test('should create instances of PublishedVersion and ConsistentVersion',
          () {
        IsLatestStatePublished(ggLog: messages.add);
      });
    });

    group('get(...)', () {
      // .......................................................................
      group('should return false', () {
        group('and log the reason', () {
          test('when the directory is not a git repo', () async {
            await expectLater(
              isLatestStatePublished.get(directory: d, ggLog: messages.add),
              throwsA(
                isA<ArgumentError>().having(
                  (e) => e.toString(),
                  'toString()',
                  contains('Directory "test" is not a git repository.'),
                ),
              ),
            );
          });

          group('when there is not a consistent version assigned', () {
            test('to pubspec.yaml, CHANGELOG.md and git', () async {
              await initGit(d);
              await addAndCommitSampleFile(d);

              await addAndCommitVersions(
                d,
                pubspec: '1.0.0',
                changeLog: '1.0.1',
                gitHead: '1.0.0',
              );

              await expectLater(
                isLatestStatePublished.get(directory: d, ggLog: messages.add),
                throwsA(
                  isA<Exception>().having(
                    (e) => e.toString(),
                    'toString()',
                    contains(
                      'Versions are not consistent: '
                      '- pubspec: 1.0.0, - changeLog: 1.0.1, - gitHead: 1.0.0',
                    ),
                  ),
                ),
              );
            });
          });

          test('when the local version is behind published version', () async {
            // Mock local version 1.0.0
            await initGit(d);
            final pubSpec = File('test/sample_package/pubspec.yaml');
            pubSpec.copySync('${d.path}/pubspec.yaml');

            await addAndCommitVersions(
              d,
              pubspec: '1.0.0',
              changeLog: '1.0.0',
              gitHead: '1.0.0',
            );

            // Mock published version 1.0.2
            final responseContent =
                File('test/sample_package/pub_dev_sample_response.json')
                    .readAsStringSync();
            final uri = Uri.parse('https://pub.dev/api/packages/gg_check');
            when(() => httpClient.get(uri)).thenAnswer(
              (_) async => http.Response(responseContent, 200),
            );

            // Call isPublished.get()
            await expectLater(
              isLatestStatePublished.get(directory: d, ggLog: messages.add),

              // Should throw
              throwsA(
                isA<Exception>().having(
                  (e) => e.toString(),
                  'toString()',
                  contains(
                    'The local version "1.0.0" '
                    'is behind published version 1.0.2. '
                    'Update and try again.',
                  ),
                ),
              ),
            );
          });
        });
      });

      group('should return true', () {
        test('when the local version matches the published version', () async {
          // Mock local version 1.0.2
          await initGit(d);

          await addAndCommitVersions(
            d,
            pubspec: '1.0.2',
            changeLog: '1.0.2',
            gitHead: '1.0.2',
          );

          // Mock published version 1.0.2
          final responseContent =
              File('test/sample_package/pub_dev_sample_response.json')
                  .readAsStringSync();
          final uri = Uri.parse('https://pub.dev/api/packages/test');
          when(() => httpClient.get(uri)).thenAnswer(
            (_) async => http.Response(responseContent, 200),
          );

          // Call isPublished.get()
          final result = await isLatestStatePublished.get(
            directory: d,
            ggLog: messages.add,
          );

          expect(result, isTrue);
        });
      });
    });
    group('run()', () {
      group('should print', () {
        group('a usage description', () {
          test('when called with --help', () async {
            capturePrint(
              ggLog: messages.add,
              code: () => runner.run(
                ['--help'],
              ),
            );

            expect(messages.last, contains('Available commands:'));
            expect(messages.last, contains(isLatestStatePublished.name));
            expect(messages.last, contains(isLatestStatePublished.description));
          });
        });

        group('the current version', () {
          test('when called without arguments', () async {
            await initGit(d);

            await addAndCommitVersions(
              d,
              pubspec: '1.0.2',
              changeLog: '1.0.2',
              gitHead: '1.0.2',
            );

            // Mock published version 1.0.2
            final responseContent =
                File('test/sample_package/pub_dev_sample_response.json')
                    .readAsStringSync();
            final uri = Uri.parse('https://pub.dev/api/packages/test');
            when(() => httpClient.get(uri)).thenAnswer(
              (_) async => http.Response(responseContent, 200),
            );

            // Call isPublished.run()
            await runner.run(
              ['is-latest-state-published', '--input', d.path],
            );

            expect(messages.last, contains('✅ Latest state is on pub.dev.'));
          });
        });
      });

      group('should throw', () {
        group(' an error message', () {
          test('when called with an invalid argument', () async {
            await expectLater(
              runner.run(
                ['is-latest-state-published', '--input', 'xyz'],
              ),
              throwsA(
                isA<ArgumentError>().having(
                  (e) => e.toString(),
                  'toString()',
                  contains(
                    'Invalid argument(s): Directory "xyz" does not exist.',
                  ),
                ),
              ),
            );
          });
        });
      });
    });
  });
}
