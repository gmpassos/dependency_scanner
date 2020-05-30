import 'dart:io';

import 'package:dependency_scanner/dependency_scanner.dart'
    as dependency_scanner;

void showHelp() {
  print('--------------------------------------');
  print('| Dependency Scanner - version ${dependency_scanner.VERSION} |');
  print('--------------------------------------');
  print('');
  print('USAGE:\n');
  print('  \$> depscan %workspaceDirectory %command');
  print('');
  print('COMMANDS:');
  print('');
  print(
      '  - pubget  %projects            # Does a `pub get` in %projects list. Accepts `*` as argument.');
  print('  - list                         # List Dart projects in workspace.');
  print(
      '  - localpath %projects          # Scan %projects and point them to local path projects when possible. Accepts `*` as argument.');
  print(
      '  - rollbacklocalpath %projects  # Rollback command `localpath` in %projects. Accepts `*` as argument.');
  print(
      '  - upgradedependency %packages  # Upgrade projects dependencies that are in %packages list, checking for last version at pub.dev.');
  print('');
}

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    showHelp();
    return;
  }

  var mainDirectory = arguments[0];
  var command = arguments.length > 1 ? arguments[1] : null;
  // ignore: omit_local_variable_types
  List<String> commandArgs = arguments.length > 2 ? arguments.sublist(2) : [];

  var depScan = dependency_scanner.DependencyScanner(Directory(mainDirectory));

  await depScan.scan();

  if (command != null) {
    await depScan.doCommand(command, commandArgs);
  }

  depScan.by();
}
