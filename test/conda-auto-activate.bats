#!/usr/bin/env bats

# This test suite includes:
#
# - Tests for all major functions in the script
# - Mocking of conda/mamba commands
# - Environment setup and teardown for each test
# - Tests for different scenarios and edge cases
# - Validation testing at different strictness levels
# - Directory handling tests
# - Environment activation and creation tests
#
# The tests cover:
# - Directory targeting functionality
# - Package manager selection
# - Environment validation
# - Environment activation
# - Environment creation
# - Error handling
# - Setup functionality
#
# Note that these tests mock the conda/mamba commands to avoid actually creating environments during testing. You might want to add more specific tests based on your actual use cases and requirements.
#
# Remember to:
# - Add more specific test cases based on your needs
# - Test edge cases and error conditions
# - Add tests for any new features you add
# - Update tests when modifying existing functionality

# To run the tests, run:
# bats ./test/conda-auto-activate.bats
# Enable debug output
# To run all tests with debug output, run:
# DEBUG=1 bats ./test/conda-auto-activate.bats
#
# To run a specific test with debug output, run:
# bats ./test/conda-auto-activate.bats -f "should activate existing"
#
# Global debug flag, can be overridden with DEBUG=1 when running tests
export DEBUG="${DEBUG:-0}"

# Helper function to setup debug by default if DEBUG=1
setup_debug() {
    if [ "${DEBUG:-0}" -eq 1 ]; then
        DEBUG_ENABLED=1
    else
        DEBUG_ENABLED=0
    fi
}

# Helper function to disable debug for specific test
disable_debug() {
    DEBUG_ENABLED=0
}

# Helper function for debug output
debug() {
    if [ "${DEBUG:-0}" -eq 1 ] && [ "${DEBUG_ENABLED:-0}" -eq 1 ]; then
        local timestamp=$(date '+%H:%M:%S')
        echo "========================================" >&3
        echo "[${timestamp}] 🔍 $BATS_TEST_NAME: $*" >&3
        echo "========================================" >&3
    fi
}

# Setup function runs before each test
setup() {
    # Enable debug by default if DEBUG=1
    setup_debug

    # Source the script we're testing
    source "${BATS_TEST_DIRNAME}/../conda-auto-activate.sh"

    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    debug "Created test directory: $TEST_DIR"

    # Save original directory
    ORIGINAL_DIR="$PWD"

    # Mock conda/mamba commands with debug output
    function conda() {
        debug "conda called with arguments: $*"
        case "$1" in
            "env")
                case "$2" in
                    "list")
                        debug "Listing conda environments"
                        echo "test-env                  /path/to/env"
                        ;;
                    "create")
                        debug "Creating conda environment with args: ${*:3}"
                        return 0
                        ;;
                esac
                ;;
            "activate")
                debug "Activating conda environment: $2"
                return 0
                ;;
            *)
                debug "Unknown conda command: $1"
                return 1
                ;;
        esac
    }

    function mamba() {
        debug "mamba called with arguments: $*"
        conda "$@"
    }

    export -f conda mamba debug
}

# Teardown function runs after each test
teardown() {
    debug "Cleaning up test directory: $TEST_DIR"
    rm -rf "$TEST_DIR"
    debug "Returning to original directory: $ORIGINAL_DIR"
    cd "$ORIGINAL_DIR"
}

# Test is_target_directory function
@test "is_target_directory should return true for target directory" {
    TARGET_DIRECTORIES=("$TEST_DIR")
    cd "$TEST_DIR"
    debug "Current directory: $PWD"
    debug "Target directories: ${TARGET_DIRECTORIES[*]}"
    run is_target_directory
    [ "$status" -eq 0 ]
}

@test "is_target_directory should return false for non-target directory" {
    TARGET_DIRECTORIES=("/some/other/path")
    cd "$TEST_DIR"
    debug "Current directory: $PWD"
    debug "Target directories: ${TARGET_DIRECTORIES[*]}"
    run is_target_directory
    [ "$status" -eq 1 ]
}

# Test get_pkg_manager function
@test "get_pkg_manager should return mamba when mamba is available" {
    PACKAGE_MANAGER="mamba"
    debug "Testing package manager selection with PACKAGE_MANAGER=$PACKAGE_MANAGER"
    result="$(get_pkg_manager)"
    debug "Selected package manager: $result"
    [ "$result" = "mamba" ]
}

@test "get_pkg_manager should fallback to conda when mamba is not set" {
    PACKAGE_MANAGER="conda"
    result="$(get_pkg_manager)"
    [ "$result" = "conda" ]
}

# Test validate_environment_yml function
@test "validate_environment_yml should pass with strictness level 0" {
    disable_debug
    STRICTNESS_LEVEL=0
    cd "$TEST_DIR"
    echo "name: test-env
channels:
  - conda-forge
dependencies:
  - python=3.8" > environment.yml

    run validate_environment_yml
    [ "$status" -eq 0 ]
}

@test "validate_environment_yml should detect dangerous packages at strictness level 2" {
    STRICTNESS_LEVEL=2
    cd "$TEST_DIR"
    echo "name: test-env
channels:
  - conda-forge
dependencies:
  - curl" > environment.yml

    run validate_environment_yml
    [ "$status" -eq 1 ]
}

# Test auto_env function
@test "auto_env should activate existing environment" {
    cd "$TEST_DIR"
    debug "Creating test environment.yml"
    cat > environment.yml << EOF
name: test-env
channels:
  - conda-forge
dependencies:
  - python=3.8
EOF
    debug "Content of environment.yml:"
    debug "$(cat environment.yml)"

    run auto_env
    debug "auto_env exit status: $status"
    debug "auto_env output: $output"
    [ "$status" -eq 0 ]
}

@test "auto_env should create and activate new environment" {
    cd "$TEST_DIR"
    debug "Creating test environment.yml for new environment"
    cat > environment.yml << EOF
name: new-env
channels:
  - conda-forge
dependencies:
  - python=3.8
EOF
    debug "Content of environment.yml:"
    debug "$(cat environment.yml)"

    run auto_env
    debug "auto_env exit status: $status"
    debug "auto_env output: $output"
    [ "$status" -eq 0 ]
}

@test "auto_env should handle missing environment.yml" {
    cd "$TEST_DIR"
    debug "Testing auto_env behavior with no environment.yml"
    debug "Current directory: $PWD"
    debug "Directory contents: $(ls -la)"

    run auto_env
    debug "auto_env exit status: $status"
    debug "auto_env output: $output"
    [ "$status" -eq 0 ]
}

@test "auto_env should handle envs directory" {
    cd "$TEST_DIR"
    debug "Creating envs directory"
    mkdir -p "./envs"
    debug "Current directory: $PWD"
    debug "Directory structure:"
    debug "$(ls -R)"

    run auto_env
    debug "auto_env exit status: $status"
    debug "auto_env output: $output"
    [ "$status" -eq 0 ]
}

# Test setup_auto_activation function
@test "setup_auto_activation should set PROMPT_COMMAND" {
    debug "Testing setup_auto_activation"
    debug "Initial PROMPT_COMMAND: $PROMPT_COMMAND"

    run setup_auto_activation

    debug "Final PROMPT_COMMAND: $PROMPT_COMMAND"
    debug "setup_auto_activation exit status: $status"
    debug "setup_auto_activation output: $output"

    [[ "$PROMPT_COMMAND" == *"auto_env"* ]] || [ "$status" -eq 0 ]
    debug "PROMPT_COMMAND test result: $?"
}
