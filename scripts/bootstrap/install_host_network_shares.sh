#!/bin/sh
## =============================================================================
## install_host_network_shares.sh — Install And Configure NFS/SMB Network Mounts
## Reads mount definitions from a YAML config file, generates systemd unit files
## for each share, encrypts SMB credentials using systemd-creds, and enables all
## units so mounts are active after the next boot or daemon reload.
##
## Usage: install_host_network_shares.sh [OPTIONS]
##   --parent-config <file>   Path to a parent config file to source
##                            (sets LOGGER_FILE, SHARE_CONFIG_FILE, etc.)
##   --share-config <file>    Path to the YAML share config file
##   --logger <file>          Path to better_logs.sh for structured log output
##   --create-units           Create systemd unit files only
##   --create-creds           Create encrypted SMB credentials only
##   --change-creds           Update existing SMB credentials only
##   --dry-run                Print what would be done without making changes
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
SHARE_CONFIG_FILE="${SHARE_CONFIG_FILE:-}"
WORK_DIR="${WORK_DIR:-$PWD}"

DIALOG_HEIGHT=20
DIALOG_WIDTH=70

SCRIPT_NAME="${0##*/}"
CONST_UNIT_DIR="/etc/systemd/system"
CONST_CRED_DIR="/etc/systemd/credentials"
CONST_SMB_GROUP_FILE="smb-mounts.target"
CONST_NFS_GROUP_FILE="nfs-mounts.target"

PKG_MGR=""
SUDO=""
TMP_FILE=""
FLG_DRYRUN=0

## Action flags — set by the corresponding CLI flags.
## Setup mode flags (--create-units, --create-creds) may be combined freely.
## Change-creds mode (--change-creds) and remove mode (--remove-shares) are
## each mutually exclusive with all setup flags and with each other.
## When no action flag is set, setup mode runs all setup steps.
FLG_ACT_CREATE_UNITS=0
FLG_ACT_CREATE_CREDS=0
FLG_ACT_CHANGE_CREDS=0
FLG_ACT_REMOVE_SHARES=0

TAB=$(printf '\t')

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

Reads NFS and SMB mount definitions from a YAML share config file, generates
systemd unit files for each share, encrypts SMB credentials using systemd-creds,
and enables all units so mounts are active after the next boot or daemon reload.

By default all three actions run sequentially. Use the action flags to run only
specific steps — useful when re-running after a partial failure or when updating
credentials on an already-configured system.

Options:
  --parent-config <file>   Source a parent config file that sets variables such
                           as LOGGER_FILE and SHARE_CONFIG_FILE before this
                           script runs. Useful when called from bootstrap.sh.
  --share-config <file>    Path to the YAML network share config file.
                           If not provided the script searches:
                             1. Current working directory
                             2. /opt/git/*/configs/
  --logger <file>          Path to better_logs.sh for structured log output.
                           Default: no file logging, fallback stubs used.
  --create-units           Create systemd unit files (and enable them).
                           Setup mode — may be combined with --create-creds.
  --create-creds           Create encrypted SMB credential files.
                           Setup mode — may be combined with --create-units.
  --change-creds           Update credentials for an existing SMB profile.
                           Mutually exclusive with all setup flags and --remove-shares.
  --remove-shares          Disable, stop, and remove all systemd unit files
                           managed by this script that are NOT listed in the
                           share config. Also removes empty mount point dirs
                           and group targets when no units of that type remain.
                           Mutually exclusive with all setup flags and --change-creds.
  --dry-run                Print what would be done without making any changes.
  --help                   Show this help message and exit.

Examples:
  ## Full run — auto-locate share config, run all steps:
  sudo sh $SCRIPT_NAME

  ## Specify config and logger explicitly:
  sudo sh $SCRIPT_NAME --share-config /etc/shares.yaml --logger /opt/scripts/better_logs.sh

  ## Load settings from a parent config then run all steps:
  sudo sh $SCRIPT_NAME --parent-config /opt/scripts/bootstrap.env

  ## Re-create unit files only (e.g. after editing the share config):
  sudo sh $SCRIPT_NAME --create-units

  ## Remove shares that are no longer in the config (dry-run preview first):
  sudo sh $SCRIPT_NAME --remove-shares --dry-run
  sudo sh $SCRIPT_NAME --remove-shares

  ## Update SMB credentials only:
  sudo sh $SCRIPT_NAME --change-creds

  ## Preview all actions without writing any files:
  sudo sh $SCRIPT_NAME --dry-run

Environment variables (alternative to flags):
  CONFIG_FILE          Path to a parent config file to source
  SHARE_CONFIG_FILE    Path to the YAML share config file
  LOGGER_FILE          Path to better_logs.sh
  WORK_DIR             Working directory used when locating override.config

Exit codes:
  0  Success
  1  Fatal error (insufficient privileges, missing dependency, invalid config)
EOF
}

## =============================================================================
## Package Manager Abstraction
## =============================================================================

## pkg_install <package> [package ...]
## Installs one or more packages using the detected package manager.
## Requires PKG_MGR and SUDO to be set by preflight_checks first.
pkg_install() {
  log_info "Installing package(s): $*"
  case "$PKG_MGR" in
    apt-get) $SUDO apt-get install -y "$@" ;;
    dnf|yum) "$PKG_MGR" install -y "$@" ;;
    apk)     apk add --no-cache "$@" ;;
  esac
}

## pkg_update
## Refreshes the package manager's metadata/cache.
## Requires PKG_MGR and SUDO to be set by preflight_checks first.
pkg_update() {
  log_info "Updating package lists..."
  case "$PKG_MGR" in
    apt-get) $SUDO apt-get update -qq ;;
    dnf|yum) "$PKG_MGR" makecache -q ;;
    apk)     apk update -q ;;
  esac
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

  ## Update package list before installing any dependencies
  pkg_update

  ## Ensure yq is present (used to parse the YAML share config)
  if ! command -v yq >/dev/null 2>&1; then
    log_info "Installing missing dependency: yq"
    pkg_install yq
  fi

  ## systemd-creds is required to encrypt SMB credentials
  if ! command -v systemd-creds >/dev/null 2>&1; then
    log_error "systemd-creds not found. This script requires systemd."
    log_error "Modify the script to handle non-systemd environments if needed."
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

## find_share_config_file
## Locates the YAML share config file when SHARE_CONFIG_FILE is not already set.
## Search order:
##   1. Current working directory — network_mounts.yaml
##   2. /opt/git/*/configs/network_mounts.yaml  (glob expanded by the shell)
## Sets SHARE_CONFIG_FILE to the first match found and logs the path.
## Exits with code 1 if no file is found, as nothing can proceed without it.
find_share_config_file() {
  if [ -n "${SHARE_CONFIG_FILE:-}" ]; then
    if [ ! -f "$SHARE_CONFIG_FILE" ]; then
      log_error "Share config file not found: $SHARE_CONFIG_FILE"
      exit 1
    fi
    log_info "Using share config: $SHARE_CONFIG_FILE"
    return 0
  fi

  ## Search 1: current working directory
  if [ -f "$PWD/network_mounts.yaml" ]; then
    SHARE_CONFIG_FILE="$PWD/network_mounts.yaml"
    log_info "Share config found in CWD: $SHARE_CONFIG_FILE"
    return 0
  fi

  ## Search 2: /opt/git/*/configs/ — use a for loop so the glob is
  ## expanded by the shell without requiring nullglob (not POSIX)
  for CANDIDATE in /opt/git/*/configs/network_mounts.yaml; do
    if [ -f "$CANDIDATE" ]; then
      SHARE_CONFIG_FILE="$CANDIDATE"
      log_info "Share config found at: $SHARE_CONFIG_FILE"
      return 0
    fi
  done

  log_error "No share config file found."
  log_error "Provide one with --share-config, set SHARE_CONFIG_FILE, or place"
  log_error "network_mounts.yaml in the current directory or /opt/git/*/configs/"
  exit 1
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
## Command Helpers
## =============================================================================

## run_cmd <command> [args ...]
## Executes a command prefixed with $SUDO, suppressing all output.
## In dry-run mode prints what would be executed instead of running it.
run_cmd() {
  if [ "$FLG_DRYRUN" -eq 1 ]; then
    printf "${C_YELLOW:-}[dry-run]${C_RESET:-} %s %s\n" "$SUDO" "$*"
  else
    sh -c "$SUDO $*" >/dev/null 2>&1
    return $?
  fi
  return 0
}

## write_file <destination>
## Reads from stdin and writes to <destination> using sudo tee.
## In dry-run mode prints the destination path and discards stdin.
write_file() {
  PATH_DESTINATION="$1"

  if [ "$FLG_DRYRUN" -eq 1 ]; then
    printf "${C_YELLOW:-}[dry-run]${C_RESET:-} Write file: ${C_BG_CYAN:-}%s${C_RESET:-}\n" "$PATH_DESTINATION"
    cat > /dev/null
    return 0
  fi

  sudo tee "$PATH_DESTINATION" > /dev/null
}

## =============================================================================
## Package Installation
## =============================================================================

## install_cifs_nfs
## Installs the cifs-utils and nfs-common packages required for SMB and NFS
## mounts. Uses pkg_install which requires PKG_MGR to be set by preflight_checks.
install_cifs_nfs() {
  log_info "Installing network mount packages: cifs-utils, nfs-common"

  for DEP in cifs-utils nfs-common; do
    if ! dpkg -s "$DEP" >/dev/null 2>&1; then
      log_info "Installing: $DEP"
      if ! pkg_install "$DEP"; then
        log_error "Installation failed for: $DEP"
      fi
    fi
  done

  return 0
}

## =============================================================================
## Config Validation
## =============================================================================

## validate_share_config
## Reads SHARE_CONFIG_FILE and checks that every mount entry has a recognised type
## (smb or nfs). Returns the number of invalid entries, or 1 if the file
## cannot be parsed. Logs a warning for each invalid entry found.
validate_share_config() {
  i=0
  INT_INVALID=0
  TMP_FILE=$(mktemp)

  log_info "Validating config file: $SHARE_CONFIG_FILE"
  yq -e '.mounts | length > 0' "$SHARE_CONFIG_FILE" >/dev/null 2>&1 || log_error "Invalid or empty mounts list"

  ## Write all type values to a temp file for iteration
  yq -r '.mounts[].type' "$SHARE_CONFIG_FILE" > "$TMP_FILE" || { rm -f "$TMP_FILE"; return 1; }

  while read -r TYPE; do
    if [ "$TYPE" != "smb" ] && [ "$TYPE" != "nfs" ]; then
      NAME=$(yq -r ".mounts[$i] | .name" "$SHARE_CONFIG_FILE")
      INT_INVALID=$((INT_INVALID + 1))
      log_warn "Mount '$NAME' has invalid type '$TYPE' — expected 'smb' or 'nfs'."
    fi
    i=$((i + 1))
  done < "$TMP_FILE"

  rm -f "$TMP_FILE"
  return $INT_INVALID
}

## =============================================================================
## Unit File Templates
## =============================================================================

## create_smb_unit <n> <source> <target> <profile>
## Generates a systemd service unit file for an SMB mount at <target>.
## The unit uses systemd-creds to load the encrypted credential file for
## <profile> at mount time. In dry-run mode prints the target path only.
create_smb_unit() {
  SHARE_NAME="$1"; SOURCE="$2"; TARGET="$3"; PROFILE="$4"
  UNIT_FILE=$(printf '%s' "$TARGET" | sed 's|^/||; s|/|-|g').service

  if [ "$FLG_DRYRUN" -eq 1 ]; then
    printf "${C_YELLOW:-}[dry-run]${C_RESET:-} Create unit file: %s/%s\n" "$CONST_UNIT_DIR" "$UNIT_FILE"
    return 0
  fi

  cat <<EOF | write_file "$CONST_UNIT_DIR/$UNIT_FILE"
[Unit]
Description=SMB mount - $TARGET
After=network-online.target
Wants=network-online.target
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
LoadCredentialEncrypted=${PROFILE}.cred:/etc/systemd/credentials/${PROFILE}.cred
ExecStart=/bin/mount -t cifs $SOURCE $TARGET -o vers=3.1.1,serverino,iocharset=utf8,credentials=%d/${PROFILE}.cred
ExecStop=/bin/umount $TARGET

[Install]
WantedBy=$CONST_SMB_GROUP_FILE
EOF
}

## create_nfs_unit <n> <source> <target>
## Generates a systemd mount unit file for an NFS mount at <target>.
## Uses NFSv4.1 with hard mount and sensible timeout defaults.
## In dry-run mode prints the target path only.
create_nfs_unit() {
  SHARE_NAME="$1"; SOURCE="$2"; TARGET="$3"
  UNIT_FILE=$(printf '%s' "$TARGET" | sed 's|^/||; s|/|-|g').mount

  if [ "$FLG_DRYRUN" -eq 1 ]; then
    printf "${C_YELLOW:-}[dry-run]${C_RESET:-} Create unit file: %s/%s\n" "$CONST_UNIT_DIR" "$UNIT_FILE"
    return 0
  fi

  cat <<EOF | write_file "$CONST_UNIT_DIR/$UNIT_FILE"
[Unit]
Description=NFS mount $TARGET
After=network-online.target
Before=docker.service

[Mount]
What=$SOURCE
Where=$TARGET
Type=nfs
Options=_netdev,hard,nfsvers=4.1,timeo=600,retrans=5

[Install]
WantedBy=$CONST_NFS_GROUP_FILE
EOF
}

## create_smb_group_unit
## Generates the smb-mounts.target group unit that all SMB service units depend
## on. This target is the single enable/disable point for all SMB mounts.
## In dry-run mode prints the target path only.
create_smb_group_unit() {
  if [ "$FLG_DRYRUN" -eq 1 ]; then
    printf "${C_YELLOW:-}[dry-run]${C_RESET:-} Create unit file: %s/%s\n" "$CONST_UNIT_DIR" "$CONST_SMB_GROUP_FILE"
    return 0
  fi

  cat <<EOF | write_file "$CONST_UNIT_DIR/$CONST_SMB_GROUP_FILE"
[Unit]
Description=All SMB Mounts
Wants=network-online.target
After=network-online.target
Before=docker.service
EOF
}

## create_nfs_group_unit
## Generates the nfs-mounts.target group unit that all NFS mount units depend
## on. This target is the single enable/disable point for all NFS mounts.
## In dry-run mode prints the target path only.
create_nfs_group_unit() {
  if [ "$FLG_DRYRUN" -eq 1 ]; then
    printf "${C_YELLOW:-}[dry-run]${C_RESET:-} Create unit file: %s/%s\n" "$CONST_UNIT_DIR" "$CONST_NFS_GROUP_FILE"
    return 0
  fi

  cat <<EOF | write_file "$CONST_UNIT_DIR/$CONST_NFS_GROUP_FILE"
[Unit]
Description=All NFS mounts
Wants=remote-fs-pre.target
After=remote-fs-pre.target
Before=docker.service
EOF
}

## =============================================================================
## Unit File Orchestration
## =============================================================================

## create_units
## Reads all mount entries from SHARE_CONFIG_FILE, validates them, creates the mount
## point directory, and generates the corresponding systemd unit file for each
## entry. Also creates the SMB/NFS group target units as required, then reloads
## the systemd daemon so the new units are recognised immediately.
create_units() {
  validate_share_config || {
    log_error "Invalid entries in '$SHARE_CONFIG_FILE' must be fixed before continuing."
    exit 1
  }

  FLG_SMB=0
  FLG_NFS=0
  TMP_FILE=$(mktemp)

  yq -r '.mounts[].name' "$SHARE_CONFIG_FILE" > "$TMP_FILE"

  while read -r NAME; do
    TYPE=$(yq -r ".mounts[] | select(.name==\"$NAME\") | .type" "$SHARE_CONFIG_FILE")
    SOURCE=$(yq -r ".mounts[] | select(.name==\"$NAME\") | .source" "$SHARE_CONFIG_FILE")
    TARGET=$(yq -r ".mounts[] | select(.name==\"$NAME\") | .target" "$SHARE_CONFIG_FILE")
    PROFILE=$(yq -r ".mounts[] | select(.name==\"$NAME\") | .user_profile // \"\"" "$SHARE_CONFIG_FILE")

    ## Require an absolute path for the mount target
    if [ "${TARGET#/}" = "$TARGET" ]; then
      log_error "Mount target must be an absolute path (must start with '/'). Got: $TARGET"
      continue
    fi

    run_cmd mkdir -p "$TARGET"

    if [ "$TYPE" = "smb" ]; then
      if [ -z "$PROFILE" ]; then
        log_error "SMB mount '$NAME' is missing user_profile — skipping."
        continue
      fi
      create_smb_unit "$NAME" "$SOURCE" "$TARGET" "$PROFILE"
      FLG_SMB=1
    else
      create_nfs_unit "$NAME" "$SOURCE" "$TARGET"
      FLG_NFS=1
    fi

    log_info "Created unit for mount: ${C_CYAN:-}${NAME}${C_RESET:-}"
  done < "$TMP_FILE"

  if [ "$FLG_SMB" -ne 0 ]; then
    create_smb_group_unit
    log_info "Created group target: ${C_CYAN:-}SMB${C_RESET:-}"
  fi
  if [ "$FLG_NFS" -ne 0 ]; then
    create_nfs_group_unit
    log_info "Created group target: ${C_CYAN:-}NFS${C_RESET:-}"
  fi

  run_cmd systemctl daemon-reload
  rm -f "$TMP_FILE"
}

## =============================================================================
## Credential Management
## =============================================================================

## create_credentials
## For each unique SMB user_profile in SHARE_CONFIG_FILE, prompts for a username and
## password, then encrypts them into a systemd-creds credential file stored in
## CONST_CRED_DIR. Skips profiles that already have a credential file.
create_credentials() {
  run_cmd mkdir -p "$CONST_CRED_DIR"
  run_cmd chmod 700 "$CONST_CRED_DIR"

  PROFILES=$(yq -r '.mounts[] | select(.type=="smb") | .user_profile' "$SHARE_CONFIG_FILE" | sort -u)

  for PROFILE in $PROFILES; do
    printf "Setup credential for profile ${C_CYAN:-}%s${C_RESET:-}, used by mounts:\n" "$PROFILE"
    yq -r --arg p "$PROFILE" \
      '.mounts[] | select(.user_profile==$p) | [.name, .source] | @tsv' \
      "$SHARE_CONFIG_FILE" | while IFS="$TAB" read -r NAME SOURCE; do
        printf '  - %s: %b%s%b\n' "$NAME" "${C_CYAN:-}" "$SOURCE" "${C_RESET:-}"
      done

    CRED_FILE="$CONST_CRED_DIR/${PROFILE}.cred"
    if [ ! -f "$CRED_FILE" ]; then
      printf "Username for %s: " "$PROFILE"
      read -r PROFILE_USER
      printf "Password for %s: " "$PROFILE"
      stty -echo; read -r PROFILE_PWD; stty echo; printf "\n"

      printf "username=%s\npassword=%s" "$PROFILE_USER" "$PROFILE_PWD" \
        | run_cmd systemd-creds encrypt --name="${PROFILE}.cred" /dev/stdin "$CRED_FILE"
    fi

    log_info "Credentials ready for profile: ${C_CYAN:-}$PROFILE${C_RESET:-}"
  done
}

## change_credentials
## Presents a numbered list of all SMB profiles from SHARE_CONFIG_FILE and prompts
## the user to select one, then collects a new username and password and
## re-encrypts the credential file. Restarts the SMB mount target afterwards.
change_credentials() {
  ARR_PROFILES=$(yq -r '.mounts[] | select(.type=="smb") | .user_profile' "$SHARE_CONFIG_FILE" | sort -u)

  i=1
  log_info "Select profile to update:"
  for PROFILE in $ARR_PROFILES; do
    printf "  %d) %s\n" "$i" "$PROFILE"
    i=$((i + 1))
  done

  printf "Choice: "
  read -r CHOICE
  PROFILE=$(printf '%s' "$ARR_PROFILES" | sed -n "${CHOICE}p")
  if [ -z "$PROFILE" ]; then
    log_error "Invalid choice: $CHOICE"
    return 1
  fi

  CRED_FILE="$CONST_CRED_DIR/${PROFILE}.cred"

  printf "New username for %s: " "$PROFILE"
  read -r PROFILE_USER
  printf "New password for %s: " "$PROFILE"
  stty -echo; read -r PROFILE_PWD; stty echo; printf "\n"

  printf "username=%s\npassword=%s" "$PROFILE_USER" "$PROFILE_PWD" \
    | run_cmd systemd-creds encrypt --name="${PROFILE}.cred" /dev/stdin "$CRED_FILE"

  log_info "Credentials updated for: $PROFILE"
  run_cmd systemctl daemon-reexec
  run_cmd systemctl restart smb-mounts.target
}

## =============================================================================
## Unit Enablement
## =============================================================================

## enable_restart_units_files
## Reads all mount entries from SHARE_CONFIG_FILE and calls systemctl enable on each
## generated unit file if it exists in CONST_UNIT_DIR. Also enables the SMB
## and NFS group targets as required.
enable_restart_units_files() {
  FLG_SMB=0
  FLG_NFS=0
  TMP_FILE=$(mktemp)

  ## Get all the share mount names
  yq -r '.mounts[].name' "$SHARE_CONFIG_FILE" > "$TMP_FILE"

  while read -r NAME; do
    ## Get all the share type and mount location for each mount name
    TYPE=$(yq -r ".mounts[] | select(.name==\"$NAME\") | .type" "$SHARE_CONFIG_FILE")
    TARGET=$(yq -r ".mounts[] | select(.name==\"$NAME\") | .target" "$SHARE_CONFIG_FILE")

    ## NFS and SMB have different systemd file extension
    if [ "$TYPE" = "smb" ]; then
      FLG_SMB=1
      UNIT_FILE=$(printf '%s' "$TARGET" | sed 's|^/||; s|/|-|g').service
    elif [ "$TYPE" = "nfs" ]; then
      FLG_NFS=1
      UNIT_FILE=$(printf '%s' "$TARGET" | sed 's|^/||; s|/|-|g').mount
    else
      log_warn "Skipping unknown type '$TYPE' for mount '$NAME'"
      continue
    fi

    ## Enable the unit files for each mount name. The mounting happens at the
    ## group level though
    if [ -f "$CONST_UNIT_DIR/$UNIT_FILE" ]; then
      run_cmd systemctl enable "$UNIT_FILE"
      log_info "Enabled unit: ${C_CYAN:-}${NAME}${C_RESET:-} (${C_GREEN:-}$UNIT_FILE${C_RESET:-})"
    else
      log_warn "Unit file not found, skipping enable: $UNIT_FILE"
    fi
  done < "$TMP_FILE"

  ## Enable and restart the group mounts, to mount the network shares.
  if [ "$FLG_SMB" -ne 0 ]; then
    run_cmd systemctl enable "$CONST_SMB_GROUP_FILE"
    run_cmd systemctl restart "$CONST_SMB_GROUP_FILE"
    log_info "Enabled & restarted group target for shares: ${C_CYAN:-}SMB${C_RESET:-}"
  fi
  if [ "$FLG_NFS" -ne 0 ]; then
    run_cmd systemctl enable "$CONST_NFS_GROUP_FILE"
    run_cmd systemctl restart "$CONST_NFS_GROUP_FILE"
    log_info "Enabled & restarted group target for shares: ${C_CYAN:-}NFS${C_RESET:-}"
  fi

  rm -f "$TMP_FILE"
}

## =============================================================================
## Share Removal
## =============================================================================

## remove_shares
## Disables, stops, and removes all systemd unit files managed by this script
## that are NOT defined in SHARE_CONFIG_FILE. A unit is considered managed by
## this script if its [Install] section contains WantedBy=smb-mounts.target or
## WantedBy=nfs-mounts.target.
##
## For each removed unit the function also:
##   - Unmounts the target path if it is currently mounted
##   - Removes the mount point directory if it is empty
##
## The SMB and NFS group target files are removed when no managed units remain
## for their respective type.
##
## In dry-run mode all actions are printed but nothing is changed.
remove_shares() {
  TMP_FILE=$(mktemp)
  TMP_KEEP=$(mktemp)

  ## Build the set of unit filenames that SHOULD exist according to the config
  yq -r '.mounts[].target' "$SHARE_CONFIG_FILE" > "$TMP_FILE" || {
    log_error "Failed to read targets from share config."
    rm -f "$TMP_FILE" "$TMP_KEEP"
    return 1
  }

  while read -r TARGET; do
    ## SMB units use .service, NFS units use .mount — derive both and store both
    ## so either type is protected from removal regardless of what is in the config
    TYPE=$(yq -r '.mounts[] | select(.target=="$TARGET") | .type' "$SHARE_CONFIG_FILE")
    UNIT_FILE=$(printf "%s" "$TARGET" | sed 's|^/||; s|/|-|g')
    if [ "$TYPE" = "smb" ]; then
      printf "%s\n" "${UNIT_FILE}.service" >> "$TMP_KEEP"
    else
      printf "%s\n" "${UNIT_FILE}.mount" >> "$TMP_KEEP"
    fi
  done < "$TMP_FILE"
  rm -f "$TMP_FILE"

  ## Track whether any SMB or NFS managed units survive so we know whether to
  ## remove the group target files at the end
  REMAINING_SMB=0
  REMAINING_NFS=0

  ## Scan every .service and .mount file in the unit directory
  for UNIT_PATH in "$CONST_UNIT_DIR"/*.service "$CONST_UNIT_DIR"/*.mount; do
    ## Skip glob non-matches (no files of that extension present)
    [ -f "$UNIT_PATH" ] || continue

    UNIT_FILE="${UNIT_PATH##*/}"

    ## Only act on units managed by this script — identified by WantedBy
    if ! grep -qE "WantedBy=(smb|nfs)-mounts\.target" "$UNIT_PATH" 2>/dev/null; then
      continue
    fi

    ## Determine the type of this managed unit
    if grep -q "WantedBy=smb-mounts.target" "$UNIT_PATH" 2>/dev/null; then
      UNIT_TYPE="smb"
    else
      UNIT_TYPE="nfs"
    fi

    ## Check if this unit is in the keep list
    if grep -qx "$UNIT_FILE" "$TMP_KEEP"; then
      ## Unit is still wanted — update the remaining counters
      if [ "$UNIT_TYPE" = "smb" ]; then REMAINING_SMB=1; fi
      if [ "$UNIT_TYPE" = "nfs" ]; then REMAINING_NFS=1; fi
      continue
    fi

    ## Unit is not in the config — derive the mount target path from the filename
    ## Reverse the name-to-filename transform: strip extension, replace - with /,
    ## re-add leading /
    MOUNT_TARGET="/$(printf '%s' "${UNIT_FILE%.*}" | sed 's|-|/|g')"

    log_info "Removing unit no longer in config: ${C_CYAN:-}${UNIT_FILE}${C_RESET:-}"

    ## Stop and disable the unit
    if [ "$FLG_DRYRUN" -eq 1 ]; then
      printf "${C_YELLOW:-}[dry-run]${C_RESET:-} systemctl disable --now %s\n" "$UNIT_FILE"
      printf "${C_YELLOW:-}[dry-run]${C_RESET:-} rm %s\n" "$UNIT_PATH"
    else
      run_cmd systemctl disable --now "$UNIT_FILE" 2>/dev/null || true
      run_cmd rm -f "$UNIT_PATH"
    fi

    ## Unmount and remove the mount point if it is empty
    if [ -d "$MOUNT_TARGET" ]; then
      if [ "$FLG_DRYRUN" -eq 1 ]; then
        printf "${C_YELLOW:-}[dry-run]${C_RESET:-} umount %s (if mounted)\n" "$MOUNT_TARGET"
        printf "${C_YELLOW:-}[dry-run]${C_RESET:-} rmdir %s (if empty)\n" "$MOUNT_TARGET"
      else
        run_cmd umount "$MOUNT_TARGET" 2>/dev/null || true
        ## rmdir only removes an empty directory; non-empty dirs are left alone
        run_cmd rmdir "$MOUNT_TARGET" 2>/dev/null || true
      fi
    fi

    log_ok "Removed: ${C_CYAN:-}${UNIT_FILE}${C_RESET:-}"
  done

  rm -f "$TMP_KEEP"

  ## Remove the SMB group target if no SMB units remain
  if [ "$REMAINING_SMB" -eq 0 ] && [ -f "$CONST_UNIT_DIR/$CONST_SMB_GROUP_FILE" ]; then
    log_info "No SMB units remain — removing group target: $CONST_SMB_GROUP_FILE"
    if [ "$FLG_DRYRUN" -eq 1 ]; then
      printf "${C_YELLOW:-}[dry-run]${C_RESET:-} systemctl disable --now %s
" "$CONST_SMB_GROUP_FILE"
      printf "${C_YELLOW:-}[dry-run]${C_RESET:-} rm %s
" "$CONST_UNIT_DIR/$CONST_SMB_GROUP_FILE"
    else
      run_cmd systemctl disable --now "$CONST_SMB_GROUP_FILE" 2>/dev/null || true
      run_cmd rm -f "$CONST_UNIT_DIR/$CONST_SMB_GROUP_FILE"
    fi
  fi

  ## Remove the NFS group target if no NFS units remain
  if [ "$REMAINING_NFS" -eq 0 ] && [ -f "$CONST_UNIT_DIR/$CONST_NFS_GROUP_FILE" ]; then
    log_info "No NFS units remain — removing group target: $CONST_NFS_GROUP_FILE"
    if [ "$FLG_DRYRUN" -eq 1 ]; then
      printf "${C_YELLOW:-}[dry-run]${C_RESET:-} systemctl disable --now %s
" "$CONST_NFS_GROUP_FILE"
      printf "${C_YELLOW:-}[dry-run]${C_RESET:-} rm %s
" "$CONST_UNIT_DIR/$CONST_NFS_GROUP_FILE"
    else
      run_cmd systemctl disable --now "$CONST_NFS_GROUP_FILE" 2>/dev/null || true
      run_cmd rm -f "$CONST_UNIT_DIR/$CONST_NFS_GROUP_FILE"
    fi
  fi

  run_cmd systemctl daemon-reload
  log_ok "Share removal complete."
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
## Three mutually exclusive operating modes are enforced after all flags are
## parsed:
##   Setup mode     --create-units and/or --create-creds (combinable)
##   Change mode    --change-creds (standalone)
##   Remove mode    --remove-shares (standalone)
##
## Combining a setup flag with --change-creds or --remove-shares, or combining
## --change-creds with --remove-shares, is an error. When no action flag is
## given the script defaults to setup mode and runs all setup steps.
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
      --parent-config)
        if [ -z "$VALUE" ]; then VALUE="$2"; shift; fi
        CONFIG_FILE="$VALUE"
        ;;
      --share-config)
        if [ -z "$VALUE" ]; then VALUE="$2"; shift; fi
        SHARE_CONFIG_FILE="$VALUE"
        ;;
      --logger)
        if [ -z "$VALUE" ]; then VALUE="$2"; shift; fi
        LOGGER_FILE="$VALUE"
        ;;
      --create-units)
        FLG_ACT_CREATE_UNITS=1
        ;;
      --create-creds)
        FLG_ACT_CREATE_CREDS=1
        ;;
      --change-creds)
        FLG_ACT_CHANGE_CREDS=1
        ;;
      --remove-shares)
        FLG_ACT_REMOVE_SHARES=1
        ;;
      --dry-run)
        FLG_DRYRUN=1
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

  ## Enforce mutual exclusion between operating modes
  SETUP_FLAGS=$((FLG_ACT_CREATE_UNITS + FLG_ACT_CREATE_CREDS))

  if [ "$SETUP_FLAGS" -gt 0 ] && [ "$FLG_ACT_CHANGE_CREDS" -eq 1 ]; then
    log_error "--change-creds cannot be combined with --create-units or --create-creds."
    log_error "Run setup and credential change as separate invocations."
    usage
    exit 1
  fi

  if [ "$SETUP_FLAGS" -gt 0 ] && [ "$FLG_ACT_REMOVE_SHARES" -eq 1 ]; then
    log_error "--remove-shares cannot be combined with --create-units or --create-creds."
    usage
    exit 1
  fi

  if [ "$FLG_ACT_CHANGE_CREDS" -eq 1 ] && [ "$FLG_ACT_REMOVE_SHARES" -eq 1 ]; then
    log_error "--change-creds and --remove-shares cannot be used together."
    usage
    exit 1
  fi
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

  ## Resolve the share config file path — exits if no file can be located
  find_share_config_file

  ## --change-creds mode — update credentials for an existing SMB profile
  if [ "$FLG_ACT_CHANGE_CREDS" -eq 1 ]; then
    log_banner "Network Shares — Update Credentials"
    log_step "Updating SMB credentials..."
    change_credentials
    log_ok "Credential update complete."
    return 0
  fi

  ## --remove-shares mode — remove units not defined in the share config
  if [ "$FLG_ACT_REMOVE_SHARES" -eq 1 ]; then
    log_banner "Network Shares — Remove Unlisted Shares"
    log_step "Removing shares not present in: $SHARE_CONFIG_FILE"
    remove_shares
    return 0
  fi

  ## Setup mode — create units and/or credentials.
  ## When no action flag was set both steps run; individual flags limit the run.
  RUN_SETUP_ALL=0
  if [ "$FLG_ACT_CREATE_UNITS" -eq 0 ] && [ "$FLG_ACT_CREATE_CREDS" -eq 0 ]; then
    RUN_SETUP_ALL=1
  fi

  log_banner "Network Shares Setup"
  install_cifs_nfs

  if [ "$RUN_SETUP_ALL" -eq 1 ] || [ "$FLG_ACT_CREATE_UNITS" -eq 1 ]; then
    log_step "Creating systemd unit files..."
    create_units
    enable_restart_units_files
  fi

  if [ "$RUN_SETUP_ALL" -eq 1 ] || [ "$FLG_ACT_CREATE_CREDS" -eq 1 ]; then
    log_step "Creating SMB credentials..."
    create_credentials
  fi

  log_ok "Network share setup complete."
}

main "$@"