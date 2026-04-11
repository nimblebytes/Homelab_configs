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
REPO_SERVER_PROJ=${HOSTNAME}            ## Which folder (system name) in the repository to use
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


## =============================================================================
## Create git repo and git raw strings
## Allows using a config file or override file to redefine the git repo to use
## =============================================================================
create_repo_string(){
  REPO_STR="https://github.com/${REPO_ORG}/${REPO_PROJECT}.git"
  REPO_STR_RAW="https://raw.githubusercontent.com/${REPO_ORG}/${REPO_PROJECT}/refs/heads/${REPO_BRANCH}"
}

## =============================================================================
## Install Git
## =============================================================================
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

## =============================================================================
## Detect sudo requirement
## =============================================================================
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

## =============================================================================
## Load config setting and overrides, if the files exists
## =============================================================================
load_config(){
  if [ -f "${CONFIG_FILE:-}" ]; then 
    . $CONFIG_FILE
  fi

  if [ -f "$PWD/override.config" ]; then
    . $PWD/override.config
    log_warn "Config override file loaded: $PWD/override.config"
  elif [ -f "$WORK_DIR/override.config" ]; then
    log_warn "Config override file loaded: $WORK_DIR/override.config"
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

## =============================================================================
## Manages the creation and ownership of the git destination directory, setup 
## of the spare checkout for the host specific folder (or overrides) and pulls
## the repo
## =============================================================================
pull_git_project() {
  create_repo_string

  log_step "Preparing project folder: $PROJECT_FOLDER"

  if [ ! -e "$PROJECT_FOLDER" ]; then
    log_info "Folder does not exist — creating and cloning..."

    GIT_OUT=$("$SUDO" mkdir -p "$PROJECT_FOLDER" 2>&1)
    if [ $? -ne 0 ]; then
      log_error "Failed to create project folder: $PROJECT_FOLDER"
      [ -n "$GIT_OUT" ] && log_error "$GIT_OUT"
      return 1
    fi
  fi

  GIT_OUT=$("$SUDO" chown "$REAL_USER:$REAL_GROUP" "$PROJECT_FOLDER" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "Failed to set ownership on: $PROJECT_FOLDER"
    [ -n "$GIT_OUT" ] && log_error "$GIT_OUT"
    return 1
  fi

  if [ ! -d "$PROJECT_FOLDER/.git" ]; then
    log_info "Cloning repository (no-checkout)..."
    GIT_OUT=$(git clone --quiet --no-checkout $REPO_STR $PROJECT_FOLDER 2>&1)
    if [ $? -ne 0 ]; then
      log_error "git clone failed for: $REPO_STR"
      [ -n "$GIT_OUT" ] && log_error "$GIT_OUT"
      return 1
    fi
    [ -n "$GIT_OUT" ] && log_debug "$GIT_OUT"
  fi

  log_info "Changing into project folder..."
  if ! cd "$PROJECT_FOLDER"; then
    log_error "Failed to cd into: $PROJECT_FOLDER"
    return 1
  fi

  log_info "Initialising sparse-checkout (cone mode)..."
  GIT_OUT=$(git sparse-checkout init --cone 2>&1)
  if [ $? -ne 0 ]; then
    log_error "git sparse-checkout init failed"
    [ -n "$GIT_OUT" ] && log_error "$GIT_OUT"
    return 1
  fi
  [ -n "$GIT_OUT" ] && log_debug "$GIT_OUT"

  ## Checkout only the folder with the system host name
  log_info "Setting sparse-checkout path: ${REPO_SERVER_PROJ:-<REPO_SERVER_PROJ is empty>}"
  GIT_OUT=$(git sparse-checkout set $REPO_SERVER_PROJ 2>&1)
  if [ $? -ne 0 ]; then
    log_error "git sparse-checkout set failed for: $REPO_SERVER_PROJ"
    [ -n "$GIT_OUT" ] && log_error "$GIT_OUT"
    return 1
  fi
  [ -n "$GIT_OUT" ] && log_debug "$GIT_OUT"

  log_info "Checking out branch: $REPO_BRANCH"
  GIT_OUT=$(git checkout --quiet "$REPO_BRANCH" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "git checkout failed for branch: $REPO_BRANCH"
    [ -n "$GIT_OUT" ] && log_error "$GIT_OUT"
    return 1
  fi
  [ -n "$GIT_OUT" ] && log_debug "$GIT_OUT"

  log_ok "Project ready at: $PROJECT_FOLDER (branch: $REPO_BRANCH)"
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
  detect_root_sudo
  load_logger
  load_config
  
  log_step "Installing git..."
  install_git

  log_step "Downloading host project..."  
  pull_git_project
}

main "$@"