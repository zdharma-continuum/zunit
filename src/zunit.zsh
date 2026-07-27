#!/usr/bin/env zsh

setopt extendedglob typesetsilent

######################
# Main zunit process #
######################

# FUNCTION: _zunit_usage [[[
# Output usage information and exit
function _zunit_usage() {
    echo "$(color yellow 'Usage:')"
    echo "  zunit [options] [command] [tests...]"
    echo
    echo "$(color yellow 'Commands:')"
    echo "  init               Bootstrap zunit in a new project"
    echo "  run [tests...]     Run tests"
    echo
    echo "$(color yellow 'Options:')"
    echo "  -h, --help         Output help text and exit"
    echo "  -f, --fail-fast    Stop the test runner immediately after the first failure"
    echo "  -p, --parallel     Run tests in parallel across CPU cores"
    echo "  -r, --revolver     Run tests with revolver spinner"
    echo "  -t, --tap          Output results in a TAP compatible format"
    echo "  -v, --version      Output version information and exit"
    echo "      --allow-risky  Supress warnings generated for risky tests"
    echo "      --no-progress  Disable the progress bar during parallel runs"
    echo "      --output-html  Print results to a HTML page"
    echo "      --output-text  Print results to a text log, in TAP compatible format"
    echo "      --slice        Split a single test file's tests across workers"
    echo "      --time-limit   Set a time limit in seconds for each test"
    echo "      --verbose      Prints full output from each test"
} # ]]]
# FUNCTION: _zunit_version [[[
# Output the version number
function _zunit_version() {
    echo '0.15.0'
} # ]]]
# FUNCTION: _zunit [[[
# The main zunit process
function _zunit() {
    local help version ctx missing_dependencies=0 missing_config=1
    if [[ -f .zunit.yml ]]; then
        # Try and parse the config file within a subprocess,
        # to avoid killing the main thread
        $(eval $(_zunit_parse_yaml .zunit.yml 'zunit_config_') >/dev/null 2>&1)
        if [[ $? -eq 0 ]]; then
            # The config file was parsed successfully, so we Perform the parse
            # again, but this time on the main thread so that the config vars are
            # loaded into the enviroment
            eval $(_zunit_parse_yaml .zunit.yml 'zunit_config_') >/dev/null 2>&1
            missing_config=0
        else
            # The config file failed to parse, so we report this to the user and exit
            print -P "%F{red}[ERROR]%f: %F{white}Unable to parse configuration file%f" >&2
            exit 1
        fi
    fi

    zparseopts -D -E \
        h=help -help=help \
        v=version -version=version

    # If the version option is passed,
    # output version information and exit
    if [[ -n $version ]]; then
        _zunit_version && exit 0
    fi

    # An option which belongs to a command may be written before it, so
    # the command is the first word which is neither an option nor the
    # value of one. The scan runs on what is left once the options above
    # have been removed, so that the position it finds is a position in
    # the list the command is handed. '--time-limit' is the only option
    # whose value is a separate word, and zparseopts reads whatever
    # follows it as that value, so the scan skips it too
    local -a args=("$@")
    local -i i pos=0
    for (( i = 1; i <= $#args; i++ )); do
        case "$args[i]" in
            --time-limit ) i=$(( i + 1 )) ;;
            -* ) ;;
            * ) ctx="$args[i]"; pos=i; break ;;
        esac
    done

    # Check which command has been passed, and run it. If the command
    # is not recognised, then we'll assume it's a test file and pass
    # it to `zunit run`, since that will catch it if it's not a valid
    # file. The command is removed by position, so that an option
    # written before it is still passed along with the rest
    case "$ctx" in
        init )
            # If the help option is passed,
            # output usage information and exit
            if [[ -n $help ]]; then
                _zunit_init_usage && exit 0
            fi
            _zunit_init "${(@)args[1,pos-1]}" "${(@)args[pos+1,-1]}"
            ;;
        run )
            # If the help option is passed,
            # output usage information and exit
            if [[ -n $help ]]; then
                _zunit_run_usage && exit 0
            fi
            _zunit_run "${(@)args[1,pos-1]}" "${(@)args[pos+1,-1]}"
            ;;
        * )
            # If the help option is passed,
            # output usage information and exit
            if [[ -n $help ]]; then
                _zunit_usage && exit 0
            fi
            _zunit_run "$@"
            ;;
    esac
} # ]]]

_zunit "$@"

# vim: ft=zsh sw=4 ts=4 et foldmarker=[[[,]]] foldmethod=marker
