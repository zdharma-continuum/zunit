#!/usr/bin/env zsh

# According to the Zsh Plugin Standard:
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html#zero-handling
emulate -LR zsh
setopt extendedglob warncreateglobal typesetsilent noshortloops

0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

local ZUNIT_BIN="${${0:h}:A}/zunit"

# Clear the file to start with
cat /dev/null > "$ZUNIT_BIN"

# Start with the shebang
echo "#!/usr/bin/env zsh\n" >> "$ZUNIT_BIN"

# Print each of the source files into the target, removing any comments
# and blank lines from the compiled executable
cat ${ZUNIT_BIN:h}/src/**/(^zunit).zsh | grep -v -E '^(\s*#.*[^"]|\s*)$' >> "$ZUNIT_BIN"

# Print the main command last
cat ${ZUNIT_BIN:h}/src/zunit.zsh | grep -v -E '^(\s*#.*[^"]|\s*)$' >> "$ZUNIT_BIN"

# Make sure the file is executable
chmod u+x "$ZUNIT_BIN"

# Let the user know we're finished
builtin print -Pr "==> %Bzunit built at ${(D)ZUNIT_BIN}%b"
