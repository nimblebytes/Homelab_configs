#!/bin/sh

## =============================================================================
## Script Name: install_host_git_project.sh
## Description: Script to install Git and the host projects in the git repo
##  - Repo package updates and upgrades
##  - Install Git
##  - Install host project from the Git repo
##
## Author: nimblebytes (GitHub)
## =============================================================================

#set -x  # Enable script debugging

## Script variables - default values
HOSTNAME=${HOSTNAME}
REPO_ORG=nimblebytes
REPO_PROJECT=Homelab_configs
REPO_BRANCH=master
REPO_STR=""
REPO_STR_RAW=""

## Load variables from local environment
CONFIG_FILE="${CONFIG_FILE:-}"
LOG_FILE="${LOG_FILE:-}"
LOGGER_FILE="${LOGGER_FILE:-}"

PROJECT_FOLDER="/opt/git"
SUDO=""
REAL_USER=${SUDO_USER:-$(id -un)}
REAL_GROUP=$(id -gn "$REAL_USER")

## =============================================================================
## Fallback Logging
## These simple stubs are active until better_logs.sh is sourced.
## Once sourced, its definitions silently replace these.
## =============================================================================
log_debug()   { printf '[DEBUG] %s\n' "$*"; }
log_info()    { printf '[INFO]  %s\n' "$*"; }
log_step()    { printf '[STEP]  %s\n' "$*"; }
log_ok()      { printf '[OK]    %s\n' "$*"; }
log_warn()    { printf '[WARN]  %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }
log_banner()  { printf '=== %s ===\n' "$*"; }
log_divider() { printf '%s\n' '---------------------------------------------'; }



create_repo_string(){
  REPO_STR="https://github.com/${REPO_ORG}/${REPO_PROJECT}.git"
  REPO_STR_RAW="https://raw.githubusercontent.com/${REPO_ORG}/${REPO_PROJECT}/refs/heads/${REPO_BRANCH}"
}

install_git(){
  ## Check if required privileges 
  if ! detect_root_sudo; then
    log_error "Root or sudo privileges are needed for this script."
    return 1
  fi

  # Update package lists silently
  if ! $SUDO apt update -y >/dev/null 2>&1; then
    log_error "apt update failed."
    return 1
  fi

  # Install git silently
  if ! $SUDO apt install -y git >/dev/null 2>&1; then
    log_error "git installation failed."
    return 1
  fi

  # Verify git is available
  if ! command -v git >/dev/null 2>&1; then
    log_error "git installed but not found in PATH."
    return 1
  fi

  log_ok "git installed successfully."
  return 0
}

## Detect sudo requirement
detect_root_sudo(){
  ## Get the UID of the user, to check if running as root
  UID_RESULT=`id -u 2>/dev/null`
  if [ "$UID_RESULT" = "0" ]; then
    SUDO=""
  ## Check if the 'sudo' command exists
  elif command -v sudo >/dev/null 2>&1; then
    if sudo -n true >/dev/null 2>&1; then
      SUDO="sudo"
    else
      log_error "sudo available but user lacks privileges or password is required."
    fi
  else
    return 1
  fi
  return 0
}

## Load config setting and overrides, if the files exists
load_config(){
  if [ -f "${CONFIG_FILE:-}" ]; then 
    . $CONFIG_FILE
  fi

  if [ -f "$PWD/override.config" ]; then
    . $PWD/override.config
    log_info "Config override file loaded: $PWD/override.config"
  elif [ -f "$WORK_DIR/override.config" ]; then
    log_info "Config override file loaded: $WORK_DIR/override.config"
  fi
}

## =============================================================================
## Load an external Logger helper
## Sources better_logs.sh if available. Falls back silently to the stubs above.
## =============================================================================
load_logger(){

  if [ -f "${LOGGER_FILE:-}" ]; then 
    log_info "Attempting to load logger: ${LOGGER_FILE}..."
    . $LOGGER_FILE
    if log_file_init; then 
      log_ok "Logger: ${LOGGER_FILE} loaded successfully."
    else
      log_warn "Logger: ${LOGGER_FILE} loaded, but the log file failed to initialize. Logging to file is disabled.\n"
    fi
  fi
}

pull_git_project(){
  create_repo_string

  ## Create the project folder if it does not exist
  if [ ! -e ${PROJECT_FOLDER} ]; then
    mkdir -r "${PROJECT_FOLDER}"
    git clone --no-checkout ${REPO_STR} ${PROJECT_FOLDER}     ## Clone the Repo to the project folder
    cd ${PROJECT_FOLDER}
    git sparse-checkout init --cone                                   ## Initialise a sparse checkout
    git sparse-checkout set ${HOSTNAME}                           ## Checkout only folders with host name
    git checkout ${REPO_BRANCH}                                   ## Checkout the required branch
  else
    cd ${PROJECT_FOLDER}
  fi
}

pull_git_project_temp(){
  create_repo_string
  
  ## Create the project folder if it does not exist
  if [ ! -e "$PROJECT_FOLDER" ]; then
    "$SUDO" mkdir -p "$PROJECT_FOLDER"
    "$SUDO" chown "$REAL_USER:$REAL_GROUP" "$PROJECT_FOLDER"
  fi
  git clone --no-checkout ${REPO_STR} ${PROJECT_FOLDER}
  cd ${PROJECT_FOLDER}
  git sparse-checkout init --cone 
  git sparse-checkout set ${HOSTNAME} 
  git checkout ${REPO_BRANCH}                                   ## Checkout the required branch
}

## =============================================================================
## Usage
## =============================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Bootstrap a new Linux VM by selecting tools via a dialog interface.
Each selected tool is installed by a dedicated script downloaded from
the configured repository.

Options:
  --config <url>      (Optional) Path to config file that set script settings 
                        Warning: if "override.config" is present in the base 
                        path, it takes preference and overrides any settings
  --log-file <file>   Path to the log file
                        Default: $LOG_FILE
  --help              Show this help message and exit

EOF
}

## =============================================================================
## Parameter Parsing
## Supports long flags only. Both "--flag value" and "--flag=value" are accepted.
## =============================================================================
parse_args() {
  while [ $# -gt 0 ]; do
    ## Split --flag=value into flag and value for uniform handling
    case "$1" in
      --*=*)
        FLAG="${1%%=*}"
        VALUE="${1#*=}"
        ;;
      *)
        FLAG="$1"
        VALUE=""
        ;;
    esac

    case "$FLAG" in
      --config)
        if [ -z "$VALUE" ]; then
          VALUE="$2"
          shift
        fi
        CONFIG_FILE="$VALUE"
        ;;
      --log-file)
        if [ -z "$VALUE" ]; then
          VALUE="$2"
          shift
        fi
        LOG_FILE="$VALUE"
        ;;
      --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      --*)
        log_error "Unknown option: $FLAG"
        usage
        exit 1
        ;;
      *)
        log_error "Unexpected argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

## =============================================================================
## Main
## =============================================================================
main(){
  parse_args "$@"
  load_logger
  load_config
  log_step "Installing git..."
  #install_git
  echo "Downloading host project..."
  log_step "Downloading host project..."
  pull_git_project_temp
}

## Temporary override
HOSTNAME="docktopia"
main "$@"