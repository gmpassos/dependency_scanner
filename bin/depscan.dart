import 'dart:io';

import 'package:dependency_scanner/dependency_scanner.dart' as dependency_scanner ;

import 'package:path/path.dart' as path ;


void showHelp() {
  print('------------------------------------') ;
  print('| Dependency Scanner - version ${ dependency_scanner.VERSION } |') ;
  print('------------------------------------') ;
  print('') ;
  print('USAGE:\n') ;
  print('  \$> depscan %workspaceDirectory') ;
  print('') ;

}

void main(List<String> arguments) async {

  if (arguments.isEmpty) {
    showHelp();
    return ;

  }

  var mainDirectory = arguments[0] ;
  var command = arguments.length > 1 ? arguments[1] : null ;
  // ignore: omit_local_variable_types
  List<String> commandArgs = arguments.length > 2 ? arguments.sublist(2) : [] ;

  var depScan = dependency_scanner.DependencyScanner( Directory(mainDirectory) ) ;

  await depScan.scan() ;

  if ( command != null ) {
    await depScan.doCommand(command, commandArgs) ;
  }

  depScan.by();

}
