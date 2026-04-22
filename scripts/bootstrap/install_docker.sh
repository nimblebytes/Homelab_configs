#!/bin/sh
## =============================================================================
## install_docker.sh — Install Or Uninstall Docker (Rootful Or Rootless)
## Installs Docker CE using the official APT repository and configures it for
## either rootful (system daemon) or rootless (per-user daemon) operation.
## Can also uninstall Docker, optionally purging all images and data.
##
## Usage: install_docker.sh [OPTIONS]
##   -c | --config <file>       Path to a parent config file to source
##                              (sets LOGGER_FILE, DOCKER_INSTALL_TYPE, etc.)
##   -l | --logger <file>       Path to better_logs.sh for structured log output
##   -R | --docker-rootful      Install Docker in rootful mode (default)
##   -r | --docker-rootless     Install Docker in rootless mode
##   -u | --uninstall [purge]   Uninstall Docker; append "purge" to also remove
##                              all images, containers, volumes, and data dirs
##   -v | --log-level <level>   Set log verbosity: DEBUG|INFO|STEP|OK|WARN|ERROR
##   -h | --help                Show this help message
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
DOCKER_INSTALL_TYPE="rootful"
LOG_LEVEL="STEP"

DIALOG_HEIGHT=20
DIALOG_WIDTH=70

SCRIPT_NAME="${0##*/}"
FLG_DOCKER_ROOTLESS=0
FLG_PURGE=0
FLG_UNINSTALL=0
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

Installs Docker CE using the official APT repository and configures it for
either rootful (system daemon) or rootless (per-user daemon) operation.
Adds a DOCKER_DETECT shell block to .bashrc that exports DOCKER_TYPE and
DOCKER_SOCK at login time so other scripts can reliably locate the socket.

Can also fully uninstall Docker, with an optional purge that removes all
images, containers, volumes, and data directories.

Options:
  -c | --config <file>       Source a parent config file that sets variables
                             such as LOGGER_FILE and DOCKER_INSTALL_TYPE.
                             Useful when called from bootstrap.sh.
  -l | --logger <file>       Path to better_logs.sh for structured log output.
                             Default: no file logging, fallback stubs used.
  -R | --docker-rootful      Install Docker in rootful mode (system daemon).
                             This is the default when no mode flag is given.
  -r | --docker-rootless     Install Docker in rootless mode. The daemon runs
                             as the invoking user with no root privileges.
                             Requires a non-root user to be detected (i.e. the
                             script must be run via sudo, not directly as root).
  -u | --uninstall [purge]   Uninstall Docker. If "purge" is appended as the
                             next argument, all images, containers, volumes, and
                             data directories are also removed.
  -v | --log-level <level>   Set the minimum log level for output. One of:
                             DEBUG  INFO  STEP  OK  WARN  ERROR
                             Default: STEP
  -h | --help                Show this help message and exit.

Examples:
  ## Install Docker in rootful mode (default):
  sudo sh $SCRIPT_NAME

  ## Install Docker in rootless mode with structured logging:
  sudo sh $SCRIPT_NAME --docker-rootless --logger /opt/scripts/better_logs.sh

  ## Load install type from a parent config file:
  sudo sh $SCRIPT_NAME --config /opt/scripts/bootstrap.env

  ## Uninstall Docker, keeping images and volumes:
  sudo sh $SCRIPT_NAME --uninstall

  ## Uninstall Docker and remove all data:
  sudo sh $SCRIPT_NAME --uninstall purge

  ## Install rootless with verbose debug output:
  sudo sh $SCRIPT_NAME --docker-rootless --log-level DEBUG

Environment variables (alternative to flags):
  CONFIG_FILE           Path to a parent config file to source
  LOGGER_FILE           Path to better_logs.sh
  DOCKER_INSTALL_TYPE   Set to "rootful" or "rootless" (overridden by -R/-r)
  WORK_DIR              Working directory used when locating override.config

Exit codes:
  0  Success
  1  Fatal error (insufficient privileges, package install failure, etc.)
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
  if [ -n "${SUDO_USER:-}" ]; then
    ## Running via sudo as root
    SUDO=""
    REAL_USER="$SUDO_USER"
    REAL_UID=$(id -u "$SUDO_USER")
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  elif [ "$(id -u)" -eq 0 ]; then
    ## Running directly as root
    SUDO=""
    REAL_USER=""
    REAL_UID=""
    REAL_HOME=""
  else
    ## Running as a normal user
    if sudo -n true >/dev/null 2>&1; then
      ## User has sudo privileges
      SUDO="sudo"
      REAL_USER="$(whoami)"
      REAL_UID=$(id -u)
      REAL_HOME="$HOME"
    else
      log_error "This script must be run as root or with sudo."
      return 1
    fi
  fi
  return 0
}

## =============================================================================
## Preflight Checks
## =============================================================================

## preflight_checks
## Verifies all prerequisites before any install work begins:
##   - Root or passwordless sudo access (sets SUDO, REAL_USER, REAL_UID, REAL_HOME)
## Exits with code 1 if the privilege check fails.
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
## Note: the sourced file can override DOCKER_INSTALL_TYPE, which is re-evaluated
## in main after this call to keep FLG_DOCKER_ROOTLESS in sync.
load_config_overrides() {
  if [ -f "$PWD/override.config" ]; then
    . "$PWD/override.config"
    log_warn "Config override loaded: $PWD/override.config"
  elif [ -f "$WORK_DIR/override.config" ]; then
    . "$WORK_DIR/override.config"
    log_warn "Config override loaded: $WORK_DIR/override.config"
  fi
}

## =============================================================================
## Docker installation
## =============================================================================

## install_docker
## Installs Docker CE and its official plugins using the APT package manager.
## This is the shared base installation used by both install_docker_rootful and
## install_docker_rootless. It:
##   1. Removes conflicting legacy docker packages
##   2. Adds Docker's official GPG key and APT repository
##   3. Installs docker-ce, docker-ce-cli, containerd.io, and the buildx and
##      compose plugins
##   4. If FLG_DOCKER_ROOTLESS is set, installs rootless dependencies, disables
##      the system-wide docker daemon, and runs the official rootless setup tool
##
## Requires SUDO to be set by detect_root_sudo before calling.
## Returns 1 if a required package fails to install; exits on rootless failure.
install_docker() {
  log_step "Install Docker using package manager"

  log_info "Removing old and conflicting docker packages"
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
    "$SUDO" apt-get remove -y -qq $pkg >/dev/null 2>&1
  done

  ## Add Docker's official GPG key:
  log_info "Adding Docker official GPG key to keyring"
  "$SUDO" apt-get update -y -qq 
  "$SUDO" apt-get install -y -qq ca-certificates curl
  "$SUDO" install -m 0755 -d /etc/apt/keyrings
  "$SUDO" curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  "$SUDO" chmod a+r /etc/apt/keyrings/docker.asc

  ## Add the docker repository, required to install docker-ce-rootless-extras package
  log_info "Adding docker repository to APT sources"
  "$SUDO" tee /etc/apt/sources.list.d/docker.sources <<EOF > /dev/null
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  ## Update to include packages from docker repository
  "$SUDO" apt-get update -y -qq

  log_info "Installing docker"
  for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do 
    "$SUDO" apt-get install -y -qq $pkg >/dev/null 2>&1 || \
      log_error "Unable to install docker required package $pkg"
        
  done

  ## Check if to convert from rootful to rootless
  [ "$FLG_DOCKER_ROOTLESS" -eq 0 ] && return
  log_step "Converting to Docker rootless"
  
  ## Install dependencies
  ## uidmap - provided subordinate UIDs/GIDs
  ## dbus-user-session - (Ubuntu recommended) D-Bus session bus for user 
  ##    sessions for running services like docker
  ## slirp4netns - provides network & port drivers. Can resolve source IP 
  ##    propagation issues. See https://docs.docker.com/engine/security/rootless/troubleshoot/#networking-errors
  ## docker-ce-rootless-extras - provides the official docker rootless install
  ##    script.
  log_info "Installing docker dependencies"
  "$SUDO" apt update -y -qq >/dev/null 2>&1
  for pkg in uidmap dbus-user-session slirp4netns docker-ce-rootless-extras; do 
    "$SUDO" apt-get install -y -qq $pkg >/dev/null 2>&1 || \
      { log_error "Unable to install docker dependancy package $pkg"; return 1; }
  done

  ## Disable system-wide docker daemon
  "$SUDO" systemctl disable --now docker.service docker.socket >/dev/null 2>&1
  [ -f "/var/run/docker.sock" ] && "$SUDO" rm /var/run/docker.sock

  ## Run the official docker rootless install script provided by docker-ce-rootless-extras
  PROCESS_OUTPUT=$(dockerd-rootless-setuptool.sh install 2>&1)
  if [ $? -ne 0 ]; then  
    log_error "The (official) Docker install script ran into issues. Script output:"
    log_error "$PROCESS_OUTPUT"
    return 1
  fi

  ## To launch the daemon on system startup, enable the systemd service and lingering
  systemctl --user enable docker
  systemctl --user start docker
  "$SUDO" loginctl enable-linger $(whoami)

}


## install_docker_rootful
## Installs Docker in rootful (system daemon) mode. Calls install_docker for
## the base package installation, then calls modify_bashrc_file to add the
## DOCKER_DETECT block to the real user's .bashrc so the correct socket and
## DOCKER_TYPE are exported on login.
## Exits with code 1 if the base installation fails.
install_docker_rootful(){

  log_step "Install Docker (rootful)..."

  install_docker || { log_error "Failed to install docker (rootful). Exiting script";  exit 1; }

  ## Add docker environment variables
  modify_bashrc_file "add"

  log_ok "Docker (rootful) installed"

}

## uninstall_docker
## Uninstalls Docker completely, handling both rootful and rootless installations.
## Steps performed in order:
##   1. Stop all running containers (rootful via system socket, rootless via user socket)
##   2. If FLG_PURGE=1: prune all images, containers, and volumes before package removal
##   3. Stop and disable all Docker systemd services (user and system)
##   4. Remove user-level and system-level Docker systemd service files
##   5. Reload systemd daemons (user then system)
##   6. Purge all Docker APT packages and run autoremove
##   7. If FLG_PURGE=1: remove data directories (/var/lib/docker,
##      /var/lib/containerd, ~/.local/share/docker)
##   8. Remove residual system files (APT source, GPG key, socket, /etc/docker)
##   9. Remove rootless user config directories (~/.docker, ~/.config/docker)
##  10. Disable loginctl linger for REAL_USER
##  11. Remove the docker group
##  12. Remove the DOCKER_DETECT block from .bashrc via modify_bashrc_file
##
## Requires SUDO, REAL_USER, REAL_UID, and REAL_HOME to be set by
## detect_root_sudo before calling.
uninstall_docker(){
  log_info "Uninstalling docker"

  FLAG_PURGE="${FLAG_PURGE:-0}"

  ## --------------------------------------------------------
  ## Stop running containers 
  ## Rootful containers
  if command -v docker >/dev/null 2>&1; then
    CONTAINERS=$("$SUDO" docker ps -q 2>/dev/null || true)
    [ -n "$CONTAINERS" ] && "$SUDO" docker stop $CONTAINERS || true
  fi

  ## Rootless container. Only if a real non-root user exists and their socket is live
  if [ -n "$REAL_UID" ] && [ -S "/run/user/${REAL_UID}/docker.sock" ]; then
    ROOTLESS_CONTAINERS=$(DOCKER_HOST="unix:///run/user/${REAL_UID}/docker.sock" \
      docker ps -q 2>/dev/null)
    [ -n "$ROOTLESS_CONTAINERS" ] && DOCKER_HOST="unix:///run/user/${REAL_UID}/docker.sock" \
      docker stop $ROOTLESS_CONTAINERS || true
  fi

  ## --------------------------------------------------------
  ## Purge containers, images, and volumes
  if [ "$FLAG_PURGE" = "1" ]; then
    log_info "Purging all containers, images, volumes..."

    # Rootful cleanup
    if command -v docker >/dev/null 2>&1; then
      "$SUDO" docker system prune -a --volumes -f || true
    fi

    # Rootless cleanup
    if [ -S "/run/user/$(id -u)/docker.sock" ]; then
      DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock" \
        docker system prune -a --volumes -f || true
    fi
  fi

  ## --------------------------------------------------------
  ## Stop and disable systemd services
  if command -v systemctl >/dev/null 2>&1; then

    # Rootless user services — only when a real non-root user was identified
    if [ -n "$REAL_USER" ]; then
      systemctl --user stop    docker         2>/dev/null || true
      systemctl --user disable docker         2>/dev/null || true
      systemctl --user stop    docker.socket  2>/dev/null || true
      systemctl --user disable docker.socket  2>/dev/null || true
    fi

    # Rootful system services
    "$SUDO" systemctl stop    docker        2>/dev/null || true
    "$SUDO" systemctl stop    docker.socket 2>/dev/null || true
    "$SUDO" systemctl disable docker        2>/dev/null || true
    "$SUDO" systemctl disable docker.socket 2>/dev/null || true
  fi

  ## --------------------------------------------------------
  ## Remove systemd service files then reload daemon
  if [ -n "$REAL_HOME" ]; then
    rm -f "${REAL_HOME}/.config/systemd/user/docker.service"
    rm -f "${REAL_HOME}/.config/systemd/user/docker.socket"
  fi
  [ -d "/etc/systemd/system/docker.service.d" ] && "$SUDO" rm -rf /etc/systemd/system/docker.service.d

  # Reload after file removal — user first, then system
  if command -v systemctl >/dev/null 2>&1; then
    [ -n "$REAL_USER" ] && systemctl --user daemon-reload 2>/dev/null || true
    "$SUDO" systemctl daemon-reload
  fi

  ## --------------------------------------------------------
  ## Uninstall docker packages
  for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras; do 
    "$SUDO" apt-get purge -y -qq $pkg >/dev/null 2>&1 || true
  done
  "$SUDO" apt-get autoremove -y -qq >/dev/null 2>&1 || true
  
  ## --------------------------------------------------------
  ## Remove all docker data (images, containers, and volumes)
  if [ "$FLAG_PURGE" = "1" ]; then
    log_info "Removing docker data directories"
    ## Rootful data
    ## /var/lib/docker: images, volumes, containers
    ## /var/lib/containerd: content store, snapshots
    [ -d "/var/lib/docker" ]     && "$SUDO" rm -rf /var/lib/docker    
    [ -d "/var/lib/containerd" ] && "$SUDO" rm -rf /var/lib/containerd
    ## Rootless data
    ## ~/.local/share/docker: rootless images, volumes
    if [ -n "$REAL_HOME" ]; then
      [ -d "${REAL_HOME}/.local/share/docker" ] && rm -rf "${REAL_HOME}/.local/share/docker"
    fi
  fi

  ## --------------------------------------------------------
  ## Remove system-wide config and residual files
  ## /etc/docker: system daemon config
  log_info "Removing residual system files"
  [ -f "/etc/apt/sources.list.d/docker.sources" ] && "$SUDO" rm -f /etc/apt/sources.list.d/docker.sources
  [ -f "/etc/apt/keyrings/docker.asc" ]           && "$SUDO" rm -f /etc/apt/keyrings/docker.asc
  [ -S "/var/run/docker.sock" ]                   && "$SUDO" rm -f /var/run/docker.sock
  [ -d "/etc/docker" ]                            && "$SUDO" rm -rf /etc/docker

  ## --------------------------------------------------------
  ## Remove Docker Rootless user directories
  ## ~/.docker: CLI config, credentials, contexts - not image data
  ## ~/.config/docker: daemon config for rootless
  if [ -n "$REAL_HOME" ]; then
    log_info "Removing rootless docker user files"
    [ -d "${REAL_HOME}/.docker" ]        && rm -rf "${REAL_HOME}/.docker"
    [ -d "${REAL_HOME}/.config/docker" ] && rm -rf "${REAL_HOME}/.config/docker"
    ## ~/.local/share/docker is "user data" and already handled under FLAG_PURGE above
  fi

  ## --------------------------------------------------------
  ## Remove linger for the real non-root user
  [ -n "$REAL_USER" ] && "$SUDO" loginctl disable-linger "$REAL_USER" || true

  "$SUDO" groupdel docker 2>/dev/null || true

  modify_bashrc_file "remove"

  log_ok "Docker (rootful) uninstalled"
}

## install_docker_rootless
## Installs Docker in rootless mode so the daemon runs under REAL_USER without
## root privileges. Calls install_docker (with FLG_DOCKER_ROOTLESS=1) which
## handles the rootless-specific steps: installing uidmap, dbus-user-session,
## slirp4netns, and docker-ce-rootless-extras; disabling the system daemon;
## running dockerd-rootless-setuptool.sh; and enabling the user-level systemd
## service with loginctl linger.
## After the base install, calls modify_bashrc_file to export the DOCKER_HOST
## and DOCKER_TYPE variables into REAL_USER's .bashrc.
## Exits with code 1 if the base installation fails.
install_docker_rootless(){

  log_step "Install Docker (rootless)..."

  install_docker || { log_error "Failed to install docker (rootless). Exiting script";  exit 1; }

  ## Add docker environment variables to .bashrc and current shell
  modify_bashrc_file "add"
  

  log_ok "Docker (rootless) installed"
}

## modify_bashrc_file <action>
## Adds or removes the DOCKER_DETECT block from the real user's .bashrc file.
## The block defines and calls detect_docker_install_type(), which inspects the
## active Docker context at login time to export DOCKER_TYPE, DOCKER_SOCK,
## DOCKER_HOST1, and DOCKER_HOST2 into the shell environment.
##
## Arguments:
##   add    — Appends the block if not already present, then sources .bashrc
##            into the current shell so the variables take effect immediately.
##   remove — Strips the block (between START_MARK and END_MARK) from .bashrc
##            using sed, then sources .bashrc to clear the exported variables.
##
## The function is a no-op if the block is already present (add) or already
## absent (remove). Returns 1 on unknown action.
modify_bashrc_file() {

  OPTIONS="$1"
  FILE="$HOME/.bashrc"

  START_MARK="# >>> DOCKER DETECT BLOCK >>>"
  END_MARK="# <<< DOCKER DETECT BLOCK <<<"

  # Ensure file exists
  [ -f "$FILE" ] || touch "$FILE"

  case "$OPTIONS" in
    add)
      # Only add if not already present
      TMP=$(mktemp)
      if ! grep -Fq "$START_MARK" "$FILE"; then
        ## Retrieve the .bashrc stub file for docker installs      
        if wget -qO "$TMP" "https://raw.githubusercontent.com/nimblebytes/Homelab_configs/refs/heads/master/common_configs/.bashrc.docker"; then
          {
              printf "%s\n" "$START_MARK"
              cat "$TMP"
              printf "%s\n" "$END_MARK"
          } >> "$FILE"
        else
            echo "Download failed — nothing written" >&2
        fi
      fi
      rm -f "$TMP"
      ;;

    remove)
      # Remove block between markers
      if grep -Fq "$START_MARK" "$FILE"; then
        TMP="$(mktemp)"
        sed "/$START_MARK/,/$END_MARK/d" "$FILE" > "$TMP" && mv "$TMP" "$FILE"
      fi
      ;;

    *)
      log_error "Unknown or empty option provided. .bashrc file not modified."
      return 1
      ;;
  esac

  ## Load the new environment varaibles into this script
  . "$HOME/.bashrc"
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
## Both "--flag value" and "--flag=value" forms are accepted for value flags.
##
## Flags:
##   -c | --config <file>       Set CONFIG_FILE (parent config to source)
##   -l | --logger <file>       Set LOGGER_FILE (path to better_logs.sh)
##   -R | --docker-rootful      Set FLG_DOCKER_ROOTLESS=0, DOCKER_INSTALL_TYPE=rootful
##   -r | --docker-rootless     Set FLG_DOCKER_ROOTLESS=1, DOCKER_INSTALL_TYPE=rootless
##   -u | --uninstall [purge]   Set FLG_UNINSTALL=1; if followed by "purge", also
##                              set FLG_PURGE=1 to remove all images and data
##   -v | --log-level <level>   Set LOG_LEVEL to one of: DEBUG INFO STEP OK WARN ERROR
##   -h | --help                Print usage and exit 0
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
      -c|--config)
        if [ -z "$VALUE" ]; then VALUE="$2"; shift; fi
        CONFIG_FILE="$VALUE"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -l|--logger)
        if [ -z "$VALUE" ]; then VALUE="$2"; shift; fi
        LOGGER_FILE="$VALUE"
        ;;
      -R|--docker-rootful)
        FLG_DOCKER_ROOTLESS=0
        DOCKER_INSTALL_TYPE="rootful"
        ;;
      -r|--docker-rootless)
        FLG_DOCKER_ROOTLESS=1
        DOCKER_INSTALL_TYPE="rootless"
        ;;
      -u|--uninstall)
        if [ -z "$VALUE" ]; then 
          if [ "$VALUE" = "purge" ]; then FLG_PURGE=1; shift; fi
        fi
        FLG_UNINSTALL=1
        ;;
      -v|--log_level)
        for OPTION in DEBUG INFO STEP OK WARN ERROR; do 
          [ "$VALUE" = "$OPTION" ] && LOG_LEVEL="OPTION"
        done
        [ "$LOG_LEVEL" != "$VALUE" ] && log_warn "Invalid log level provided: $VALUE. Will revert to default"
        shift
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

  ## Load the parent config first — it may set LOGGER_FILE.
  ## CLI flags from parse_args always take precedence as they are already stored;
  ## load_config_file only fills variables that are still empty.
  load_config_file
  load_logger
  preflight_checks
  load_config_overrides

  ## Check if loading the config or override changed what needs to be installed
  if [  -z "$DOCKER_INSTALL_TYPE" ]; then
    [ "$FLG_DOCKER_ROOTLESS" -eq 1 ] && DOCKER_INSTALL_TYPE = "rootless" || DOCKER_INSTALL_TYPE = "rootful"
  elif [ "$DOCKER_INSTALL_TYPE" = "rootful" ]; then
    FLG_DOCKER_ROOTLESS=0
  elif [ "$DOCKER_INSTALL_TYPE" = "rootless" ]; then
    FLG_DOCKER_ROOTLESS=1
  else
    log_error "Unknown docker type defined. Variable /$DOCKER_INSTALL_TYPE in config/override file must be set to 'rootless' or 'rootful'"
    return 1
  fi

  log_banner "Docker install script "


  if [ "$FLG_UNINSTALL" -eq 1 ]; then
    log_step "Uninstall docker (rootful)"
    uninstall_docker
  else
    if [ "$FLG_DOCKER_ROOTLESS" -eq 1 ]; then
      log_step "Install docker (rootless)"
      install_docker_rootless
    else
      log_step "Install docker (rootful)"
      install_docker_rootful
    fi
  fi

  log_ok "Docker script complete."
}

main "$@"