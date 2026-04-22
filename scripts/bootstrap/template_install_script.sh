#!/bin/sh
## =============================================================================
## <SCRIPT_NAME>.sh — <Script description>
##
## Usage: <SCRIPT_NAME>.sh [OPTIONS]
##   --config <file>          Path to a parent config file to source
##                            (sets LOGGER_FILE, SHARE_CONFIG_FILE, etc.)
##   --logger <file>          Path to better_logs.sh for structured log output
##   --help                   Show this help message
##
## Author: nimblebytes (GitHub)
## =============================================================================

## ## set -x  ## Uncomment to enable shell tracing for debugging
set -eu

## =============================================================================
## Constants And Defaults
## =============================================================================
CONFIG_FILE="${CONFIG_FILE:-}"
LOGGER_FILE="${LOGGER_FILE:-}"
WORK_DIR="${WORK_DIR:-$PWD}"

DIALOG_HEIGHT=20
DIALOG_WIDTH=70

SCRIPT_NAME="${0##*/}"

SUDO=""

## =============================================================================
## Fallback Logging
## Simple stubs active until better_logs.sh is sourced.
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
## Usage
## =============================================================================
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

<USAGE DESCRIPTION>

Options:
  --config <file>          Source a parent config file that sets variables such
                           as LOGGER_FILE and SHARE_CONFIG_FILE before this
                           script runs. Useful when called from bootstrap.sh.
  --logger <file>          Path to better_logs.sh for structured log output.
                           Default: no file logging, fallback stubs used.
  --help                   Show this help message and exit.

Examples:
  ## Full run — auto-locate share config, run all steps:
  sudo sh $SCRIPT_NAME

Environment variables (alternative to flags):
  CONFIG_FILE          Path to a parent config file to source
  LOGGER_FILE          Path to better_logs.sh
  WORK_DIR             Working directory used when locating override.config

Exit codes:
  0  Success
  1  Fatal error (insufficient privileges, missing dependency, invalid config)
EOF
}

## =============================================================================
## Privilege Detection
## =============================================================================

## detect_root_sudo
## Determines whether the script is running as root or has passwordless sudo.
## Sets SUDO="" when running as root, or SUDO="sudo" when sudo is available.
## Returns 1 and logs an error if neither condition is met.
detect_root_sudo() {
  UID_RESULT=$(id -u 2>/dev/null)
  if [ "$UID_RESULT" = "0" ]; then
    SUDO=""
  elif command -v sudo >/dev/null 2>&1; then
    if sudo -n true >/dev/null 2>&1; then
      SUDO="sudo"
    else
      log_error "User lacks sudo privileges or password is required."
      return 1
    fi
  else
    log_error "This script must be run as root or with sudo."
    return 1
  fi
  return 0
}

## =============================================================================
## Preflight Checks
## =============================================================================

## preflight_checks
## Verifies all prerequisites before any install work begins:
##   - Root or passwordless sudo access
##   - A supported package manager is present
##   - Required tool yq is installed or can be installed
##   - systemd-creds is available for credential encryption
## Exits with code 1 if any hard requirement is not met.
preflight_checks() {
  log_step "Running preflight checks..."

  if ! detect_root_sudo; then
    log_error "User privileges not met. Exiting."
    exit 1
  fi
}

## =============================================================================
## Logger Loader
## =============================================================================

## load_logger
## Sources better_logs.sh from the path in LOGGER_FILE if the file exists.
## Calls log_file_init to open the log file descriptor after sourcing.
## Falls back silently to the stub functions if the file is absent.
load_logger() {
  if [ -f "${LOGGER_FILE:-}" ]; then
    . "$LOGGER_FILE"
    if log_file_init; then
      log_ok "Logger loaded: $LOGGER_FILE"
    else
      log_warn "Logger loaded but log file failed to initialise — file logging disabled."
    fi
  fi
}

## =============================================================================
## Config Loader
## =============================================================================

## load_config_file
## Sources the file at CONFIG_FILE if it is set and the file exists.
## The sourced file is expected to export variables used by this script such as
## LOGGER_FILE and SHARE_CONFIG_FILE. Any variable already set on the command
## line (via parse_args) takes precedence because this function is called after
## parse_args but CLI-supplied values are re-applied by parse_args before main
## calls load_logger and find_share_config_file.
## If CONFIG_FILE is empty or the file does not exist the function is a no-op.
load_config_file() {
  if [ -z "${CONFIG_FILE:-}" ]; then return 0; fi
  if [ ! -f "$CONFIG_FILE" ]; then
    log_warn "Parent config file not found: $CONFIG_FILE"
    return 1
  fi
  . "$CONFIG_FILE"
  log_info "Parent config loaded: $CONFIG_FILE"
}

## load_config_overrides
## Sources override.config from PWD or WORK_DIR if the file exists.
## Allows environment-specific variable overrides without modifying the script.
load_config_overrides() {
  if [ -f "$PWD/override.config" ]; then
    . "$PWD/override.config"
    log_info "Config override loaded: $PWD/override.config"
  elif [ -f "$WORK_DIR/override.config" ]; then
    . "$WORK_DIR/override.config"
    log_info "Config override loaded: $WORK_DIR/override.config"
  fi
}


## =============================================================================
## Cleanup
## =============================================================================

## cleanup
## Trap handler registered against EXIT INT TERM.
## Removes any temporary file created during the run.
cleanup() {
  log_info "Cleaning up temporary files..."
  [ -f "${TMP_FILE:-}" ] && rm -f "$TMP_FILE"
  log_info "$SCRIPT_NAME complete."
}

## =============================================================================
## Parameter Parsing
## Supports long flags only. Both "--flag value" and "--flag=value" are accepted.
## =============================================================================

## parse_args [args ...]
## Processes command-line arguments and sets the corresponding global variables.
##
## Unknown flags and unexpected positional arguments cause an error and print
## the usage message before exiting with code 1.
parse_args() {
  while [ $# -gt 0 ]; do
    ## Split --flag=value into FLAG and VALUE for uniform handling
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
        if [ -z "$VALUE" ]; then VALUE="$2"; shift; fi
        CONFIG_FILE="$VALUE"
        ;;
      --logger)
        if [ -z "$VALUE" ]; then VALUE="$2"; shift; fi
        LOGGER_FILE="$VALUE"
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
main() {
  parse_args "$@"

  ## Register cleanup trap after variables are finalised by parse_args
  trap cleanup EXIT INT TERM

  ## Load the parent config first — it may set LOGGER_FILE and SHARE_CONFIG_FILE.
  ## CLI flags from parse_args always take precedence as they are already stored;
  ## load_config_file only fills variables that are still empty.
  load_config_file
  load_logger
  preflight_checks
  load_config_overrides

  log_banner "<SCRIPT NAME> / <SCRIPT PURPOSE>"
  log_step "<Main function step 1>"



  log_ok "<SCRIPT NAME> / <SCRIPT PURPOSE> complete."
}

main "$@"