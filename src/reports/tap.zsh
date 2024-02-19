########################################
# Functions for handling TAP reporting #
########################################
# vim: ft=zsh sw=4 ts=4 et foldmarker=[[[,]]] foldmethod=marker

# FUNCTION: _zunit_tap_error [[[
# Output a TAP compatible error message
function _zunit_tap_error() {
  local message="$@"

  echo "not ok ${total} - Error: ${name}"
  echo "  ---"
  echo "  message: ${message}"
  echo "  severity: fail"
  echo "  ..."

  [[ -n $fail_fast ]] && echo "Bail out!"
} # ]]]
# FUNCTION: _zunit_tap_failure [[[
# Output a TAP compatible failure message
function _zunit_tap_failure() {
  local message="$@"

  echo "not ok ${total} - Failure: ${name}"
  echo "  ---"
  echo "  message: ${message}"
  echo "  severity: fail"
  echo "  ..."

  [[ -n $fail_fast ]] && echo "Bail out!"
} # ]]]
# FUNCTION: _zunit_tap_skip [[[
# Output a TAP compatible skipped test message
function _zunit_tap_skip() {
  local message="$@"

  echo "ok ${total} - # SKIP ${name}"
  echo "  ---"
  echo "  message: ${message}"
  echo "  severity: comment"
  echo "  ..."
} # ]]]
# FUNCTION: _zunit_tap_success [[[
# Output a TAP compatible success message
function _zunit_tap_success() {
  echo "ok ${total} - ${name}"
} # ]]]
# FUNCTION: _zunit_tap_warn [[[
# Output a TAP compatible warning message
function _zunit_tap_warn() {
  local message="$@"

  echo "ok ${total} - Warning: ${name}"
  echo "  ---"
  echo "  message: ${message}"
  echo "  severity: comment"
  echo "  ..."
} # ]]]
