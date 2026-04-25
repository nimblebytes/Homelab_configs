#!/bin/sh
## =============================================================================
## bootstrap.sh — VM Bootstrap Entry Point
## POSIX-compliant. Downloaded and executed on a fresh VM via:
##   wget -qO - https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/bootstrap/bootstrap.sh | sh
##
## Usage: bootstrap.sh [OPTIONS]
##   --repo-url <url>       Base URL for install scripts
##                          (default: hardcoded REPO_SCRIPT_BASE_URL)
##   --log-file <file>      Log file path
##                          (default: /var/log/bootstrap.log)
##   --work-dir <dir>       Working/temp directory
##                          (default: /tmp/bootstrap_<pid>)
##   --non-interactive      Skip dialogs and use built-in defaults
##   --help                 Show this help message
##
## *****************************************************************************
## ** IMPORTANT - Adding install features scripts **
## 
## To add or remove features to be installed via scripts, the following places
## need to be updated:
##  - collect_services_to_install
##    -> In the Dialog box section, add or remove the feature name, incl. if it 
##       is to be selected by default
##    -> In the case statement, add to remove the name of the script; (optional)
##       define the parameters to run the script with.
##    -> (Optional) Call function to collect feature settings in the case statement
##  - Main
##    -> The feature is to be installed by default, in the if statement for 
##       non-interactive installs add it to selected tools list
##  - collect_<FEATURE>_config
##    -> (Optional) Create a function to collect the feature specific settings
## =============================================================================

set -eu

## =============================================================================
## Constants And Global Defaults
## All bare (non-function) code lives here so the top of the script is the
## single source of truth for every tuneable value.
## =============================================================================
REPO_ORG=nimblebytes
REPO_PROJECT=Homelab_configs
REPO_BRANCH=master
REPO_BASE_URL="https://raw.githubusercontent.com/${REPO_ORG}/${REPO_PROJECT}/${REPO_BRANCH}"
REPO_SCRIPT_BASE_URL="${REPO_BASE_URL}/scripts"
REPO_BOOTSTRAP_BASE_URL="${REPO_BASE_URL}/scripts/bootstrap"

SCRIPT_DIR="/opt/scripts"             ## Directory where scripts will be downloaded to
WORK_DIR="/tmp/bootstrap_$$"          ## For temporary files created and used by this script
LOG_FILE="${WORK_DIR}/bootstrap.log"
CONFIG_FILE=""                        ## Derived after WORK_DIR is finalised — see init_config()
PKG_MGR=""                            ## Detected at preflight time
NON_INTERACTIVE="false"               ## Toggled by --non-interactive flag
LOG_LEVEL="STEP"


DIALOG_HEIGHT=20
DIALOG_WIDTH=70

BETTER_LOGS_URL="${REPO_SCRIPT_BASE_URL}/lib/better_logs.sh"
BETTER_LOGS_LOCAL="${SCRIPT_DIR}/better_logs.sh"

## Determine which user ran this script
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
## Usage
## =============================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Bootstrap a new Linux VM by selecting tools via a dialog interface.
Each selected tool is installed by a dedicated script downloaded from
the configured repository.

Options:
  --repo-url <url>       Base URL for remote install scripts
                         Default: $REPO_SCRIPT_BASE_URL
  --log-file <file>      Path to the log file
                         Default: $LOG_FILE
  --work-dir <dir>       Working directory for temporary files
                         Default: /tmp/bootstrap_<pid>
  --non-interactive      Skip dialogs and use built-in defaults
  --help                 Show this help message and exit

Examples:
  ## Standard interactive run (requires root):
  sudo sh bootstrap.sh

  ## Override the script repository and log location:
  sudo sh bootstrap.sh --repo-url https://example.com/scripts --log-file /tmp/boot.log

  ## Pipe from wget — interactive:
  wget -qO- https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/bootstrap/bootstrap.sh | sudo sh

  ## Pipe from wget — non-interactive (uses all defaults):
  wget -qO- https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/bootstrap/bootstrap.sh | sudo sh -s -- --non-interactive

Environment:
  All collected values are written to a mode-600 temp file and sourced
  into each child install script. Sensitive values (passwords, tokens)
  are never written to the log.

Exit codes:
  0  Success
  1  Fatal error (not root, no package manager, download failure, etc.)
EOF
}

## =============================================================================
## Package Manager Abstraction
## =============================================================================
pkg_install() {
  log_info "Installing package(s): $*"
  case "$PKG_MGR" in
    apt-get) $SUDO apt-get install -y "$@" ;;
    dnf|yum) "$PKG_MGR" install -y "$@" ;;
    apk)     apk add --no-cache "$@" ;;
  esac
}

pkg_update() {
  log_info "Updating package lists..."
  echo "Package Manger: ${PKG_MGR:-empty}"
  case "$PKG_MGR" in
    apt-get) $SUDO apt-get update -qq ;;
    dnf|yum) "$PKG_MGR" makecache -q ;;
    apk)     apk update -q ;;
  esac
}

## =============================================================================
## Preflight Checks
## =============================================================================
preflight_checks() {
  log_step "Running preflight checks..."

  if ! detect_root_sudo; then 
    log_error "User privileges not met. Exiting."
    exit 1
  fi

  ## Detect package manager — extend as needed
  if   command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt-get"
  elif command -v dnf     >/dev/null 2>&1; then PKG_MGR="dnf"
  elif command -v yum     >/dev/null 2>&1; then PKG_MGR="yum"
  elif command -v apk     >/dev/null 2>&1; then PKG_MGR="apk"
  else
    log_error "No supported package manager found."
    exit 1
  fi
  log_info "Package manager: $PKG_MGR"

  ## Ensure dialog and wget are present
  for DEP in dialog wget; do
    if ! command -v "$DEP" >/dev/null 2>&1; then
      log_info "Installing missing dependency: $DEP"
      pkg_install "$DEP"
    fi
  done

  "$SUDO" mkdir -p "$WORK_DIR"
  "$SUDO" chown "$REAL_USER:$REAL_GROUP" "$WORK_DIR"
  log_info "Working directory: $WORK_DIR"

  "$SUDO" mkdir -p "$SCRIPT_DIR"  
  "$SUDO" chown "$REAL_USER:$REAL_GROUP" "$SCRIPT_DIR"
  log_info "Scripts directory: $SCRIPT_DIR"
}

## Detect sudo requirement
detect_root_sudo() {
  ## Get the UID of the user, to check if running as root
  UID_RESULT=$(id -u 2>/dev/null)
  if [ "$UID_RESULT" = "0" ]; then
    SUDO=""
  ## Check if the 'sudo' command exists
  elif command -v sudo >/dev/null 2>&1; then
    if sudo -n true >/dev/null 2>&1; then
        SUDO="sudo"
    else
      log_error "User lacks sudo privileges or password is required."
      return 1
    fi
  else
    log_error "This script must be run as root or sudo."
    return 1
  fi
  return 0
}

## =============================================================================
## Better Logs Loader
## Attempts to download better_logs.sh from the repo and source it.
## Falls back silently to the stub functions defined in Fallback Logging.
## Must be called after WORK_DIR exists (i.e. after preflight_checks).
## =============================================================================
load_better_logs() {
  log_info "Attempting to load better_logs.sh..."
  log_info "Log file: $LOG_FILE" 

  #if [ -f "$BETTER_LOGS_LOCAL" ] || wget -q -N -P "$SCRIPT_DIR" "$BETTER_LOGS_URL" 2>/dev/null; then
  if wget -q -N -P "$SCRIPT_DIR" "$BETTER_LOGS_URL" 2>/dev/null; then
    . "$BETTER_LOGS_LOCAL"
    ## Re-assert LOG_FILE so the sourced library picks up our path
    LOG_FILE="$LOG_FILE"
    if log_file_init; then 
      log_ok "better_logs.sh loaded successfully."
    else
      log_warn "better_logs.sh loaded, but the log file failed to initialize. Logging to file is disabled."
    fi
  else
    log_warn "Could not download better_logs.sh — using fallback log functions."
  fi
}

## =============================================================================
## Config File Init And Helpers
## =============================================================================
## Initialise the config file once WORK_DIR is confirmed.
init_config() {
  CONFIG_FILE="$WORK_DIR/config.env"
  touch "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  log_info "Config file: $CONFIG_FILE"
}

## Load overrides for configs, if the file exists
load_config_overrides() {
  if [ -f "$PWD/override.config" ]; then
    . "$PWD/override.config"
    log_info "Config override file loaded: $PWD/override.config"
  elif [ -f "$WORK_DIR/override.config" ]; then
    . "$WORK_DIR/override.config"
    log_info "Config override file loaded: $WORK_DIR/override.config"
  fi
}

## All values gathered by collect_* functions are written to CONFIG_FILE.
## Sensitive values (passwords, tokens) are only ever held in that mode-600
## temp file and are never written to the log.
write_cfg() { printf '%s="%s"\n' "$1" "$2" >> "$CONFIG_FILE"; }

## =============================================================================
## Dialog Helpers
## =============================================================================

## dialog_checklist <TITLE> <PROMPT> <TAG> <ITEM> <STATUS> ...
## Returns selected tags (space-separated) via stdout.
dialog_checklist() {
  TITLE="$1"; PROMPT="$2"; shift 2
  dialog --erase-on-exit \
    --title "$TITLE" \
    --checklist "$PROMPT" \
    $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
    "$@" \
    3>&1 1>&2 2>&3
}

## dialog_inputbox <TITLE> <PROMPT> [DEFAULT]
dialog_inputbox() {
  TITLE="$1"; PROMPT="$2"; DEFAULT="${3:-}"
  dialog --erase-on-exit \
    --title "$TITLE" \
    --inputbox "$PROMPT" \
    10 $DIALOG_WIDTH "$DEFAULT" \
    3>&1 1>&2 2>&3
}

## dialog_menu <TITLE> <PROMPT> <HEIGHT> <TAG> <ITEM> ...
## HEIGHT controls how many items are visible in the list.
dialog_menu() {
  TITLE="$1"; PROMPT="$2"; MENU_HEIGHT="$3"; shift 3
  dialog --erase-on-exit \
    --title "$TITLE" \
    --menu "$PROMPT" \
    $DIALOG_HEIGHT $DIALOG_WIDTH "$MENU_HEIGHT" \
    "$@" \
    3>&1 1>&2 2>&3
}

## dialog_passwordbox <TITLE> <PROMPT>
dialog_passwordbox() {
  TITLE="$1"; PROMPT="$2"
  dialog --erase-on-exit \
    --title "$TITLE" \
    --passwordbox "$PROMPT" \
    10 $DIALOG_WIDTH \
    3>&1 1>&2 2>&3
}

## dialog_yesno <TITLE> <PROMPT> — returns 0=yes 1=no
dialog_yesno() {
  dialog --erase-on-exit \
    --title "$1" \
    --yesno "$2" \
    8 $DIALOG_WIDTH \
    3>&1 1>&2 2>&3
}

## dialog_msgbox <TITLE> <MESSAGE>
dialog_msgbox() {
  dialog --erase-on-exit \
    --title "$1" \
    --msgbox "$2" \
    10 $DIALOG_WIDTH \
    3>&1 1>&2 2>&3
}

## =============================================================================
## User Input Collection
## =============================================================================
collect_services_to_install() {
  log_step "Collecting tool selection from user..."

  SELECTED=$(dialog_checklist \
    "Tool Selection" \
    "Select the tools to install/configure on this VM:" \
    "system"    "Change host name, timezone, dns"               off \
    "git"       "Install Git + load host projects"              on  \
    "nfs_samba" "Install NFS/SMB and connect shares"            on  \
    "docker"    "Install Docker Compose + start containers"     off \
    "ansible"   "Ansible (control node)"                        off \
  ) || { log_warn "Tool selection cancelled."; exit 0; }

  write_cfg SELECTED_TOOLS "$SELECTED"
  log_info "Selected tools: $SELECTED"

  ## Map each tool name to the script that installs it, then collect any
  ## tool-specific config. Combining both steps here means a single pass
  ## over the selection covers both concerns.
  for TOOL in $SELECTED; do
    case "$TOOL" in
      system)     
        write_cfg "SCRIPT_${TOOL}" "change_system_settings.sh"
        ;;
      git)
        write_cfg "SCRIPT_${TOOL}" "install_host_git_project.sh"
        #collect_git_config
        ;;
      docker)
        write_cfg "SCRIPT_${TOOL}" "install_docker.sh"
        write_cfg "ARGS_${TOOL}"   "--docker-rootful"
        # write_cfg "ARGS_${TOOL}"   "--parent-config $CONFIG_FILE --logger $BETTER_LOGS_LOCAL --docker-rootful"
        collect_docker_config
        ;;
      nfs_samba)
        write_cfg "SCRIPT_${TOOL}" "install_host_network_shares.sh"
        #collect_network_config
        ;;
      ansible)
        write_cfg "SCRIPT_${TOOL}" "install_ansible"
        ## No extra config needed for ansible
        ;;
    esac
  done
}

collect_git_config() {
  log_step "Collecting Git configuration..."

  GIT_USER_NAME=$(dialog_inputbox "Git Config" \
    "Git user.name (for commits):") || true
  write_cfg GIT_USER_NAME "$GIT_USER_NAME"

  GIT_USER_EMAIL=$(dialog_inputbox "Git Config" \
    "Git user.email:") || true
  write_cfg GIT_USER_EMAIL "$GIT_USER_EMAIL"
}

collect_nfs_config() {
  log_step "Collecting NFS configuration..."

  NFS_SERVER=$(dialog_inputbox "NFS Server" \
    "Enter the NFS server address (IP or hostname):") || true
  write_cfg NFS_SERVER "$NFS_SERVER"

  NFS_EXPORT=$(dialog_inputbox "NFS Export" \
    "Enter the export path on the server (e.g. /exports/data):" \
    "/exports/data") || true
  write_cfg NFS_EXPORT "$NFS_EXPORT"

  NFS_MOUNT=$(dialog_inputbox "NFS Mount Point" \
    "Local mount point:" \
    "/mnt/nfs") || true
  write_cfg NFS_MOUNT "$NFS_MOUNT"
}

collect_network_config() {
  log_step "Collecting network share configuration..."
  collect_nfs_config
  collect_samba_config
}

collect_samba_config() {
  log_step "Collecting Samba configuration..."

  SMB_USER=$(dialog_inputbox "Samba" "Samba username:") || true
  SMB_PASS=$(dialog_passwordbox "Samba" "Samba password (not logged):") || true
  SMB_SHARE=$(dialog_inputbox "Samba" \
    "UNC share path (e.g. //server/share):" \
    "//192.168.1.1/share") || true
  SMB_MOUNT=$(dialog_inputbox "Samba" "Local mount point:" "/mnt/smb") || true

  write_cfg SMB_USER  "$SMB_USER"
  write_cfg SMB_PASS  "$SMB_PASS"  ## stays in mode-600 temp file only
  write_cfg SMB_SHARE "$SMB_SHARE"
  write_cfg SMB_MOUNT "$SMB_MOUNT"
}

collect_docker_config() {
  log_step "Collecting Docker configuration..."

  DOCKER_COMPOSE_DIR=$(dialog_inputbox "Docker" \
    "Path to store Compose project files:" \
    "/opt/docker") || true
  write_cfg DOCKER_COMPOSE_DIR "$DOCKER_COMPOSE_DIR"

  if dialog_yesno "Docker Registry" \
    "Do you need to log in to a private Docker registry?"; then

    REGISTRY_URL=$(dialog_inputbox "Registry" \
      "Registry URL (leave blank for Docker Hub):") || true
    REGISTRY_USER=$(dialog_inputbox "Registry" "Username:") || true
    REGISTRY_PASS=$(dialog_passwordbox "Registry" \
      "Password / token (not logged):") || true

    write_cfg REGISTRY_URL  "$REGISTRY_URL"
    write_cfg REGISTRY_USER "$REGISTRY_USER"
    write_cfg REGISTRY_PASS "$REGISTRY_PASS"
  fi
}

## =============================================================================
## Script Downloader And Runner
## Each tool has a corresponding install script at:
##   $REPO_SCRIPT_BASE_URL/install_<tool>
## The script is downloaded, made executable, then run in a subshell with the
## config env sourced so every variable is available to the child script.
## =============================================================================
run_script() {
  SCRIPT_NAME="$1"
  TOOL_ARGS="${2:-}"
  LOCAL_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
  REMOTE_URL="${REPO_BOOTSTRAP_BASE_URL}/${SCRIPT_NAME}"
  
  log_info "Fetching script: $REMOTE_URL"
  if ! wget -q -N -P "$SCRIPT_DIR" "$REMOTE_URL"; then
    log_error "Failed to download $REMOTE_URL — skipping."
    return 1
  fi
  
  chmod +x "$LOCAL_PATH"
  log_info "Running: $LOCAL_PATH"
  # (
    export CONFIG_FILE="$CONFIG_FILE"
    export LOGGER_FILE="$BETTER_LOGS_LOCAL"
    ## TOOL_ARGS is defined in collect_services_to_install
    ## TOOL_ARGS is unquoted so the shell word-splits it into individual
    ## flag/value tokens.
    sh "$LOCAL_PATH" $TOOL_ARGS
  # ) | tee -a "$LOG_FILE"
  log_ok "Finished: ${SCRIPT_NAME}"
}

run_selected_scripts() {
  ## Reload the config to refresh the SCRIPT_* and ARGS_* variables
  . "$CONFIG_FILE"

  log_step "Beginning installation phase for: $SELECTED_TOOLS"

  for TOOL in $SELECTED_TOOLS; do
    log_divider
    log_step "Processing: $TOOL"

    ## Look up the script name assigned during tool selection.
    ## eval is used to resolve the variable name built from SCRIPT_<TOOL>;
    ## this is safe here because TOOL values come from a fixed case list.
    eval "TOOL_SCRIPT=\${SCRIPT_${TOOL}:-}"
    eval "TOOL_ARGS=\${ARGS_${TOOL}:-}"

    if [ -z "$TOOL_SCRIPT" ]; then
      log_warn "No script mapped for tool: $TOOL — skipping."
    else
      if ! run_script "$TOOL_SCRIPT" "$TOOL_ARGS"; then
        log_warn "$TOOL_SCRIPT reported an error — continuing."
      fi
    fi
  done
}

## =============================================================================
## Cleanup
## =============================================================================
cleanup() {
  log_info "Cleaning up temporary files..."
  rm -f "$CONFIG_FILE"
  rm -rf "$WORK_DIR"
  log_info "Bootstrap complete. Full log at: $LOG_FILE"
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
      --repo-url)
        if [ -z "$VALUE" ]; then
          VALUE="$2"
          shift
        fi
        REPO_SCRIPT_BASE_URL="$VALUE"
        ;;
      --log-file)
        if [ -z "$VALUE" ]; then
          VALUE="$2"
          shift
        fi
        LOG_FILE="$VALUE"
        ;;
      --work-dir)
        if [ -z "$VALUE" ]; then
          VALUE="$2"
          shift
        fi
        WORK_DIR="$VALUE"
        ;;
      --non-interactive)
        NON_INTERACTIVE="true"
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

  ## Register cleanup trap after WORK_DIR / LOG_FILE are finalised by parse_args
  trap cleanup EXIT INT TERM

  #clear

  ## Preflight runs first so WORK_DIR exists before we try to download anything
  pkg_update
  preflight_checks

  ## Now WORK_DIR exists — attempt to upgrade to pretty logging
  load_better_logs
  log_banner "VM Bootstrap — $(date '+%Y-%m-%d')"

  init_config
  load_config_overrides

  ## Define the feature that need to be installed by default when non-interactive
  if [ "$NON_INTERACTIVE" = "true" ]; then
    log_warn "Non-interactive mode: using built-in defaults, skipping dialogs."
    write_cfg SELECTED_TOOLS "git nfs_samba"
    write_cfg VM_HOSTNAME "$(hostname)"
    write_cfg VM_TIMEZONE "UTC"
  else
    collect_services_to_install
  fi

  log_step "Starting bootstrap..."
  run_selected_scripts

  log_ok "Bootstrap finished successfully. ${C_YELLOW:-}Log file:${C_RESET:-} $LOG_FILE"
}

main "$@"