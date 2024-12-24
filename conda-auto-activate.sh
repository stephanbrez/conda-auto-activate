#!/usr/bin/env bash

# conda-auto-activate automatically activates a conda environment when
# entering a folder with an environment.yml file or /envs/ folder
#
# If the environment doesn't exist, conda-auto-activate creates and
# activates it for you.
# 
# Based on https://github.com/chdoig/conda-auto-env
#
# To install, add this line to your .bashrc or .bash-profile:
#
#       source /path/to/conda-auto-activate.sh
#

# ********** User settings ********** #

# List of directories to check for environment.yml and its children
# Modify this to the directories you want to trigger the environment activation in
if [ -z "$TARGET_DIRECTORIES" ]; then
  TARGET_DIRECTORIES=(
    "/path/to/dir1"
    "/path/to/dir2"
    "/path/to/dir3"
  )
fi

# Strictness level for validation:
# 0 = Skip validation
# 1 = Run basic validation (yamllint, external commands check)
# 2 = Run full validation (yamllint, dangerous packages, untrusted channels, external commands)
STRICTNESS_LEVEL=1  

# ********** Full validation settings ********** #
# Example dangerous packages
DANGEROUS_PACKAGES=("curl" "wget" "bash" "sh" "python-pip" "git")

# Example trusted channels
TRUSTED_CHANNELS=("conda-forge" "defaults")

# ********** End user settings ********** #

# Function to check if the current directory is in one of the target directories or its subdirectories
function is_target_directory() {
  current_dir=$(pwd)
  for target_dir in "${TARGET_DIRECTORIES[@]}"; do
    if [[ "$current_dir" == *"$target_dir"* ]]; then
      return 0  # True, the current directory or its parent is one of the target directories
    fi
  done
  return 1  # False, not in any of the target directories or their subdirectories
}

# Function to validate the environment.yml file based on the STRICTNESS_LEVEL
function validate_environment_yml() {
  # If STRICTNESS_LEVEL is 0, skip all validation
  if [[ $STRICTNESS_LEVEL -eq 0 ]]; then
    echo "Validation skipped (STRICTNESS_LEVEL is 0)."
    return 0
  fi

  # LEVEL 1 and LEVEL 2 validation: Check for yamllint and external commands
  # Ensures LEVEL 2 includes validations from LEVEL 1
  if [[ $STRICTNESS_LEVEL -ge 1 ]]; then
    # Check if yamllint is installed
    if ! command -v yamllint &> /dev/null; then
      echo "Warning: 'yamllint' is not installed. YAML syntax validation will be skipped."
    else
      # Optionally use yamllint to validate syntax
      if ! yamllint environment.yml; then
        echo "Error: Invalid YAML syntax in environment.yml."
        exit 1
      fi
    fi

    # Check for external commands like 'curl', 'wget', 'bash', etc.
    if grep -E '(curl|wget|bash|sh|python|git)' environment.yml; then
      echo "Warning: External command invocation detected in environment.yml."
      echo "Potentially unsafe commands like 'curl', 'wget', or 'bash' found."
      exit 1
    fi
  fi

  # LEVEL 2 validation: Additional checks for dangerous packages and untrusted channels
  if [[ $STRICTNESS_LEVEL -ge 2 ]]; then
    # LEVEL 2 already includes LEVEL 1 validation due to structure

    # Check for dangerous packages
    for pkg in $(grep -E '^\s*- ' environment.yml | cut -d ' ' -f2); do
      for danger in "${DANGEROUS_PACKAGES[@]}"; do
        if [[ "$pkg" == "$danger" ]]; then
          echo "Warning: Dangerous package '$pkg' detected in environment.yml."
          exit 1
        fi
      done
    done

    # Check if channels are trusted
    for channel in $(grep "channel" environment.yml); do
      if [[ ! " ${TRUSTED_CHANNELS[@]} " =~ " ${channel} " ]]; then
        echo "Warning: Untrusted channel '$channel' detected in environment.yml."
        exit 1
      fi
    done
  fi

  echo "environment.yml is valid and safe."
}

# Function to automatically activate the conda environment or create it if necessary
function conda_auto_env() {
  # Only check if we are in a directory that matches one of the target directories
  if ! is_target_directory; then
    return 0  # Not in a target directory, skip further processing
  fi

  # Check if environment.yml exists and run validation only if it does
  if [ -e "environment.yml" ]; then
    # Run the validation function first
    validate_environment_yml || return 1

    # Extract the environment name by finding the first non-comment line with 'name:' and taking the value after it
    ENV=$(grep -m 1 '^[^#]*name:' environment.yml | awk '{print $2}')

    # Check if the environment is already active
    if [[ $PATH != *$ENV* ]]; then
      # Check if the environment exists
      if conda env list | grep -q "$ENV"; then
        # If the environment exists, activate it
        echo "Activating existing conda environment '$ENV'..."
        conda activate $ENV
      else
        # If the environment doesn't exist, create it and activate
        echo "Conda environment '$ENV' doesn't exist. Creating and activating..."
        conda env create -f environment.yml -q
        if [ $? -eq 0 ]; then
          conda activate $ENV
        else
          echo "Error: Failed to create conda environment '$ENV'."
          return 1
        fi
      fi
    fi
  elif [ -d "./envs" ]; then
    # If environment.yml is not present, check for an ./envs directory
    echo "Environment.yml not found, attempting to activate ./envs..."
    # If the ./envs directory exists, activate it
    conda activate ./envs
    if [ $? -ne 0 ]; then
      echo "Error: Failed to activate ./envs. Ensure it is a valid conda environment."
      return 1
    fi
  fi
}

# Checks if the shell is interactive and sets up the environment auto-activation.
if [[ $- =~ i ]]; then
  # Function to auto-activate environment when directory changes
  function auto_env_hook() {
    conda_auto_env
  }

  # Ensure auto_env_hook is included in the PROMPT_COMMAND for interactive shells
  if [[ $PROMPT_COMMAND != *"auto_env_hook"* ]]; then
    PROMPT_COMMAND="auto_env_hook; $PROMPT_COMMAND"
  fi

  # Call the function initially in case the script is sourced while already in a directory
  auto_env_hook
else
  conda_auto_env
fi