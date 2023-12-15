# vim: ft=zsh sw=4 ts=4 et foldmarker=[[[,]]] foldmethod=marker

###########################
# The 'zunit run' command #
###########################

# FUNCTION: _zunit_encode_test_name [[[
# Encode test name into a value which can be used as a hash key
function _zunit_encode_test_name() {
    echo "$1" | tr A-Z a-z \
        | tr _ ' ' \
        | tr - ' ' \
        | tr -s ' ' \
        | sed 's/\- /-/' \
        | sed 's/ \-/-/' \
        | tr ' ' "-"
} # ]]]
# FUNCTION: _zunit_execute_test [[[
# Execute a test and store the result
function _zunit_execute_test() {
    local name="$1" body="$2"
    if [[ -n $body ]] && [[ -n $name ]]; then
        # Update the progress indicator
        # Make sure we don't already have a function defined
        (( $+functions[__zunit_tmp_test_function] )) && unfunction __zunit_tmp_test_function
        # Create a wrapper function with our test body inside it
        func="function __zunit_tmp_test_function() {
            # Exit on errors. We do this so that execution stops immediately,
            # and the error will be reported back to the test runner
            setopt ERR_EXIT

            # Add an exit handler which calls the teardown function if it is
            # defined and the test exits early
            if (( \$+functions[__zunit_test_teardown] )); then
                zshexit() {
                    __zunit_test_teardown 2>&1
                }
            fi

            # Create some local variables to store test state in
            integer _zunit_assertion_count=0
            integer state
            local output
            typeset -a lines

            # If a setup function is defined, run it now
            if (( \$+functions[__zunit_test_setup] )); then
                __zunit_test_setup 2>&1
            fi

            # The test body is printed here, so when we eval the wrapper
            # function it will be read as part of the body of this function
            ${body}

            # If a teardown function is defined, run it now
            if (( \$+functions[__zunit_test_teardown] )); then
                __zunit_test_teardown 2>&1
            fi

            # Remove the error handler
            zshexit() {}

            # Check the assertion count, and if it is 0, return
            # the warning exit code
            [[ \$_zunit_assertion_count -gt 0 ]] || return 248
        }"

        # Increment the test count
        total=$(( total + 1 ))

        # Quietly eval the body into a variable as a first test
        output=$(eval "$(echo "$func")" 2>&1)

        # Check the status of the eval, and output any errors
        if [[ $? -ne 0 ]]; then
            _zunit_error "Failed to parse ${name} test body" $output
            return 126
        fi

        # Run the eval again, this time within the current context so that
        # the function is registered in the current scope
        eval "$(echo "$func")" 2>/dev/null

        # Any errors should have been caught above, but if the function
        # does not exist, we can't go any further
        if (( ! $+functions[__zunit_tmp_test_function] )); then
            _zunit_error "Failed to parse ${name} test body"
            return 126
        fi

        # Check if a time limit has been specified. We only do this if
        # the ZSH version is at least 5.1.0, since older versions of ZSH
        # are unable to handle asynchronous processes in the way we need
        autoload is-at-least
        if is-at-least 5.1.0 && [[ -n ${time_limit:#0} ]]; then
            # Create another wrapper function around the test
            __zunit_async_test_wrapper() {
                local pid
                # Get the current timestamp, and the time limit in ms, and use
                # those to work out the kill time for the sub process
                integer time_limit_ms=$(( time_limit * 1000 ))
                integer time=$(( EPOCHREALTIME * 1000 ))
                integer kill_time=$(( $time + $time_limit_ms ))
                # Launch the test function asynchronously and store its PID
                __zunit_tmp_test_function &
                pid=$!
                # While the child process is still running
                while kill -0 $pid >/dev/null 2>&1; do
                    # Check that the kill time has not yet been reached
                    time=$(( EPOCHREALTIME * 1000 ))
                    if [[ $time -gt $kill_time ]]; then
                        # The kill time has been reached, kill the child process,
                        # and exit the wrapper function
                        kill -9 $pid >/dev/null 2>&1
                        echo "${name} test exceeded time limit. Terminated after ${time_limit} seconds"
                        exit 78
                    fi
                done
                # Use wait to get the exit code from the background process,
                # and return that so that the test result can be deduced
                wait $pid
                return $?
            }

            # Launch the async wrapper, and capture the output in a variable
            output="$(__zunit_async_test_wrapper 2>&1)"
        else
            # Launch the test, and capture the output in a variable
            output="$(__zunit_tmp_test_function 2>&1)"
        fi

        # Output the result to the user
        state=$?
        if [[ $state -eq 48 ]]; then
            _zunit_skip $output
            return
        elif [[ $state -eq 78 ]]; then
            _zunit_error $output
            return
        elif [[ -z $allow_risky && $state -eq 248 ]]; then
            # If --verbose is specified, print test output to screen
            [[ -n $verbose && -n $output ]] && echo $output
            _zunit_warn 'No assertions were run, ${name} test considered risky'
            return
        elif [[ -n $allow_risky && $state -eq 248 ]] || [[ $state -eq 0 ]]; then
            # If --verbose is specified, print test output to screen
            [[ -n $verbose && -n $output ]] && echo $output
            _zunit_success
            return
        else
            _zunit_failure $output
            return 1
        fi
    fi
} # ]]]
# FUNCTION: _zunit_human_time [[[
# Format a ms timestamp in a human-readable format
function _zunit_human_time() {
    local tmp=$(( $1 / 1000 ))
    local days=$(( tmp / 60 / 60 / 24 ))
    local hours=$(( tmp / 60 / 60 % 24 ))
    local minutes=$(( tmp / 60 % 60 ))
    local seconds=$(( tmp % 60 ))
    local ms=$(( $1 % 1000 ))
    (( $days > 0 )) && print -n "${days}d "
    (( $hours > 0 )) && print -n "${hours}h "
    (( $minutes > 0 )) && print -n "${minutes}m "
    (( $seconds > 5 )) && print -n "${seconds}s "
    (( $seconds < 30 )) && (( $seconds > 5 )) && print -n "${ms}ms"
    (( $seconds <= 5 )) && print -n "${1}ms"
} # ]]]
# FUNCTION: _zunit_output_results [[[
# Output test results
function _zunit_output_results() {
    integer elapsed=$(( end_time - start_time ))
    echo
    echo "$total tests run in $(_zunit_human_time $elapsed)"
    echo
    print -Pr "%BResults%b"
    print -Pr "%F{green}Passed%f: ${#passed}/${total}"
    print -Pr "%F{red}Errors%f: ${#errors} $( (( $#errors )) && print "(${(j:, :)errors})" )"
    print -Pr "%F{red}Failed%f: ${#failed} $( (( $#failed )) && print "(${(j:, :)failed})" )"
    print -Pr "%F{yellow}Warnings%f: ${#warnings} $( (( $#warnings )) && print "(${(j:, :)warnings})" )"
    print -Pr "%F{white}Skipped%f: ${#skipped} $( (( $#skipped )) && print "(${(j:, :)skipped})" )"
    echo

    [[ -n $output_text ]] && echo "TAP report written at $PWD/$logfile_text"
    [[ -n $output_html ]] && echo "HTML report written at $PWD/$logfile_html"
} # ]]]
# FUNCTION: _zunit_parse_argument [[[
# Parse a list of arguments
function _zunit_parse_argument() {
    local -a bits; bits=("${(s/@/)1}")
    local argument="$bits[1]" test_name="$bits[2]"

    # If the argument begins with an underscore, then it
    # should not be run, so we skip it
    if [[ "${argument:0:1}" = "_" || "$(basename $argument | cut -c 1)" = "_" ]]; then
        return
    fi

    # If the argument is a directory
    if [[ -d $argument ]]; then
        # Loop through each of the files in the directory
        for file in $(find $argument -mindepth 1 -maxdepth 1); do
            # Skip further processing for files without a .zunit extension
            if [[ -f $file && $file != *.zunit ]]; then
                continue
            fi
            # Run it through the parser again
            _zunit_parse_argument $file
        done

        return
    fi

    # If it is a valid file
    if [[ -f $argument ]]; then
        # Grab the first line of the file
        line=$(cat $argument | head -n 1)

        # Check for the zunit shebang
        if [[ $line =~ "#! ?/usr/bin/env zunit" ]]; then
            # Add it to the array
            testfiles[(( ${#testfiles} + 1 ))]=("$argument${test_name+"@$test_name"}")
            return
        fi

        # The test file does not contain the zunit shebang, therefore
        # we can't trust that running it will not be harmful, and throw
        # a fatal error
        echo $(color red "File '$argument' is not a valid zunit test file") >&2
        echo "Test files must contain the following shebang on the first line" >&2
        echo "  #!/usr/bin/env zunit" >&2
        exit 126
    fi

    # The file could not be found, so we throw a fatal error
    echo $(color red "Test file or directory '$argument' could not be found") >&2
    exit 126
} # ]]]
# FUNCTION: _zunit_run [[[
# Run tests
function _zunit_run() {
    local -a arguments testfiles
    local fail_fast tap allow_risky verbose revolver
    local output_text logfile_text output_html logfile_html

    # Load the datetime module, and record the start time
    zmodload zsh/datetime
    local start_time=$((EPOCHREALTIME*1000)) end_time

    zparseopts -D -E \
        h=help -help=help \
        v=version -version=version \
        f=fail_fast -fail-fast=fail_fast \
        r=revolver -revolver=revolver \
        t=tap -tap=tap \
        -allow-risky=allow_risky \
        -output-html=output_html \
        -output-text=output_text \
        -time-limit:=time_limit \
        -verbose=verbose

    # TAP output is enabled
    if [[ -n $tap ]] || [[ "$zunit_config_tap" = "true" ]]; then
        # Set the $tap variable, so we can check it later
        tap=1

        # Print the TAP header
        echo '--- TAP version 13'
    fi

    # TAP output is disabled
    if [[ -z $tap ]]; then
        # Print version information
        echo $(color yellow 'Launching ZUnit')
        echo "ZUnit: $(_zunit_version)"
        echo "ZSH:   $(zsh --version)"
        echo
    fi

    # Text output has been requested
    if [[ -n $output_text || -n $output_html ]]; then
        # Make sure we have a config file, otherwise we can't determine
        # which directory to write logs to
        if [[ $missing_config -eq 1 ]]; then
            echo $(color red '.zunit.yml could not be found. Run `zulu init`')
            exit 1
        fi

        # If the output directory still isn't defined, it must not
        # be defined in the config file
        if [[ -z $zunit_config_directories_output ]]; then
            echo $(color red 'Output directory must be specified in .zunit.yml')
            exit 1
        fi
    fi

    if [[ -n $output_text ]]; then
        # Set the log filepath
        logfile_text="$zunit_config_directories_output/output.txt"

        # Print the header to the logfile
        echo 'TAP version 13' > $logfile_text
    fi

    if [[ -n $output_html ]]; then
        # Set the log filepath
        logfile_html="$zunit_config_directories_output/output.html"

        # Print the header to the logfile
        _zunit_html_header > $logfile_html
    fi

    if [[ -n $zunit_config_directories_support ]]; then
        # Check that the support directory exists
        local support="$zunit_config_directories_support"
        if [[ ! -d $support ]]; then
            echo $(color red "Support directory at $support is missing")
            exit 1
        fi

        # Look for a bootstrap script in the support directory,
        # and run it if it is available
        if [[ -f "$support/bootstrap" ]]; then
            source "$support/bootstrap"
            echo "$(color green '[SUCCESS]') Sourced bootstrap script $support/bootstrap"
        fi
    fi
    # Check if fail_fast is specified in the config or as an option
    if [[ -z $fail_fast ]] && [[ "$zunit_config_fail_fast" = "true" ]]; then
        fail_fast=1
    fi
    # Check if allow_risky is specified in the config or as an option
    if [[ -z $allow_risky ]] && [[ "$zunit_config_allow_risky" = "true" ]]; then
        allow_risky=1
    fi
    # Check if verbose is specified in the config or as an option
    if [[ -z $verbose ]] && [[ "$zunit_config_verbose" = "true" ]]; then
        verbose=1
    fi
    # Check if verbose is specified in the config or as an option
    if [[ -z $revolver ]] && [[ "$zunit_config_revolver" = "true" ]]; then
        # Check for the 'revolver' dependency
        $(type revolver >/dev/null 2>&1)
        if [[ $? -ne 0 ]]; then
            # 'revolver' could not be found, so print an error message
            print -P "%F{red}[ERROR]%f: %F{white}Missing required dependency%f: %F{cyan}Revolver%f - %F{cyan}https://github.com/molovo/revolver%f" >&2
            exit 1
        else
            revolver=1
        fi
    fi

    # Check if time_limit is specified in the config or as an option
    if [[ -n $time_limit ]]; then
        shift time_limit
    elif [[ -n $zunit_config_time_limit ]]; then
        time_limit=$zunit_config_time_limit
    fi

    arguments=("$@")
    testfiles=()

    # Start the progress indicator
    # If no arguments are passed, try to work out where the tests are
    if [[ ${#arguments} -eq 0 ]]; then
        # Check for a path defined in .zunit.yml
        if [[ -n $zunit_config_directories_tests ]]; then
            arguments=("$zunit_config_directories_tests")
            # Fall back to the directory 'tests' by default
        else
            arguments=("tests")
        fi
    fi
    # Loop through each of the passed arguments
    local argument
    for argument in $arguments; do
        # Parse the argument, so that we end up with a list of valid files
        _zunit_parse_argument $argument
    done
    # Loop through each of the test files and run them
    local line 
    local -i total
    local -a errors failed passed skipped warnings
    for testfile in ${(o)testfiles}; do
        _zunit_run_testfile $testfile
    done

    end_time=$((EPOCHREALTIME*1000))

    # Print report footers
    [[ -n $tap ]] && echo "1..$total"
    [[ -n $output_text ]] && echo "1..$total" >> $logfile_text
    [[ -n $output_html ]] && _zunit_html_footer >> $logfile_html

    # Output results to screen and kill the progress indicator
    _zunit_output_results

    # If the total of ($passed + $skipped) is not equal to the
    # total, then there must have been failures, errors or warnings,
    # in which case this assertion will return the correct exit code
    # for the test run as a whole
    [[ $(( $#passed + $#skipped )) -eq $total ]]
} # ]]]
# FUNCTION: _zunit_run_testfile [[[
# Run all tests within a file
function _zunit_run_testfile() {
    local testbody testname pattern \
        setup teardown
    local -a bits; bits=("${(s/@/)1}")
    local testfile="${bits[1]}" test_to_run="${bits[2]}" testdir="$(dirname "$testfile")"
    local -a lines tests test_names
    tests=()
    test_names=()

    # Update status message
    print -Pr "%F{blue}==>%f Loading tests from %B${testfile}%b"

    # A regex pattern to match test declarations
    pattern='^ *@test  *([^ ].*)  *\{ *(.*)$'

    # Loop through each of the lines in the file
    local oldIFS=$IFS
    IFS=$'\n' lines=($(cat $testfile))
    IFS=$oldIFS
    for line in $lines[@]; do
        # Match current line against pattern
        if [[ "$line" =~ $pattern ]]; then
            # Get test name from matches
            testname="${line[(( ${line[(i)[\']]}+1 )),(( ${line[(I)[\']]}-1 ))]}"

            # If a test name has been passed to the CLI, don't parse this test
            # unless it matches the name passed
            if [[ -n $test_to_run && $testname != $test_to_run ]]; then
                testname=''
                continue
            fi

            # Store the test name and body in the arrays so we have somewhere to
            # store the test body
            test_names=($test_names $testname)
            tests[${#test_names}]=''
        elif [[ "$line" =~ '^@setup([ ])?\{$' ]]; then
            setup=''
            parsing_setup=true
        elif [[ "$line" =~ '^@teardown([ ])?\{$' ]]; then
            teardown=''
            parsing_teardown=true
        elif [[ "$line" = '}' ]]; then
            # We've hit a closing brace as the only character on a line,
            # therefore we are at the end of either a test or a setup or teardown
            # function. We'll just clear all three here rather than work out which.
            testname=''
            parsing_setup=''
            parsing_teardown=''
        else
            # A test name is set, so we are parsing a test. Add the
            # current line to the function body.
            if [[ -n $testname ]]; then
                tests[${#test_names}]+="$line"$'\n'
                continue
            fi

            # Add the current line to the body of the setup function
            if [[ -n $parsing_setup ]]; then
                setup+="$line"$'\n'
                continue
            fi

            # Add the current line to the body of the teardown function
            if [[ -n $parsing_teardown ]]; then
                teardown+="$line"$'\n'
                continue
            fi
        fi
    done

    # A setup function has been defined
    if [[ -n $setup ]]; then
        # Print the body into a function declaration
        setupfunc="function __zunit_test_setup() {
            ${setup}
        }"

        # Quietly eval the body into a variable as a first test
        output=$(eval "$(echo "$setupfunc")" 2>&1)

        # Check the status of the eval, and output any errors
        if [[ $? -ne 0 ]]; then
            _zunit_error "Failed to parse setup method" $output

            return 126
        fi

        # Run the eval again, this time within the current context so that
        # the function is registered in the current scope
        eval "$(echo "$setupfunc")" 2>/dev/null

        # Any errors should have been caught above, but if the function
        # does not exist, we can't go any further
        if (( ! $+functions[__zunit_test_setup] )); then
            _zunit_error "Failed to parse setup method"

            return 126
        fi
    fi

    # A teardown function has been defined
    if [[ -n $teardown ]]; then
        # Print the body into a function declaration
        teardownfunc="function __zunit_test_teardown() {
            ${teardown}
        }"

        # Quietly eval the body into a variable as a first test
        output=$(eval "$(echo "$teardownfunc")" 2>&1)

        # Check the status of the eval, and output any errors
        if [[ $? -ne 0 ]]; then
            _zunit_error "Failed to parse teardown method" $output

            return 126
        fi

        # Run the eval again, this time within the current context so that
        # the function is registered in the current scope
        eval "$(echo "$teardownfunc")" 2>/dev/null

        # Any errors should have been caught above, but if the function
        # does not exist, we can't go any further
        if (( ! $+functions[__zunit_test_teardown] )); then
            _zunit_error "Failed to parse teardown method"

            return 126
        fi
    fi

    # Loop through each of the tests and execute it
    integer i=1
    local name body
    for name in "${test_names[@]}"; do
        body="${tests[$i]}"
        _zunit_execute_test "$name" "$body"
        i=$(( i + 1 ))
    done

    # Remove the temporary functions
    (( $+functions[__zunit_test_setup] )) && unfunction __zunit_test_setup
    (( $+functions[__zunit_test_teardown] )) && unfunction __zunit_test_teardown
    (( $+functions[__zunit_tmp_test_function] )) && unfunction __zunit_tmp_test_function
} # ]]]
# FUNCTION: _zunit_run_usage [[[
# Output usage information and exit
function _zunit_run_usage() {
    echo "$(color yellow 'Usage:')"
    echo "  zunit run [options] [tests...]"
    echo
    echo "$(color yellow 'Options:')"
    echo "  -h, --help             Output help text and exit"
    echo "  -f, --fail-fast        Stop the test runner immediately after the first failure"
    echo "  -r  --revolver         Run tests with revolver spinner"
    echo "  -t, --tap              Output results in a TAP compatible format"
    echo "  -v, --version          Output version information and exit"
    echo "      --allow-risky      Supress warnings generated for risky tests"
    echo "      --output-html      Print results to a HTML page"
    echo "      --output-text      Print results to a text log, in TAP compatible format"
    echo "      --time-limit <n>   Set a time limit of n seconds for each test"
    echo "      --verbose          Prints full output from each test"
} # ]]]
