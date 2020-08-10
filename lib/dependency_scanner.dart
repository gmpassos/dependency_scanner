import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub_client/pub_client.dart' as pub_client;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec/pubspec.dart';
import 'package:swiss_knife/swiss_knife_vm.dart';

final String VERSION = '1.0.5';

class DependencyScanner {
  final Directory mainDirectory;

  final bool verbose;

  DependencyScanner(this.mainDirectory, [this.verbose = true]) {
    if (mainDirectory == null) throw ArgumentError('null mainDirectory');
  }

  Future<bool> check() async {
    if (!await mainDirectory.exists()) {
      if (verbose) print("mainDirectory doesn't extis: $mainDirectory");
      return false;
    }
    return true;
  }

  Future<List<File>> listPubSpecFiles() async {
    // ignore: omit_local_variable_types
    List<File> files = [];

    return mainDirectory.list(recursive: true).listen((entry) {
      if (entry is File) {
        var name = path.basename(entry.path);
        if (name == 'pubspec.yaml') {
          files.add(entry);
        }
      }
    }).asFuture(files);
  }

  final Map<String, List<Version>> _packagesVersionsCache = {};

  Future<List<Version>> getPackageVersions(String packageName) async {
    if (_packagesVersionsCache.containsKey(packageName)) {
      return _packagesVersionsCache[packageName];
    }

    var versions = await getPackageVersionsImpl(packageName);
    _packagesVersionsCache[packageName] = versions;

    return versions;
  }

  pub_client.PubClient _pubClient;

  pub_client.PubClient get pubClient => _pubClient ??= pub_client.PubClient();

  Future<List<Version>> getPackageVersionsImpl(String packageName) async {
    try {
      var pack = await pubClient.getPackage(packageName);
      var versions = pack.versions.map((v) => v.version).toList();
      var list = versions.map((v) => Version.parse(v)).toList();
      list.sort();
      return List.from(list.reversed).cast();
    } catch (e) {
      return [];
    }
  }

  List<Project> _scannedProjects;

  Future<List<String>> getScannedProjectsNames() async {
    return await Future.wait(
        _scannedProjects.map((p) async => (await p.pubSpec).name).toList());
  }

  Future<Project> getScannedProject(String name) async {
    for (var proj in _scannedProjects) {
      var projName = await proj.name;
      if (projName == name) return proj;
    }
    return null;
  }

  Future<List<Project>> scan() async {
    if (!await check()) {
      return [];
    }

    consoleLine();
    print('SCANNING DIRECTORY: $mainDirectory');

    var files = await listPubSpecFiles();

    print("\n* Found ${files.length} 'pubspec.yaml' files:");
    files.forEach((f) => print('  - ${f.path}'));

    var projects = files.map((f) => Project(this, f.parent)).toList();

    print('\n* Loading projects PubSpecs...');

    Project.loadPubSpecs(projects);

    print('\n* Loaded ${projects.length} projects PubSpec:');

    print('\n* Loading ${projects.length} projects versions...');

    Project.loadVersions(projects);

    Project.loadAll(projects);

    print('\n* Projects:');

    for (var project in projects) {
      var pubSpec = await project.pubSpec;

      if (pubSpec.version == null) {
        print('  - ${pubSpec.name}: NO VERSION');
        continue;
      }

      print('  - ${pubSpec.name}: ${pubSpec.version}');

      var versions = await project.versions;

      var lastVersion = await project.lastVersion;
      if (lastVersion != null &&
          pubSpec.version > lastVersion &&
          versions.isNotEmpty) {
        print('    current: ${pubSpec.version} ; published: $versions');
      }

      for (var entry in pubSpec.dependencies.entries) {
        var name = entry.key;
        var depRef = entry.value;
        if (depRef is HostedReference) {
          print('    - $name: $depRef');
        }
      }
    }

    _scannedProjects = projects;

    return List.from(projects).cast();
  }

  static void consoleLine() {
    print(
        '--------------------------------------------------------------------');
  }

  void by() {
    consoleLine();
    print('By!\n');
    exit(0);
  }

  Future<bool> doCommand(String command, List<String> args) async {
    var commandSimple =
        command.toLowerCase().trim().replaceAll(RegExp(r'[\W_]'), '');

    consoleLine();
    print('EXECUTING COMMAND: $command $args');

    switch (commandSimple) {
      case 'upgradedependency':
        return doCommand_upgradeDependency(args);
      case 'pubget':
        return doCommand_pubGet(args);
      case 'list':
        return doCommand_list();
      case 'localpath':
        return doCommand_localPath(args);
      case 'rollbacklocalpath':
        return doCommand_rollback_localPath(args);
      default:
        {
          print("** Can't find command: $command [$commandSimple]");
          return false;
        }
    }
  }

  //////////////////////////

  Future<bool> doCommand_upgradeDependency(List<String> packages) async {
    consoleLine();

    var dependenciesVersions =
        packages.map((p) => DependencyVersion.parse(p)).toList();

    print('UPGRADE DEPENDENCIES: $dependenciesVersions\n');

    if (packages.isEmpty) {
      print('** Empty arguments! No package to upgrade');
      return false;
    }

    for (var project in _scannedProjects) {
      var pubSpec = await project.pubSpec;

      print('  * Project: ${pubSpec.name} > ${project.directory}\n');

      var hasGit = await project.hasGit;
      if (!hasGit) {
        print(
            "    ** Project '${pubSpec.name}' doesn't have Git! Can't make safe modifications: skipping: ${project.directory}\n");
        continue;
      }

      for (var entry in pubSpec.dependencies.entries) {
        var depName = entry.key;
        var depVerRef = entry.value;

        var dependenciesVersion =
            DependencyVersion.getByPackage(dependenciesVersions, depName);

        if (dependenciesVersion == null) continue;

        var packVersions = await getPackageVersions(depName);
        if (packVersions == null || packVersions.isEmpty) continue;
        var packageLastVersion = packVersions[0];

        var targetVersion = dependenciesVersion.version;

        if (targetVersion == null) {
          targetVersion = packageLastVersion;
        } else {
          if (!packVersions.contains(targetVersion)) {
            throw StateError(
                "Can't upgrade package to version: $depName $targetVersion > published versions: $packVersions");
          }
        }

        if (depVerRef is HostedReference) {
          var verStr = _hostedReference_toString(depVerRef);
          var verUpper = verStr.startsWith('^');

          var depVer = _parseVersion(depVerRef);

          if (depVer < targetVersion) {
            var targetVersionStr =
                verUpper ? '^$targetVersion' : '$targetVersion';
            print(
                '    - Dependency: $depName ${verUpper ? '^' : ''}$depVer -> $targetVersionStr');

            await _rewritePubSpec_dependencyVersion(
                project, depName, targetVersionStr);
          }
        }
      }

      print('');
    }

    return true;
  }

  Future<bool> _rewritePubSpec_dependencyVersion(
      Project project, String depName, String targetVersion) async {
    var pubSpec = await project.pubSpec;

    var dialect = {
      'n': r'[\r\n]',
      's': r'[ \t]',
      'depVer': r'"?\^?[\d\.\w\+-]+"?',
      'depVerComm': r'#$depVer',
      'path': r'$n$s+path:$s*\S+$s*',
      'pathComm': r'(?:$n$s+#path:$s*\S+$s*)',
      'depHost': r'$n$s+\w+:$s*$depVer$s*$pathComm?',
      'depPath': r'$n$s+\w+:$s*(?:$depVerComm$s*)?$path',
      'dep': r'(?:$depHost|$depPath)',
      'depTarget': r'(?:$n$s*' + depName + r':$s*$depVer$s*)',
    };

    var pattern = regExpDialect(
        dialect, r'($n$s*dependencies:$s*$dep*?)($depTarget)($pathComm)?',
        multiLine: true);

    //print(pattern.pattern);

    var data = await catFile(project.pubSpecFile);

    //print('\n\n'+ regExpReplaceAll(pattern, data, r'<$1><<$2>><<<$3>>>') ) ;

    var data2 = regExpReplaceAllMapped(pattern, data, (match) {
      var g1 = match.group(1) ?? '';
      var g2 = match.group(2) ?? '';
      var g3 = match.group(3) ?? '';

      var pattern =
          regExpDialect(dialect, r'($s+\w+:$s*)$depVer($s*)', multiLine: true);

      var replace = r'${1}' + targetVersion + r'$2';

      g2 = regExpReplaceAll(pattern, g2, replace);

      return g1 + g2 + g3;
    });

    var pubSpec2 = PubSpec.fromYamlString(data2);

    _checkPubSpec(pubSpec, pubSpec2, depName);

    var fileToSave = project.pubSpecFile;

    print('      - PubSpec[${pubSpec.name}]: ${fileToSave.path}');

    var confirm = _confirm_YES('        Save new PubSpec (yes/NO)?');

    if (!confirm) {
      print("        - Response not 'yes': '$confirm'");
      print('        ** Skipping $fileToSave');
      return false;
    }

    var saveOK = (await saveFile(fileToSave, data2)) != null;

    print('      - Saved: $saveOK');

    if (saveOK) {
      print('        - Reloading project PubSpec: ${project.pubSpecFile.path}');
      await project.reloadPubSpec();
    }

    print('');

    return true;
  }

  //////////////////////////

  Future<bool> doCommand_pubGet(List<String> projects) async {
    consoleLine();

    var all = projects.firstWhere((p) => p == '*' || p.toLowerCase() == 'all',
            orElse: () => null) !=
        null;

    if (all) {
      projects = await getScannedProjectsNames();
    }

    print('PUB GET: $projects\n');

    if (projects.isEmpty) {
      print('** Empty arguments! No project to run: pub get');
      return false;
    }

    for (var projectName in projects) {
      if (projectName == '*' || projectName.toLowerCase() == 'all') continue;

      var project = await getScannedProject(projectName);

      if (project == null) {
        print("  ** Can't find project: $projectName");
        continue;
      }

      print('\n-- $projectName: running pub get...\n');

      await Process.run('pub', ['get'],
              workingDirectory: project.directory.path, runInShell: true)
          .then((result) {
        stdout.write(result.stdout);
        stderr.write(result.stderr);
      });
    }

    return true;
  }

  //////////////////////////

  Future<bool> doCommand_list() async {
    consoleLine();

    var projects = await getScannedProjectsNames();

    print('Projects:');
    print(projects.join(' '));

    return true;
  }

  //////////////////////////

  Future<bool> doCommand_localPath(List<String> projects) async {
    consoleLine();

    var all = projects.firstWhere((p) => p == '*' || p.toLowerCase() == 'all',
            orElse: () => null) !=
        null;

    if (all) {
      projects = await getScannedProjectsNames();
    }

    print('LOCAL PATH DEPENDENCIES: $projects\n');

    if (projects.isEmpty) {
      print('** Empty arguments! No project to change!');
      return false;
    }

    for (var projectName in projects) {
      if (projectName == '*' || projectName.toLowerCase() == 'all') continue;

      var project = await getScannedProject(projectName);

      if (project == null) {
        print("  ** Can't find project: $projectName");
        continue;
      }

      var pubSpec = await project.pubSpec;

      print('  * Project: ${pubSpec.name} > ${project.directory.path}\n');

      if (!(await project.hasGit)) {
        print("    ** Can't modify project without Git: $projectName\n");
        continue;
      }

      for (var entry in pubSpec.dependencies.entries) {
        var depName = entry.key;
        var depVerRef = entry.value;

        var localProject = await getScannedProject(depName);

        if (localProject == null) {
          continue;
        }

        if (depVerRef is HostedReference) {
          var verStr = _hostedReference_toString(depVerRef);
          var verUpper = verStr.startsWith('^');
          var depVer = _parseVersion(depVerRef);

          var localPubSpec = await localProject.pubSpec;

          if (localPubSpec.version < depVer) {
            print(
                '    ** Local project in a older version: ${localPubSpec.name}:${localPubSpec.version} < $depName:$verStr ');
            continue;
          } else if (localPubSpec.version > depVer && !verUpper) {
            print(
                '    ** Local project in a upper version: ${localPubSpec.name}:${localPubSpec.version} > $depName:$verStr ');
            continue;
          }

          print(
              '    - $depName[$verStr] -> [${localPubSpec.version}] ${localProject.directory.path}');

          try {
            await _rewritePubSpec_dependencyPath(
                project, depName, localProject.directory.path);
          } catch (e, s) {
            print(e);
            print(s);
            print(
                '** ERROR REWRITING PUBSPEC: $project ; ${localProject.directory.path}');
          }
        }
      }

      print('');
    }

    return true;
  }

  Future<bool> _rewritePubSpec_dependencyPath(
      Project project, String depName, String localPath) async {
    var localPathOrig = localPath;

    var pubSpec = await project.pubSpec;

    var projectParent = project.directory.absolute.parent;
    var localParent = File(localPath).absolute.parent;

    if (projectParent.path == localParent.path) {
      var simpleLocalPath = '../$depName';
      localPath = simpleLocalPath;
    }

    var dialect = {
      'n': r'[\r\n]',
      's': r'[ \t]',
      'depVer': r'"?\^?[\d\.\w\+-]+"?',
      'depVerComm': r'#$depVer',
      'path': r'$n$s+path:$s*\S+$s*',
      'pathComm': r'(?:$n$s+#path:$s*\S+$s*)',
      'depHost': r'$n$s+\w+:$s*$depVer$s*$pathComm?',
      'depPath': r'$n$s+\w+:$s*(?:$depVerComm$s*)?$path',
      'dep': r'(?:$depHost|$depPath)',
      'depTarget': r'(?:$n$s*' + depName + r':$s*$depVer$s*)',
    };

    var pattern = regExpDialect(
        dialect, r'($n$s*dependencies:$s*$dep*?)($depTarget)($pathComm)?',
        multiLine: true);

    var data = await catFile(project.pubSpecFile);

    var data2 = regExpReplaceAllMapped(pattern, data, (match) {
      var g1 = match.group(1) ?? '';
      var g2 = match.group(2) ?? '';
      var g3 = match.group(3) ?? '';

      var pattern = regExpDialect(dialect, r'($s+\w+:$s*)($depVer)($s*)',
          multiLine: true);

      g2 = regExpReplaceAll(pattern, g2, '\$1#\$2\$3');

      if (g3.isNotEmpty) {
        var patternPath = regExpDialect(
            dialect, '^(\$n\$s+)#(path:\$s*)($localPath|$localPathOrig)(\$s*)',
            multiLine: true);

        if (regExpHasMatch(patternPath, g3)) {
          var pathEntry = regExpReplaceAllMapped(patternPath, g3, (match) {
            var g3_1 = match.group(1);
            var g3_2 = match.group(2);
            //var g3_3 = match.group(3);
            var g3_4 = match.group(4);
            return g3_1 + g3_2 + localPath + g3_4;
          });

          return g1 + g2 + pathEntry;
        }
      }

      var ident = g2.replaceFirst(RegExp(r'^[\r\n]+'), '');
      ident = regExpReplaceAll(r'^(\s+).*', ident, r'$1');

      return g1 + g2 + '\n$ident  path: $localPath' + g3;
    });

    //print('\n$data2\n') ;

    PubSpec pubSpec2;

    try {
      pubSpec2 = PubSpec.fromYamlString(data2);
    } catch (e, s) {
      print(e);
      print(s);
      print('** ERROR PARSING PUBSPEC:');
      print(data2);
      throw StateError(e);
    }

    _checkPubSpec(pubSpec, pubSpec2, depName);

    var fileToSave = project.pubSpecFile;

    print('      - PubSpec[${pubSpec.name}]: ${fileToSave.path}');

    var confirm = _confirm_YES('        Save new PubSpec (yes/NO)?');

    if (!confirm) {
      print("        - Response not 'yes': '$confirm'");
      print('        ** Skipping $fileToSave\n');
      return false;
    }

    var saveOK = (await saveFile(fileToSave, data2)) != null;

    print('        - Saved: $saveOK');

    if (saveOK) {
      print('        - Reloading project PubSpec: ${project.pubSpecFile.path}');
      await project.reloadPubSpec();
    }

    print('');

    return true;
  }

  //////////////////////////

  Future<bool> doCommand_rollback_localPath(List<String> projects) async {
    consoleLine();

    var all = projects.firstWhere((p) => p == '*' || p.toLowerCase() == 'all',
            orElse: () => null) !=
        null;

    if (all) {
      projects = await getScannedProjectsNames();
    }

    print('ROLLBACK LOCAL PATH DEPENDENCIES: $projects\n');

    if (projects.isEmpty) {
      print('** Empty arguments! No project to change!');
      return false;
    }

    for (var projectName in projects) {
      if (projectName == '*' || projectName.toLowerCase() == 'all') continue;

      var project = await getScannedProject(projectName);

      if (project == null) {
        print("  ** Can't find project: $projectName");
        continue;
      }

      var pubSpec = await project.pubSpec;

      print('  * Project: ${pubSpec.name} > ${project.directory.path}\n');

      if (!(await project.hasGit)) {
        print("    ** Can't modify project without Git: $projectName\n");
        continue;
      }

      for (var entry in pubSpec.dependencies.entries) {
        var depName = entry.key;
        var depVerRef = entry.value;

        var localProject = await getScannedProject(depName);

        if (localProject == null) {
          continue;
        }

        if (depVerRef is PathReference) {
          var depPath = depVerRef.path;

          var localPubSpec = await localProject.pubSpec;

          print(
              '    - $depName[$depPath] -- ROLLBACK [${localPubSpec.version}] ${localProject.directory.path}');

          await _rewritePubSpec_dependencyHosted(
              project, depName, localProject.directory.path);
        }
      }

      print('');
    }

    return true;
  }

  Future<bool> _rewritePubSpec_dependencyHosted(
      Project project, String depName, String localPath) async {
    var localPathOrig = localPath;

    var pubSpec = await project.pubSpec;

    var projectParent = project.directory.absolute.parent;
    var localParent = File(localPath).absolute.parent;

    if (projectParent.path == localParent.path) {
      var simpleLocalPath = '../$depName';
      localPath = simpleLocalPath;
    }

    var dialect = {
      'n': r'[\r\n]',
      's': r'[ \t]',
      'depVer': r'"?\^?[\d\.\w\+-]+"?',
      'depVerComm': r'#$depVer',
      'path': r'$n$s+path:$s*\S+$s*',
      'pathComm': r'(?:$n$s+#path:$s*\S+$s*)',
      'depHost': r'$n$s+\w+:$s*$depVer$s*$pathComm?',
      'depPath': r'$n$s+\w+:$s*(?:$depVerComm$s*)?$path',
      'dep': r'(?:$depHost|$depPath)',
      'depTarget': r'(?:$n$s*' + depName + r':$s*$depVerComm$s*)',
    };

    var pattern = regExpDialect(
        dialect, r'($n$s*dependencies:$s*$dep*?)($depTarget)($path)?',
        multiLine: true);

    var data = await catFile(project.pubSpecFile);

    var hostedVersion;

    var data2 = regExpReplaceAllMapped(pattern, data, (match) {
      var g1 = match.group(1) ?? '';
      var g2 = match.group(2) ?? '';
      var g3 = match.group(3) ?? '';

      var pattern = regExpDialect(dialect, r'($s+\w+:$s*)#$s*($depVer)($s*)',
          multiLine: true);

      hostedVersion = regExpReplaceAll(pattern, g2, '\$2').trim();
      g2 = regExpReplaceAll(pattern, g2, '\$1\$2\$3');

      if (g3.isNotEmpty) {
        var patternPath = regExpDialect(
            dialect, '^(\$n\$s+)(path:\$s*)($localPath|$localPathOrig)(\$s*)',
            multiLine: true);

        if (regExpHasMatch(patternPath, g3)) {
          var pathEntry = regExpReplaceAllMapped(patternPath, g3, (match) {
            var g3_1 = match.group(1);
            var g3_2 = match.group(2);
            var g3_3 = match.group(3);
            var g3_4 = match.group(4);
            return g3_1 + '#' + g3_2 + g3_3 + g3_4;
          });

          return g1 + g2 + pathEntry;
        }
      }

      var ident = g2.replaceFirst(RegExp(r'^[\r\n]+'), '');
      ident = regExpReplaceAll(r'^(\s+).*', ident, r'$1');

      return g1 + g2 + '\n$ident  #path: $localPath';
    });

    //print('\n$data2\n') ;

    var pubSpec2 = PubSpec.fromYamlString(data2);

    _checkPubSpec(pubSpec, pubSpec2, depName);

    var fileToSave = project.pubSpecFile;

    print('      - $depName -> $hostedVersion');
    print('      - PubSpec[${pubSpec.name}]: ${fileToSave.path}');

    var confirm = _confirm_YES('        Save new PubSpec (yes/NO)?');

    if (!confirm) {
      print("        - Response not 'yes': '$confirm'");
      print('        ** Skipping $fileToSave\n');
      return false;
    }

    var saveOK = (await saveFile(fileToSave, data2)) != null;

    print('        - Saved: $saveOK');

    if (saveOK) {
      print('        - Reloading project PubSpec: ${project.pubSpecFile.path}');
      await project.reloadPubSpec();
    }

    print('');

    return true;
  }

  //////////////////////////

  void _checkPubSpec(
      PubSpec pubSpec, PubSpec pubSpec2, String ignoreDependency) {
    if (pubSpec.name != pubSpec2.name) throw StateError('name');
    if (pubSpec.version != pubSpec2.version) throw StateError('version');
    if (pubSpec.description != pubSpec2.description) {
      throw StateError('description');
    }
    if (pubSpec.documentation != pubSpec2.documentation) {
      throw StateError('documentation');
    }
    if (pubSpec.homepage != pubSpec2.homepage) throw StateError('homepage');
    if (pubSpec.publishTo != pubSpec2.publishTo) throw StateError('publishTo');
    if (!isEqualsAsString(pubSpec.environment, pubSpec2.environment)) {
      throw StateError('environment');
    }
    if (!isEqualsDeep(
        pubSpec.dependencyOverrides, pubSpec2.dependencyOverrides)) {
      throw StateError('dependencyOverrides');
    }

    var deps1 = Map.from(pubSpec.dependencies);
    var deps2 = Map.from(pubSpec2.dependencies);

    deps1.remove(ignoreDependency);
    deps2.remove(ignoreDependency);

    if (!isEqualsDeep(deps1, deps2)) {
      throw StateError('dependencies> ignoreDependency: $ignoreDependency');
    }
  }

  bool _confirm_YES(String question, [bool allowYesAll = true]) {
    return _confirm(question, ['yes', 'y'], allowYesAll);
  }

  bool _yesAll = false;

  bool get yesAll => _yesAll;

  set yesAll(bool value) {
    _yesAll = value ?? false;
  }

  bool _confirm(String question, List<String> answer,
      [bool allowYesAll = false]) {
    if (allowYesAll && _yesAll) {
      print('$question> yes (auto confirm)');
      return true;
    }

    answer = answer.map((e) => e.toLowerCase().trim()).toList();
    var resp = _ask(question).toLowerCase().trim();
    if (allowYesAll && resp.replaceAll(RegExp(r'\s'), '') == 'yesall') {
      _yesAll = true;
      resp = 'yes';
    }
    return answer.contains(resp);
  }

  String _ask(String question) {
    stdout.write('$question> ');
    var resp = stdin.readLineSync().trim().toLowerCase();
    return resp;
  }

  String _hostedReference_toString(HostedReference depVerRef) {
    var s = depVerRef.toString();
    return s.replaceAll(RegExp(r'(^"|"$)'), '');
  }

  Version _parseVersion(dynamic depVerRef) {
    var s = _hostedReference_toString(depVerRef);
    if (s.startsWith('^')) s = s.substring(1);
    return Version.parse(s);
  }
}

class DependencyVersion {
  static DependencyVersion getByPackage(
      List<DependencyVersion> list, String name) {
    return list.firstWhere((d) => d.name == name, orElse: () => null);
  }

  static bool containsPackage(List<DependencyVersion> list, String name) {
    return getByPackage(list, name) != null;
  }

  final String name;

  final Version version;

  DependencyVersion(this.name, [dynamic version])
      : version = version is Version
            ? version
            : (version is String || version is num
                ? Version.parse('$version'.trim())
                : null) {
    if (!RegExp(r'^\w+$').hasMatch(name)) {
      throw ArgumentError('Invalid name: $name');
    }
  }

  factory DependencyVersion.parse(String s) {
    if (s == null) return null;
    s = s.trim();
    if (s.isEmpty) return null;

    var idx = s.indexOf(RegExp(r'[,:]'));

    if (idx > 0) {
      var name = s.substring(0, idx).trim();
      var ver = s.substring(idx + 1).trim();
      if (ver.isEmpty) ver = null;
      return DependencyVersion(name, ver);
    } else {
      return DependencyVersion(s);
    }
  }

  @override
  String toString() {
    return version != null ? '{$name: $version}' : '{$name}';
  }
}

class Project {
  static void loadPubSpecs(List<Project> projects) {
    Future.wait(projects.map((p) => p.pubSpec));
  }

  static void loadVersions(List<Project> projects) {
    Future.wait(projects.map((p) => p.versions));
  }

  static void loadAll(List<Project> projects) {
    Future.wait(projects.map((p) async {
      var pubSpec = await p.pubSpec;
      var versions = await p.versions;
      var hasGit = await p.hasGit;
      return '$pubSpec $versions $hasGit';
    }));
  }

  final DependencyScanner scanner;

  final Directory directory;

  Project(this.scanner, this.directory);

  Future<PubSpec> reloadPubSpec() async {
    _pubSpec = null;
    return await pubSpec;
  }

  PubSpec _pubSpec;

  Future<PubSpec> get pubSpec async {
    if (_pubSpec != null) return _pubSpec;
    _pubSpec = await PubSpec.loadFile(pubSpecFile.path);
    return _pubSpec;
  }

  Future<String> get name async => (await pubSpec).name;

  File get pubSpecFile => File(path.join(directory.path, 'pubspec.yaml'));

  List<Version> _versions;

  Future<List<Version>> get versions async {
    if (_versions == null) {
      var pubSpec = await this.pubSpec;
      _versions = await scanner.getPackageVersions(pubSpec.name);
    }
    return List.from(_versions).cast();
  }

  Version _lastVersion;

  Future<Version> get lastVersion async {
    if (_lastVersion == null) {
      var vers = await versions;
      _lastVersion = vers.isNotEmpty ? vers[0] : Version.none;
    }
    return _lastVersion;
  }

  bool _hasGit;

  Future<bool> get hasGit async {
    _hasGit ??= await gitDirectory.exists();
    return _hasGit;
  }

  Directory get gitDirectory => Directory(path.join(directory.path, '.git'));
}
