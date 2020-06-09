# dependency_scanner

[![pub package](https://img.shields.io/pub/v/dependency_scanner.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/dependency_scanner)
[![CI](https://img.shields.io/github/workflow/status/gmpassos/dependency_scanner/Dart%20CI/master?logo=github-actions&logoColor=white)](https://github.com/gmpassos/dependency_scanner/actions)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/dependency_scanner?logo=git&logoColor=white)](https://github.com/gmpassos/dependency_scanner/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/dependency_scanner/latest?logo=git&logoColor=white)](https://github.com/gmpassos/dependency_scanner/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/dependency_scanner?logo=git&logoColor=white)](https://github.com/gmpassos/dependency_scanner/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/dependency_scanner?logo=github&logoColor=white)](https://github.com/gmpassos/dependency_scanner/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/dependency_scanner?logo=github&logoColor=white)](https://github.com/gmpassos/dependency_scanner)
[![License](https://img.shields.io/github/license/gmpassos/dependency_scanner?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/dependency_scanner/blob/master/LICENSE)
[![Funding](https://img.shields.io/badge/Donate-yellow?labelColor=666666&style=plastic&logo=liberapay)](https://liberapay.com/gmpassos/donate)
[![Funding](https://img.shields.io/liberapay/patrons/gmpassos.svg?logo=liberapay)](https://liberapay.com/gmpassos/donate)


Dart Dependency Scanner: scans workspace directory for Dart projects and runs batch commands over them. 

# Commands

## pub_get

* pub get in all workspace dart projects:

    ```bash
    $> depscan /path/to/your/workspace_dir pub_get all
    ```

* pub get in specific projects

    ```bash
    $> depscan /path/to/your/workspace_dir pub_get projects1 projects2 extra_project
    ```
## list

* List all projects in workspace

    ```bash
    $> depscan /path/to/your/workspace_dir list
    ```

## upgrade_dependency

* Upgrade a specific dependency in all projects

    ```bash
    $> depscan /path/to/your/workspace_dir upgrade_dependency swiss_knife
    ```
    * All projects with the dependency `swiss_knife` where upgraded to the last published version.

* Upgrade a specific dependency to a specific version in all projects

    ```bash
    $> depscan /path/to/your/workspace_dir upgrade_dependency swiss_knife:2.3.7
    ```
    * All projects with the dependency `swiss_knife` where upgraded to version 2.3.7

## local_path

* Change a specific dependency to local workspace path:

    ```bash
    $> depscan /path/to/your/workspace_dir local_path swiss_knife
    ```
    * All projects with the dependency `swiss_knife` where referencing to '../swiss_knife' (if found in the same workspace).

* Change all dependencies to local workspace path:

    ```bash
    $> depscan /path/to/your/workspace_dir local_path all
    ```
    * All projects with any dependency also present in the workspace will point to a local path.

## rollback_local_path

* Rollback a specific local dependency to local hosted version:

    ```bash
    $> depscan /path/to/your/workspace_dir rollback_local_path swiss_knife
    ```
    * All projects with local dependency `swiss_knife` will point to commented hosted version.

* Rollback all local dependencies to commented hosted versions:

    ```bash
    $> depscan /path/to/your/workspace_dir rollback_local_path all
    ```
    * All projects with any local dependency project will reference to hosted versions (using commented versions by 'local_path' command).


## Git

Only projects with `git` will be changed as a safety measure. Git allows rollback of any change and control history of your files.

## Common usage

Upgrade and resolve a dependency in all your projects:

```bash
$> depscan /path/to/your/workspace_dir upgrade_dependency swiss_knife
$> depscan /path/to/your/workspace_dir pub_get all
```

Point dependencies to your local workspace projects: 

```bash
$> depscan /path/to/your/workspace_dir local_path all
$> depscan /path/to/your/workspace_dir pub_get all
```

Rollback local dependencies to hosted versions: 

```bash
$> depscan /path/to/your/workspace_dir rollback_local_path all
$> depscan /path/to/your/workspace_dir pub_get all
```

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/gmpassos/dependency_scanner/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

Dart free & open-source [license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).
