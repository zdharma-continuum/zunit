![ZUnit](https://zunit.xyz/img/logo.png)

[![GitHub release](https://img.shields.io/github/release/zdharma-continuum/zunit.svg)](https://github.com/zdharma-continuum/zunit/releases/latest)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/zdharma-continuum/zinit?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

ZUnit is a powerful unit testing framework for ZSH

## Installation

> **WARNING**: Although the majority of ZUnit's functionality works as expected,
> it is in the early stages of development, and as such bugs are likely to be
> present. Please continue with caution, and
> [report any issues](https://github.com/zunit-zsh/zunit/issues/new) you may
> have.

### [Zinit](https://github.com/zdharma-continuum/zinit)

```sh
zinit for \                                       
    as'command' \
    atclone'./build.zsh' \
    nocompile \
    pick'zunit' \
  @zdharma-continuum/zunit
```

### Manual

```zsh
git clone https://github.com/zdharma-continuum/zunit.git
cd zunit
./build.zsh
chmod u+x ./zunit
cp ./zunit /usr/local/bin
```

## Writing Tests

### Test syntax

Tests in ZUnit have a simple syntax, which is inspired by the
[BATS](https://github.com/sstephenson/bats) framework.

```zsh
#!/usr/bin/env zunit

@test 'example test' {
  # test logic
}
```

The body of each test can contain any valid ZSH code. The zunit shebang
`#!/usr/bin/env zunit` **MUST** appear at the top of each test file, or ZUnit
will not run it.

## Documentation

For a full breakdown of ZUnit's syntax and functionality, check out the
[official documentation](https://zunit.xyz/docs/).

## Contributing

All contributions are welcome, and encouraged. Please read our
[contribution guidelines](contributing.md) and
[code of conduct](code-of-conduct.md) for more information.

## License

ZUnit is licensed under The MIT License (MIT)

Copyright (c) 2016 - 2022 James Dinsdale <hi@molovo.co> (molovo.co)

Copyright (c) 2022 zdharma-continuum <https://github.com/zdharma-continuum>
