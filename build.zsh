#!/usr/bin/env zsh

# Clear the file to start with

(){
  0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
  0="${${(M)0:#/*}:-$PWD/$0}"

  BUILD_DIR="${0:h}"
  ZUNIT_PATH="${BUILD_DIR}/zunit"
  cat /dev/null > $ZUNIT_PATH

  # Start with the shebang
  echo "#!/usr/bin/env zsh\n" >> $ZUNIT_PATH

  # We need to do some fancy globbing
  emulate -L zsh
  setopt EXTENDED_GLOB

  # Print each of the source files into the target, removing any comments
  # and blank lines from the compiled executable
  cat src/**/(^zunit).zsh | grep -v -E '^(\s*#.*[^"]|\s*)$' >> $ZUNIT_PATH
  # Print the main command last
  cat src/zunit.zsh | grep -v -E '^(\s*#.*[^"]|\s*)$' >> $ZUNIT_PATH
  # Make sure the file is executable
  chmod u+x $ZUNIT_PATH
  # Let the user know we're finished
  echo "\033[0;32m✔\033[0;m ZUnit built successfully"
}
