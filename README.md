![ZUnit](https://zunit.xyz/img/logo.png)

[![GitHub release](https://img.shields.io/github/release/zdharma-continuum/zunit.svg)](https://github.com/zdharma-continuum/zunit/releases/latest)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/zdharma-continuum/zinit?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

ZUnit is a powerful unit testing framework for ZSH

## Installation

> **WARNING**: Although the majority of ZUnit's functionality works as expected, it is in the early stages of
> development, and as such bugs are likely to be present. Please continue with caution, and
> [report any issues](https://github.com/zunit-zsh/zunit/issues/new) you may have.

### [Zinit](https://github.com/zdharma-continuum/zinit)

```sh
zinit build for @zdharma-continuum/zunit
```

### Manual

```zsh
git clone https://github.com/zdharma-continuum/zunit.git
cd zunit
./configure
make
make install
```

## Writing Tests

### Test syntax

Tests in ZUnit have a simple syntax, which is inspired by the [BATS](https://github.com/sstephenson/bats) framework.

```zsh
#!/usr/bin/env zunit

@test 'example test' {
  # test logic
}
```

The body of each test can contain any valid ZSH code. The zunit shebang `#!/usr/bin/env zunit` **MUST** appear at the
top of each test file, or ZUnit will not run it.

## Usage

```
zunit [options] [command] [tests...]
```

### Commands

| Command | Description |
| --- | --- |
| `zunit init` | Bootstrap ZUnit in a new project, writing `.zunit.yml`, a test directory and an example test |
| `zunit run [tests...]` | Run tests |

The command is optional. If the first argument is not a recognised command it is treated as a test
path and passed to `run`, so `zunit tests/example.zunit` and `zunit run tests/example.zunit` are
equivalent.

### Options

`-h`/`--help` and `-v`/`--version` are accepted anywhere, before or after a command.

| Option | Description |
| --- | --- |
| `-h`, `--help` | Output help text and exit |
| `-f`, `--fail-fast` | Stop the test runner immediately after the first failure |
| `-p`, `--parallel` | Run tests in parallel across CPU cores |
| `-r`, `--revolver` | Run tests with [revolver](https://github.com/molovo/revolver) spinner |
| `-t`, `--tap` | Output results in a TAP compatible format |
| `-v`, `--version` | Output version information and exit |
| `--allow-risky` | Suppress warnings generated for risky tests |
| `--no-progress` | Disable the progress bar during parallel runs |
| `--output-html` | Print results to a HTML page |
| `--output-text` | Print results to a text log, in TAP compatible format |
| `--time-limit <n>` | Set a time limit of n seconds for each test |
| `--verbose` | Print full output from each test |

`zunit init` takes `-t`/`--travis`, which additionally writes a `.travis.yml` to the project.

Single letter options may be stacked, and options may appear either side of the test paths, so
`zunit run -fp tests` and `zunit run tests --fail-fast --parallel` are both valid.

### Test arguments

`zunit run` accepts any number of arguments, in three forms:

```zsh
zunit run tests/example.zunit              # a single file
zunit run tests                            # a directory
zunit run 'tests/example.zunit@my test'    # a single test within a file
```

Directories are walked recursively. Within a directory, files which do not end in `.zunit` are
skipped, as is any path whose name begins with an underscore — which is what keeps `tests/_support`
and `tests/_output` out of a run. A file passed explicitly is run whatever its extension, as long as
it carries the ZUnit shebang.

With no arguments, ZUnit runs the directory named by `directories.tests` in `.zunit.yml`, falling
back to `tests`.

### Configuration

`zunit init` writes a `.zunit.yml` to the root of the project. Every key has a command line
equivalent. The boolean keys can only be turned on — an option enables a feature the config left
off, but a feature enabled in the config cannot be switched back off from the command line. The two
exceptions are `time_limit`, which `--time-limit` overrides outright, and `progress`, which
`--no-progress` disables.

```yaml
tap: false
directories:
  tests: tests
  output: tests/_output
  support: tests/_support
time_limit: 0
fail_fast: false
allow_risky: false
parallel: false
progress: true
verbose: false
revolver: false
```

| Key | Default | Notes |
| --- | --- | --- |
| `tap` | `false` | Equivalent to `--tap` |
| `directories.tests` | `tests` | Where `zunit run` looks when given no arguments |
| `directories.output` | `tests/_output` | Must be set before `--output-text` or `--output-html` will run |
| `directories.support` | `tests/_support` | Must exist if set. A `bootstrap` script inside it is sourced once before a serial run, and by each worker in a parallel run |
| `time_limit` | `0` | Seconds allowed per test. `0` means no limit |
| `fail_fast` | `false` | Equivalent to `--fail-fast` |
| `allow_risky` | `false` | Equivalent to `--allow-risky` |
| `parallel` | `false` | Equivalent to `--parallel` |
| `progress` | `true` | Set to `false` for the same effect as `--no-progress` |
| `verbose` | `false` | Equivalent to `--verbose` |
| `revolver` | `false` | Equivalent to `--revolver`. Requires the `revolver` binary on `$PATH` |

The progress bar is drawn during parallel runs only, and only when stderr is a terminal and TAP
output has not been requested, so piped output and report files are byte for byte identical to a
serial run.

During a parallel run the bootstrap script is not sourced into the runner itself. Each worker
sources it before running its share of the tests, so every worker builds its own copy of whatever
environment the script prepares, and nothing the script creates is shared between workers. A worker
whose bootstrap fails runs no tests, and the run reports the failure and exits non-zero.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Every test passed or was skipped |
| `1` | One or more tests failed, errored or warned, or the run could not be started |
| `126` | A test file was missing, or did not carry the ZUnit shebang |

## Documentation

For a full breakdown of ZUnit's syntax and functionality, check out the
[official documentation](https://zunit.xyz/docs/).

## Contributing

All contributions are welcome, and encouraged. Please read our [contribution guidelines](contributing.md) and
[code of conduct](code-of-conduct.md) for more information.

## License

ZUnit is licensed under The MIT License (MIT)

Copyright (c) 2016 - 2022 James Dinsdale <hi@molovo.co> (molovo.co)

Copyright (c) 2022 zdharma-continuum <https://github.com/zdharma-continuum>
