###############################################
# Functions for running tests in parallel     #
###############################################

# FUNCTION: _zunit_parallel_child_bail [[[
# Stop a worker early after a failure when --fail-fast is set
function _zunit_parallel_child_bail() {
    [[ -n $__zunit_parallel_fail_fast ]] || return 0

    # Signal the other workers and the spawn loop to stop
    : >| "$__zunit_parallel_abortfile"

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
        # Written last, so a truncated state file is detectable
        print -r -- "__zunit_parallel_done=1"
    } > "${__zunit_parallel_statefile}.tmp"

    mv "${__zunit_parallel_statefile}.tmp" "$__zunit_parallel_statefile"
} # ]]]
# FUNCTION: _zunit_parallel_child_init [[[
# Prepare a worker subshell: replace the event handlers with
# recorders, and disable all reporting output
function _zunit_parallel_child_init() {
    # Make sure the parent's traps are not inherited. A worker which
    # kept the resize handler would paint a progress bar into its own
    # log file every time the window changed size
    trap - EXIT
    trap - WINCH

    _zunit_parallel_child=1
    __zunit_parallel_statefile="$1.state"
    __zunit_parallel_abortfile="${1:h}/abort"
    __zunit_parallel_progressfile="${1:h}/progress"
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
# Detect the number of available CPU cores. The commands are tried
# directly rather than probed via $+commands, because the first
# access to the commands hash scans every directory in $PATH, which
# is very slow on systems with slow filesystem mounts in their path
function _zunit_parallel_cores() {
    integer cores=0

    cores=$(nproc 2>/dev/null) \
        || cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null) \
        || cores=$(sysctl -n hw.ncpu 2>/dev/null)

    (( cores > 0 )) || cores=2

    echo $cores
} # ]]]
# FUNCTION: _zunit_parallel_count_tests [[[
# Approximate the number of tests in a file. Used only to bound the
# worker count, so an overcount is harmless
function _zunit_parallel_count_tests() {
    integer count=$(grep -cE '^ *@test +[^ ].* +\{' "$1" 2>/dev/null)

    (( count > 0 )) || count=1

    echo $count
} # ]]]
# FUNCTION: _zunit_parallel_progress_clear [[[
# Erase the progress bar and hand the terminal back in the state it
# was found in. Safe to call more than once, and from the EXIT trap,
# where the locals of the function which started the run have already
# gone out of scope
function _zunit_parallel_progress_clear() {
    [[ -n $__zunit_parallel_progress ]] || return 0

    __zunit_parallel_progress=''
    __zunit_parallel_progress_last=''
    trap - WINCH

    # Erase the bar, then give the cursor back
    print -nu2 -- $'\r\e[K\e[?25h'

    # Restore the terminal mode the run started with. SIGTTOU is
    # ignored while the settings are written, so that a runner which
    # has been backgrounded is not stopped by its own stty
    if [[ -n $__zunit_parallel_progress_stty ]]; then
        trap '' TTOU
        stty "$__zunit_parallel_progress_stty" <&2 2>/dev/null
        trap - TTOU
        __zunit_parallel_progress_stty=''
    fi

    return 0
} # ]]]
# FUNCTION: _zunit_parallel_progress_columns [[[
# Measure the width of the terminal the bar is drawn on. $COLUMNS is
# only a fallback: a non interactive shell does not refresh it while
# the run is in progress, so a window which is resized mid run leaves
# it stale, and a bar drawn to a stale width wraps. A wrapped line
# cannot be erased with a single escape sequence, so every redraw
# after it strands another copy on the screen
function _zunit_parallel_progress_columns() {
    local -a size
    integer cols=0

    size=(${=$(stty size <&2 2>/dev/null)})
    cols=${size[2]:-0}

    # Each fallback is only reached when the one before it has
    # nothing to say - a pseudo terminal created by zpty, for
    # example, reports no window size at all
    (( cols > 0 )) || cols=${COLUMNS:-0}
    (( cols > 0 )) || cols=80

    typeset -g __zunit_parallel_progress_cols=$cols

    return 0
} # ]]]
# FUNCTION: _zunit_parallel_progress_draw [[[
# Redraw the progress bar from the ticks which the workers have
# written to the shared progress file
function _zunit_parallel_progress_draw() {
    [[ -n $__zunit_parallel_progress ]] || return 0

    local ticks bar suffix line
    integer width=24 completed=0 passed=0 failed=0 filled=0
    integer columns

    if [[ -f $__zunit_parallel_progressfile ]]; then
        ticks="$(<$__zunit_parallel_progressfile)"
        completed=${#ticks}
        passed=${#${ticks//[^.]/}}
        # Errors and failures are both failed tests as far as the
        # exit code is concerned, so the tally counts them together
        failed=${#${ticks//[^FE]/}}
    fi

    # Measure the terminal whenever a worker has reported something
    # new, because that is what is about to be put on the screen, and
    # a bar drawn to a width the window has already moved away from
    # wraps. Every tenth poll is measured as well, roughly once a
    # second, to catch a resize which the handler never saw - a
    # runner in the background is sent no SIGWINCH at all
    (( __zunit_parallel_progress_poll = (__zunit_parallel_progress_poll + 1) % 10 ))
    if [[ "$ticks" != "$__zunit_parallel_progress_seen" ]] \
        || (( ! __zunit_parallel_progress_poll )); then
        typeset -g __zunit_parallel_progress_seen="$ticks"
        _zunit_parallel_progress_columns
    fi
    columns=$__zunit_parallel_progress_cols

    # The total is only an estimate, so a run which turns out to be
    # longer than expected pushes the bar along, rather than
    # overflowing it
    (( completed > __zunit_parallel_progress_total )) \
        && __zunit_parallel_progress_total=$completed

    suffix="] ${completed}/${__zunit_parallel_progress_total}  ${passed} passed  ${failed} failed"

    # Shrink the bar to fit the terminal, leaving the last column
    # free - a line which wraps cannot be erased with a single
    # escape sequence
    (( columns > 0 && width + ${#suffix} + 1 >= columns )) \
        && width=$(( columns - ${#suffix} - 2 ))

    if (( width < 4 )); then
        # There is no room for a bar worth drawing, and the counts
        # are worth more than four characters of one, so the bar is
        # dropped rather than squeezed
        line="${suffix#\] }"
    else
        (( __zunit_parallel_progress_total > 0 )) \
            && filled=$(( width * completed / __zunit_parallel_progress_total ))
        (( filled > width )) && filled=$width

        bar="${(l:$filled::#:):-}${(l:$(( width - filled ))::-:):-}"
        line="[${bar}${suffix}"
    fi

    # The last resort. Whatever the width was measured as, the line
    # is never allowed to reach the final column of the terminal
    (( columns > 0 && ${#line} >= columns )) && line="${line[1,columns-1]}"

    # Redrawing a bar which has not changed only adds noise to
    # scrollback and to captured output
    [[ "$line" == "$__zunit_parallel_progress_last" ]] && return 0
    typeset -g __zunit_parallel_progress_last="$line"

    print -nu2 -- $'\r\e[K'"$line"

    return 0
} # ]]]
# FUNCTION: _zunit_parallel_progress_init [[[
# Work out whether a progress bar can be drawn, and estimate the
# number of tests which the run will execute
function _zunit_parallel_progress_init() {
    local file

    # These are deliberately global. The EXIT trap which erases the
    # bar runs after the locals of _zunit_parallel_run have already
    # been popped, so it cannot see them otherwise
    typeset -g __zunit_parallel_progress=''
    typeset -g __zunit_parallel_progress_total=0
    typeset -g __zunit_parallel_progress_last=''
    typeset -g __zunit_parallel_progress_seen=''
    typeset -g __zunit_parallel_progress_stty=''
    typeset -gi __zunit_parallel_progress_poll=0

    # The bar is a terminal affordance. It is skipped when stderr is
    # not a terminal, so that piped output and report files stay
    # byte for byte identical to a serial run, and when TAP output
    # has been requested, since that is a machine readable format
    [[ -t 2 && -z $tap && -z $no_progress ]] || return 0

    for file in "$@"; do
        if [[ -n ${${(s/@/)file}[2]} ]]; then
            # Only a single named test will run from this file
            (( __zunit_parallel_progress_total++ ))
        else
            (( __zunit_parallel_progress_total += \
                $(_zunit_parallel_count_tests "${${(s/@/)file}[1]}") ))
        fi
    done

    (( __zunit_parallel_progress_total > 0 )) || return 0

    __zunit_parallel_progress=1
    : >| "$__zunit_parallel_progressfile"

    _zunit_parallel_progress_columns

    # Keep the bar on a line of its own. With echo left on, a newline
    # typed while the run is in progress scrolls the bar up the
    # screen, and every redraw which follows lands on a new line,
    # leaving a stack of stale bars behind. The mode is restored by
    # _zunit_parallel_progress_clear, which the EXIT trap reaches
    # even when the run is interrupted
    trap '' TTOU
    __zunit_parallel_progress_stty="$(stty -g <&2 2>/dev/null)"
    [[ -n $__zunit_parallel_progress_stty ]] && stty -echo <&2 2>/dev/null
    trap - TTOU

    # Follow the window for as long as the bar is being drawn
    trap '_zunit_parallel_progress_columns; _zunit_parallel_progress_draw' WINCH

    # Hide the cursor rather than leave it blinking at the end of the bar
    print -nu2 -- $'\e[?25l'

    _zunit_parallel_progress_draw
} # ]]]
# FUNCTION: _zunit_parallel_record [[[
# Record a result event, preserving the current test name
# and test count at the time of the event. Each field is quoted
# before joining so payloads containing the separator byte survive
function _zunit_parallel_record() {
    local tick
    local -a fields
    fields=("$1" "$name" "$total" "${(@)@:2}")

    __zunit_parallel_events+=("${(pj:\x1f:)${(@q+)fields}}")

    # Append a single character per completed test to the shared
    # progress file, so that the parent can count results while the
    # workers are still running. Single byte appends are atomic, so
    # the workers need no locking between them. Verbose output is
    # not a test result, so it does not get a tick
    case "$1" in
        success ) tick='.' ;;
        failure ) tick='F' ;;
        error )   tick='E' ;;
        skip )    tick='S' ;;
        warn )    tick='W' ;;
    esac

    [[ -n $tick && -n $__zunit_parallel_progress ]] \
        && print -n -- "$tick" >> "$__zunit_parallel_progressfile"

    return 0
} # ]]]
# FUNCTION: _zunit_parallel_replay [[[
# Replay a worker's recorded events through the real event handlers
function _zunit_parallel_replay() {
    local statefile="$1.state" event
    local -a __zunit_parallel_events fields
    integer __zunit_parallel_total=0
    integer __zunit_parallel_done=0
    integer __zunit_parallel_base=$total

    [[ -f $statefile ]] && source "$statefile" 2>/dev/null

    if (( ! __zunit_parallel_done )); then
        # The worker died before it could report its results. Count
        # it as a single errored test so totals, TAP numbering and
        # the exit code all reflect the crash
        name='parallel worker'
        total=$(( __zunit_parallel_base + 1 ))
        _zunit_error 'Parallel worker exited unexpectedly' "$(cat "$1.log" 2>/dev/null)"
        return 1
    fi

    for event in "${__zunit_parallel_events[@]}"; do
        fields=("${(@Q)${(@ps:\x1f:)event}}")
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
    integer __zunit_parallel_k __zunit_parallel_slices
    local __zunit_parallel_file __zunit_parallel_prev
    local -a __zunit_parallel_ordered __zunit_parallel_args
    local -a __zunit_parallel_groups __zunit_parallel_ngroups
    local -a __zunit_parallel_pids __zunit_parallel_spawned

    __zunit_parallel_ordered=(${(o)testfiles})
    (( ${#__zunit_parallel_ordered} > 0 )) || return 0

    local __zunit_parallel_tmpdir
    __zunit_parallel_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/zunit-parallel.XXXXXXXX")"
    if [[ $? -ne 0 || ! -d $__zunit_parallel_tmpdir ]]; then
        echo $(color red 'Failed to create a temporary directory for the parallel run') >&2
        exit 1
    fi

    typeset -g __zunit_parallel_progressfile="$__zunit_parallel_tmpdir/progress"

    # Clean the temporary directory up on exit, and make fatal
    # signals exit the shell so the EXIT trap still runs. Erasing
    # the bar leaves the cursor on a clean line when a run is
    # interrupted or shut down early by --fail-fast.
    #
    # The order matters: a `return` inside a function called from a
    # trap returns from the trap itself, abandoning everything after
    # it, so the cleanup has to come before the call
    trap "rm -rf ${(q)__zunit_parallel_tmpdir}; _zunit_parallel_progress_clear" EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    # Build the list of work units. Each unit is either a whole test
    # file, or a contiguous slice of the tests in a single file, with
    # no more slices than the file has tests
    if (( ${#__zunit_parallel_ordered} == 1 )); then
        __zunit_parallel_slices=$(_zunit_parallel_count_tests "${${(s/@/)__zunit_parallel_ordered[1]}[1]}")
        (( __zunit_parallel_slices > __zunit_parallel_max )) && __zunit_parallel_slices=$__zunit_parallel_max

        for (( __zunit_parallel_k=1; __zunit_parallel_k <= __zunit_parallel_slices; __zunit_parallel_k++ )); do
            __zunit_parallel_args+=("${__zunit_parallel_ordered[1]}")
            __zunit_parallel_groups+=($__zunit_parallel_k)
            __zunit_parallel_ngroups+=($__zunit_parallel_slices)
        done
    else
        for __zunit_parallel_file in "${__zunit_parallel_ordered[@]}"; do
            __zunit_parallel_args+=("$__zunit_parallel_file")
            __zunit_parallel_groups+=(0)
            __zunit_parallel_ngroups+=(0)
        done
    fi

    _zunit_parallel_progress_init "${__zunit_parallel_ordered[@]}"

    # Spawn a worker subshell per unit, never running more
    # than $__zunit_parallel_max workers at once
    for (( __zunit_parallel_k=1; __zunit_parallel_k <= ${#__zunit_parallel_args}; __zunit_parallel_k++ )); do
        # Once a worker has failed under --fail-fast there is no
        # point starting any further work
        [[ -n $fail_fast && -f "$__zunit_parallel_tmpdir/abort" ]] && break

        _zunit_parallel_wait_slot $__zunit_parallel_max
        (
            _zunit_parallel_child_init "$__zunit_parallel_tmpdir/$__zunit_parallel_k"

            # Each worker builds its own environment from the
            # bootstrap script, so nothing the script creates is
            # shared between workers. It is sourced right here rather
            # than inside one of the helper functions, because source
            # runs the script in the enclosing function scope - a
            # variable the script declares with a bare typeset would
            # become a local of that helper, gone before the tests run
            if [[ -n $__zunit_parallel_bootstrap ]] && \
                ! source "$__zunit_parallel_bootstrap"; then
                name='bootstrap'
                _zunit_error "Failed to source bootstrap script $__zunit_parallel_bootstrap" \
                    "$(cat "${__zunit_parallel_statefile%.state}.log" 2>/dev/null)"
                _zunit_parallel_child_finish
                exit 1
            fi

            _zunit_run_testfile "${__zunit_parallel_args[$__zunit_parallel_k]}" \
                "${__zunit_parallel_groups[$__zunit_parallel_k]}" \
                "${__zunit_parallel_ngroups[$__zunit_parallel_k]}"
            _zunit_parallel_child_finish
        ) > "$__zunit_parallel_tmpdir/$__zunit_parallel_k.log" 2>&1 &
        __zunit_parallel_pids+=($!)
        __zunit_parallel_spawned+=($!)

        _zunit_parallel_progress_draw
    done

    # While a bar is being drawn, wait by polling so that it keeps
    # moving. Without one there is nothing to redraw, so the shell
    # blocks in wait instead of waking up ten times a second
    [[ -n $__zunit_parallel_progress ]] && _zunit_parallel_wait_slot 1

    # Wait for the tracked workers only - a bare wait would also
    # block on any background process left behind by a bootstrap
    # script sourced into this shell
    (( ${#__zunit_parallel_spawned} )) && wait "${__zunit_parallel_spawned[@]}"

    # Results are printed from here on, so the bar has to go
    _zunit_parallel_progress_clear

    # Replay each worker's recorded events, in the order a serial
    # run would have produced them. Under --fail-fast the replay of
    # the first failure exits before any unspawned unit is reached
    __zunit_parallel_prev=''
    for (( __zunit_parallel_k=1; __zunit_parallel_k <= ${#__zunit_parallel_args}; __zunit_parallel_k++ )); do
        __zunit_parallel_file="${${(s/@/)__zunit_parallel_args[$__zunit_parallel_k]}[1]}"

        # Print the file header once per file - workers suppress theirs
        if [[ "$__zunit_parallel_file" != "$__zunit_parallel_prev" ]] || (( ${__zunit_parallel_groups[$__zunit_parallel_k]} == 0 )); then
            _zunit_testfile_header "$__zunit_parallel_file"
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

    zmodload zsh/parameter 2>/dev/null
    zmodload zsh/zselect 2>/dev/null

    while (( ${#__zunit_parallel_pids} >= max_procs )); do
        alive=()
        for pid in "${__zunit_parallel_pids[@]}"; do
            # Check the shell's own job table rather than kill -0,
            # which can be fooled by a recycled PID
            if [[ -n ${(M)${(v)jobstates}:#running:*:${pid}=*} ]]; then
                alive+=($pid)
            fi
        done
        __zunit_parallel_pids=($alive)

        if (( ${#__zunit_parallel_pids} >= max_procs )); then
            _zunit_parallel_progress_draw

            if (( $+builtins[zselect] )); then
                zselect -t 10 2>/dev/null
            else
                sleep 0.1
            fi
        fi
    done

    return 0
} # ]]]

# vim: ft=zsh sw=4 ts=4 et foldmarker=[[[,]]] foldmethod=marker
