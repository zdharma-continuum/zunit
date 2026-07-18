###############################################
# Functions for running tests in parallel     #
###############################################

# FUNCTION: _zunit_parallel_child_bail [[[
# Stop a worker early after a failure when --fail-fast is set
function _zunit_parallel_child_bail() {
    [[ -n $__zunit_parallel_fail_fast ]] || return 0

    _zunit_parallel_child_finish
    exit 1
} # ]]]
# FUNCTION: _zunit_parallel_child_finish [[[
# Atomically write a worker's recorded events to its state file
function _zunit_parallel_child_finish() {
    local event

    {
        print -r -- "__zunit_parallel_total=$total"
        print -r -- "__zunit_parallel_events=("
        for event in "${__zunit_parallel_events[@]}"; do
            print -r -- "  ${(q+)event}"
        done
        print -r -- ")"
    } > "${__zunit_parallel_statefile}.tmp"

    mv "${__zunit_parallel_statefile}.tmp" "$__zunit_parallel_statefile"
} # ]]]
# FUNCTION: _zunit_parallel_child_init [[[
# Prepare a worker subshell: replace the event handlers with
# recorders, and disable all reporting output
function _zunit_parallel_child_init() {
    # Make sure the parent's cleanup trap is not inherited
    trap - EXIT

    _zunit_parallel_child=1
    __zunit_parallel_statefile="$1.state"
    __zunit_parallel_fail_fast=$fail_fast
    __zunit_parallel_events=()

    total=0

    # Workers never print TAP output, write report files or shut the
    # runner down - the parent does all of that while replaying the
    # recorded events in serial order
    fail_fast=''
    tap=''
    output_text=''
    output_html=''

    function _zunit_success() {
        _zunit_parallel_record success "$@"
    }
    function _zunit_failure() {
        _zunit_parallel_record failure "$@"
        _zunit_parallel_child_bail
    }
    function _zunit_error() {
        _zunit_parallel_record error "$@"
        _zunit_parallel_child_bail
    }
    function _zunit_skip() {
        _zunit_parallel_record skip "$@"
    }
    function _zunit_warn() {
        _zunit_parallel_record warn "$@"
    }
    function _zunit_verbose_output() {
        [[ -n $verbose && -n "$1" ]] && _zunit_parallel_record verbose "$@"
        return 0
    }
} # ]]]
# FUNCTION: _zunit_parallel_cores [[[
# Detect the number of available CPU cores
function _zunit_parallel_cores() {
    integer cores=0

    if (( $+commands[nproc] )); then
        cores=$(nproc 2>/dev/null)
    elif (( $+commands[getconf] )); then
        cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    elif (( $+commands[sysctl] )); then
        cores=$(sysctl -n hw.ncpu 2>/dev/null)
    fi

    (( cores > 0 )) || cores=2

    echo $cores
} # ]]]
# FUNCTION: _zunit_parallel_record [[[
# Record a result event, preserving the current test name
# and test count at the time of the event
function _zunit_parallel_record() {
    local -a fields
    fields=("$1" "$name" "$total" "${(@)@:2}")

    __zunit_parallel_events+=("${(pj:\x1f:)fields}")
} # ]]]
# FUNCTION: _zunit_parallel_replay [[[
# Replay a worker's recorded events through the real event handlers
function _zunit_parallel_replay() {
    local statefile="$1.state" event
    local -a __zunit_parallel_events fields
    integer __zunit_parallel_total=0
    integer __zunit_parallel_base=$total

    if [[ ! -f $statefile ]]; then
        # The worker died before it could report its results
        __zunit_parallel_crashed=1
        name='parallel worker'
        _zunit_error 'Parallel worker exited unexpectedly' "$(cat "$1.log" 2>/dev/null)"
        return 1
    fi

    source "$statefile"

    for event in "${__zunit_parallel_events[@]}"; do
        fields=("${(@ps:\x1f:)event}")
        name="${fields[2]}"
        total=$(( __zunit_parallel_base + ${fields[3]:-0} ))

        case "${fields[1]}" in
            verbose ) _zunit_verbose_output "${(@)fields[4,-1]}" ;;
            success ) _zunit_success "${(@)fields[4,-1]}" ;;
            failure ) _zunit_failure "${(@)fields[4,-1]}" ;;
            error )   _zunit_error   "${(@)fields[4,-1]}" ;;
            skip )    _zunit_skip    "${(@)fields[4,-1]}" ;;
            warn )    _zunit_warn    "${(@)fields[4,-1]}" ;;
        esac
    done

    total=$(( __zunit_parallel_base + __zunit_parallel_total ))
} # ]]]
# FUNCTION: _zunit_parallel_run [[[
# Run the queued test files in parallel, then replay the recorded
# results in the same order as a serial run would produce them
function _zunit_parallel_run() {
    # All locals here remain visible to test code running inside the
    # worker subshells via dynamic scope, so every name is prefixed
    # to avoid collisions with variables used in tests
    integer __zunit_parallel_max=$(_zunit_parallel_cores)
    integer __zunit_parallel_k
    local __zunit_parallel_file __zunit_parallel_prev
    local -a __zunit_parallel_ordered __zunit_parallel_args
    local -a __zunit_parallel_groups __zunit_parallel_ngroups
    local -a __zunit_parallel_pids

    __zunit_parallel_ordered=(${(o)testfiles})
    (( ${#__zunit_parallel_ordered} > 0 )) || return 0

    local __zunit_parallel_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/zunit-parallel.XXXXXXXX")"
    trap "rm -rf ${(q)__zunit_parallel_tmpdir}" EXIT

    # Build the list of work units. Each unit is either a whole test
    # file, or a contiguous slice of the tests in a single file
    if (( ${#__zunit_parallel_ordered} == 1 )); then
        for (( __zunit_parallel_k=1; __zunit_parallel_k <= __zunit_parallel_max; __zunit_parallel_k++ )); do
            __zunit_parallel_args+=("${__zunit_parallel_ordered[1]}")
            __zunit_parallel_groups+=($__zunit_parallel_k)
            __zunit_parallel_ngroups+=($__zunit_parallel_max)
        done
    else
        for __zunit_parallel_file in "${__zunit_parallel_ordered[@]}"; do
            __zunit_parallel_args+=("$__zunit_parallel_file")
            __zunit_parallel_groups+=(0)
            __zunit_parallel_ngroups+=(0)
        done
    fi

    # Spawn a worker subshell per unit, never running more
    # than $__zunit_parallel_max workers at once
    for (( __zunit_parallel_k=1; __zunit_parallel_k <= ${#__zunit_parallel_args}; __zunit_parallel_k++ )); do
        _zunit_parallel_wait_slot $__zunit_parallel_max
        (
            _zunit_parallel_child_init "$__zunit_parallel_tmpdir/$__zunit_parallel_k"
            _zunit_run_testfile "${__zunit_parallel_args[$__zunit_parallel_k]}" \
                "${__zunit_parallel_groups[$__zunit_parallel_k]}" \
                "${__zunit_parallel_ngroups[$__zunit_parallel_k]}"
            _zunit_parallel_child_finish
        ) > "$__zunit_parallel_tmpdir/$__zunit_parallel_k.log" 2>&1 &
        __zunit_parallel_pids+=($!)
    done

    wait

    # Replay each worker's recorded events, in the order a serial
    # run would have produced them
    __zunit_parallel_prev=''
    for (( __zunit_parallel_k=1; __zunit_parallel_k <= ${#__zunit_parallel_args}; __zunit_parallel_k++ )); do
        __zunit_parallel_file="${${(s/@/)__zunit_parallel_args[$__zunit_parallel_k]}[1]}"

        # Print the file header once per file - workers suppress theirs
        if [[ "$__zunit_parallel_file" != "$__zunit_parallel_prev" ]] || (( ${__zunit_parallel_groups[$__zunit_parallel_k]} == 0 )); then
            print -Pr "%F{blue}==>%f Loading tests in %B${__zunit_parallel_file}%b"
        fi
        __zunit_parallel_prev="$__zunit_parallel_file"

        _zunit_parallel_replay "$__zunit_parallel_tmpdir/$__zunit_parallel_k"
    done
} # ]]]
# FUNCTION: _zunit_parallel_wait_slot [[[
# Block until fewer than $1 worker processes are still running
function _zunit_parallel_wait_slot() {
    integer max_procs=$1
    local pid
    local -a alive

    while (( ${#__zunit_parallel_pids} >= max_procs )); do
        alive=()
        for pid in "${__zunit_parallel_pids[@]}"; do
            kill -0 $pid 2>/dev/null && alive+=($pid)
        done
        __zunit_parallel_pids=($alive)

        (( ${#__zunit_parallel_pids} >= max_procs )) && sleep 0.1
    done

    return 0
} # ]]]

# vim: ft=zsh sw=4 ts=4 et foldmarker=[[[,]]] foldmethod=marker
