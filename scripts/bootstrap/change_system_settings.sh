#!/bin/sh
## =============================================================================
## change_system_settings.sh — Interactive System Configuration
## POSIX-compliant. Downloaded and run by bootstrap.sh via run_script.
##
## Presents a dialog menu for hostname, IP address, DNS, and timezone.
## Reads current live values on entry; holds edits in pending variables until
## the user selects "Apply". On apply, writes config values and applies them
## to the running system. Selecting "Cancel" or pressing ESC discards all
## pending changes without modifying the system.
##
## Usage: change_system_settings.sh [OPTIONS]
##   --config-file <file>   Path to the shared bootstrap config env file
##                          (default: value of CONFIG_FILE env variable)
##   --logger <file>        (Optional) Path to logger for pretty log output
##                          (default: value of LOGGER_FILE env variable)
##   --help                 Show this help message
##
## Environment variables (set automatically when called by bootstrap.sh):
##   CONFIG_FILE          — path to the shared mode-600 config env file
##   LOGGER_FILE          — path to logging helper script
## =============================================================================

set -eu

## =============================================================================
## Constants And Defaults
## =============================================================================
CONFIG_FILE="${CONFIG_FILE:-}"
LOGGER_FILE="${LOGGER_FILE:-}"

DIALOG_HEIGHT=20
DIALOG_WIDTH=70

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
Usage: $(basename "$0") [OPTIONS]

Interactively configure system settings: hostname, IP address, DNS, timezone.
Called automatically by bootstrap.sh when "system" is selected. Can also be
run standalone.

Options:
  --config-file <file>   Path to the shared bootstrap config env file
  --logger <file>        Path to better_logs.sh
  --help                 Show this help message and exit

Environment variables (used when flags are not provided):
  CONFIG_FILE         Shared bootstrap config env file
  LOGGER_FILE         Path to better_logs.sh

Exit codes:
  0  Success (including cancel — no changes is not an error)
  1  Fatal error
EOF
}

## =============================================================================
## Loader got a external Logger helper
## Sources better_logs.sh if available. Falls back silently to the stubs above.
## =============================================================================
load_logger(){

  if [ -f "${LOGGER_FILE:-}" ]; then 
    log_info "Attempting to load logger: ${LOGGER_FILE}..."
    . $LOGGER_FILE

    ## Re-assert LOG_FILE so the sourced library picks up our path
    LOG_FILE="$LOG_FILE"

    if log_file_init; then 
      log_ok "Logger: ${LOGGER_FILE} loaded successfully."
    else
      log_warn "Logger: ${LOGGER_FILE} loaded, but the log file failed to initialize. Logging to file is disabled.\n"
    fi
  fi
}

## =============================================================================
## Config File Helper
## =============================================================================
## write_cfg appends a key="value" line to CONFIG_FILE.
write_cfg() { printf '%s="%s"\n' "$1" "$2" >> "$CONFIG_FILE"; }

## =============================================================================
## Dialog Helpers
## =============================================================================

## dialog_menu <TITLE> <PROMPT> <MENU_HEIGHT> <TAG> <ITEM> ...
dialog_menu() {
  TITLE="$1"; PROMPT="$2"; MENU_HEIGHT="$3"; shift 3
  dialog --erase-on-exit \
    --title "$TITLE" \
    --menu "$PROMPT" \
    $DIALOG_HEIGHT $DIALOG_WIDTH "$MENU_HEIGHT" \
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

## dialog_msgbox <TITLE> <MESSAGE>
dialog_msgbox() {
  dialog --erase-on-exit \
    --title "$1" \
    --msgbox "$2" \
    10 $DIALOG_WIDTH \
    3>&1 1>&2 2>&3
}

## =============================================================================
## IP Mode Detection
## =============================================================================
## detect_ip_mode — sets DETECTED_IFACE, DETECTED_IP, DETECTED_PREFIX,
## DETECTED_GATEWAY, and DETECTED_IP_MODE ("dhcp" or "static").
## Checks /etc/network/interfaces first (ifupdown/Debian), then falls back to
## NetworkManager (nmcli) and systemd-networkd.
detect_ip_mode() {
  ## Find the first non-loopback interface that has a global IPv4 address
  DETECTED_IFACE="$(ip -4 addr show scope global \
    | awk '/^[0-9]+:/{iface=substr($2,1,length($2)-1)} /inet /{print iface; exit}' \
    2>/dev/null || printf '')"

  DETECTED_IP="$(ip -4 addr show scope global \
    | awk '/inet /{split($2,a,"/"); print a[1]; exit}' \
    2>/dev/null || printf '')"

  DETECTED_PREFIX="$(ip -4 addr show scope global \
    | awk '/inet /{split($2,a,"/"); print a[2]; exit}' \
    2>/dev/null || printf '24')"

  DETECTED_GATEWAY="$(ip -4 route show default \
    | awk '{print $3; exit}' 2>/dev/null \
    || printf '')"

  DETECTED_IP_MODE="dhcp"

  ## ── ifupdown (/etc/network/interfaces) ──────────────────────────────────
  if [ -f /etc/network/interfaces ] && [ -n "$DETECTED_IFACE" ]; then
    if grep -qE "^iface ${DETECTED_IFACE} inet static" /etc/network/interfaces 2>/dev/null; then
      DETECTED_IP_MODE="static"
      return 0
    fi
    ## Also check /etc/network/interfaces.d/ drop-ins
    IFACES_D="/etc/network/interfaces.d"
    if [ -d "$IFACES_D" ]; then
      for F in "${IFACES_D}"/*; do
        if [ -f "$F" ] && grep -qE "^iface ${DETECTED_IFACE} inet static" "$F" 2>/dev/null; then
          DETECTED_IP_MODE="static"
          return 0
        fi
      done
    fi
  fi

  ## ── NetworkManager (nmcli) ───────────────────────────────────────────────
  if command -v nmcli >/dev/null 2>&1 && [ -n "$DETECTED_IFACE" ]; then
    NM_METHOD="$(nmcli -g IP4.METHOD device show "$DETECTED_IFACE" 2>/dev/null \
      || printf '')"
    if [ "$NM_METHOD" = "manual" ]; then
      DETECTED_IP_MODE="static"
      return 0
    fi
  fi

  ## ── systemd-networkd (.network files) ───────────────────────────────────
  for NF in /etc/systemd/network/*.network /run/systemd/network/*.network; do
    if [ -f "$NF" ] && grep -qi "DHCP=no" "$NF" 2>/dev/null; then
      DETECTED_IP_MODE="static"
      return 0
    fi
  done

  DETECTED_IP_MODE="dhcp"
}

## =============================================================================
## System Info Collection
## =============================================================================
## collect_system_info — interactive menu for hostname, IP, DNS, and timezone.
##
## Reads current live values on entry, including whether the IP is DHCP or
## static. Each menu item shows the setting name and its current pending value.
## Selecting an item prompts for a new value held in a pending variable.
## Nothing is written until the user selects "Apply". "Cancel" or ESC discards
## all pending changes and returns without modifying anything.
##
## If the IP is currently DHCP and the user edits the IP field, the mode is
## automatically switched to static and prefix/gateway are also collected.
## apply_static_ip is then called from apply_system_settings.
collect_system_info() {
  log_step "Collecting system / identity information..."

  ## Detect current interface, IP, prefix, gateway, and DHCP/static mode
  detect_ip_mode

  ## Initialise pending state from live values
  PENDING_HOSTNAME="$(hostname 2>/dev/null || printf '')"
  PENDING_TIMEZONE="$(cat /etc/timezone 2>/dev/null \
    || timedatectl show --property=Timezone --value 2>/dev/null \
    || printf 'UTC')"
  PENDING_DNS="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null \
    || printf '')"
  PENDING_IP="$DETECTED_IP"
  PENDING_PREFIX="$DETECTED_PREFIX"
  PENDING_GATEWAY="$DETECTED_GATEWAY"
  PENDING_IP_MODE="$DETECTED_IP_MODE"
  PENDING_IFACE="$DETECTED_IFACE"

  ## Loop until the user explicitly applies or cancels
  while true; do
    ## Build the IP label showing current mode alongside the address
    IP_LABEL="IP  [${PENDING_IP_MODE}]  :  ${PENDING_IP}/${PENDING_PREFIX}"

    CHOICE=$(dialog_menu \
      "System Settings" \
      "Select a setting to edit, then choose Apply to save." \
      6 \
      "hostname" "Hostname  :  ${PENDING_HOSTNAME}" \
      "ip"       "${IP_LABEL}"                       \
      "dns"      "DNS       :  ${PENDING_DNS}"        \
      "timezone" "Timezone  :  ${PENDING_TIMEZONE}"   \
      "apply"    "Apply changes and continue"          \
      "cancel"   "Cancel — discard all changes"        \
    ) || CHOICE="cancel"

    case "$CHOICE" in
      hostname)
        INPUT=$(dialog_inputbox \
          "Hostname" \
          "Enter the desired hostname:" \
          "$PENDING_HOSTNAME") || true
        [ -n "$INPUT" ] && PENDING_HOSTNAME="$INPUT"
        ;;
      ip)
        if [ "$PENDING_IP_MODE" = "dhcp" ]; then
          ## Warn the user that editing the IP will switch to static
          dialog_msgbox "IP Mode Change" \
            "This interface is currently using DHCP.\n\nEditing the IP address will switch it to a static configuration.\nYou will also be asked for the subnet prefix and gateway."
        fi

        INPUT=$(dialog_inputbox \
          "IP Address" \
          "Enter the IP address (e.g. 192.168.1.100):" \
          "$PENDING_IP") || true

        if [ -n "$INPUT" ]; then
          PENDING_IP="$INPUT"

          ## Collect prefix and gateway whenever the IP is edited,
          ## regardless of the original mode
          PREFIX_INPUT=$(dialog_inputbox \
            "Subnet Prefix" \
            "Enter the subnet prefix length (e.g. 24 for /24):" \
            "$PENDING_PREFIX") || true
          [ -n "$PREFIX_INPUT" ] && PENDING_PREFIX="$PREFIX_INPUT"

          GW_INPUT=$(dialog_inputbox \
            "Gateway" \
            "Enter the default gateway address (e.g. 192.168.1.1):" \
            "$PENDING_GATEWAY") || true
          [ -n "$GW_INPUT" ] && PENDING_GATEWAY="$GW_INPUT"

          ## Switch mode to static if it was previously DHCP
          if [ "$PENDING_IP_MODE" = "dhcp" ]; then
            PENDING_IP_MODE="static"
            log_info "IP mode changed from dhcp to static for interface $PENDING_IFACE"
          fi
        fi
        ;;
      dns)
        INPUT=$(dialog_inputbox \
          "DNS Server" \
          "Enter the primary DNS server address (e.g. 1.1.1.1):" \
          "$PENDING_DNS") || true
        [ -n "$INPUT" ] && PENDING_DNS="$INPUT"
        ;;
      timezone)
        INPUT=$(dialog_inputbox \
          "Timezone" \
          "Enter the system timezone (e.g. Europe/Berlin):" \
          "$PENDING_TIMEZONE") || true
        [ -n "$INPUT" ] && PENDING_TIMEZONE="$INPUT"
        ;;
      apply)
        ## Write all pending values to the config file in one go
        write_cfg VM_HOSTNAME  "$PENDING_HOSTNAME"
        write_cfg VM_TIMEZONE  "$PENDING_TIMEZONE"
        write_cfg VM_DNS       "$PENDING_DNS"
        write_cfg VM_IP        "$PENDING_IP"
        write_cfg VM_PREFIX    "$PENDING_PREFIX"
        write_cfg VM_GATEWAY   "$PENDING_GATEWAY"
        write_cfg VM_IP_MODE   "$PENDING_IP_MODE"
        write_cfg VM_IFACE     "$PENDING_IFACE"
        log_info "System settings saved — hostname=${PENDING_HOSTNAME} ip=${PENDING_IP}/${PENDING_PREFIX} gw=${PENDING_GATEWAY} dns=${PENDING_DNS} tz=${PENDING_TIMEZONE} mode=${PENDING_IP_MODE}"
        return 0
        ;;
      cancel)
        log_info "System settings unchanged — changes discarded."
        return 0
        ;;
    esac
  done
}

## =============================================================================
## Apply System Settings
## =============================================================================
## apply_system_settings — sources the config file and applies all collected
## values to the running system: hostname, timezone, and static IP if changed.
apply_system_settings() {
  if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    log_warn "apply_system_settings: CONFIG_FILE not set or not found — skipping apply."
    return 1
  fi

  . "$CONFIG_FILE"

  if [ -n "${VM_HOSTNAME:-}" ]; then
    log_info "Setting hostname to: $VM_HOSTNAME"
    if ! hostnamectl set-hostname "$VM_HOSTNAME" 2>/dev/null; then
      echo "$VM_HOSTNAME" > /etc/hostname
    fi
  fi

  if [ -n "${VM_TIMEZONE:-}" ]; then
    log_info "Setting timezone: $VM_TIMEZONE"
    if ! timedatectl set-timezone "$VM_TIMEZONE" 2>/dev/null; then
      ln -sf "/usr/share/zoneinfo/$VM_TIMEZONE" /etc/localtime
    fi
  fi

  ## Apply static IP if the user switched from DHCP during collection
  if [ "${VM_IP_MODE:-}" = "static" ]; then
    if ! apply_static_ip; then
      log_warn "Static IP configuration failed — network settings may be unchanged."
    fi
  fi
}

## =============================================================================
## Apply Static IP
## =============================================================================
## apply_static_ip — configures a static IPv4 address on VM_IFACE.
##
## Tries /etc/network/interfaces (ifupdown) first, then nmcli (NetworkManager).
## Called from apply_system_settings when VM_IP_MODE is "static".
apply_static_ip() {
  if [ "${VM_IP_MODE:-}" != "static" ]; then return 0; fi
  if [ -z "${VM_IFACE:-}" ]; then
    log_warn "apply_static_ip: no interface recorded — skipping."
    return 1
  fi

  log_step "Applying static IP ${VM_IP}/${VM_PREFIX} gw ${VM_GATEWAY} on ${VM_IFACE}..."

  ## ── ifupdown path (/etc/network/interfaces) ─────────────────────────────
  if [ -f /etc/network/interfaces ]; then
    IFACES_FILE="/etc/network/interfaces"
    IFACES_BACKUP="${IFACES_FILE}.bak.$(date '+%Y%m%d%H%M%S')"

    log_info "Backing up $IFACES_FILE to $IFACES_BACKUP"
    cp "$IFACES_FILE" "$IFACES_BACKUP"

    ## Remove any existing stanza for this interface, then append a static one.
    ## The awk script deletes lines from "iface <IFACE>" up to the next blank
    ## line or next "iface" keyword so partial configs are cleanly replaced.
    awk -v iface="$VM_IFACE" '
      /^iface[[:space:]]/ && $2 == iface { skip=1 }
      skip && (/^$/ || (/^iface[[:space:]]/ && $2 != iface)) { skip=0 }
      !skip { print }
    ' "$IFACES_BACKUP" > "$IFACES_FILE"

    ## Append the new static stanza
    printf '\nauto %s\niface %s inet static\n  address %s/%s\n  gateway %s\n' \
      "$VM_IFACE" "$VM_IFACE" "$VM_IP" "$VM_PREFIX" "$VM_GATEWAY" \
      >> "$IFACES_FILE"

    ## Write DNS into /etc/resolv.conf if a DNS value was set
    if [ -n "${VM_DNS:-}" ]; then
      log_info "Writing DNS $VM_DNS to /etc/resolv.conf"
      printf 'nameserver %s\n' "$VM_DNS" > /etc/resolv.conf
    fi

    ## Bring the interface down then up to apply the change
    log_info "Restarting interface $VM_IFACE"
    if command -v ifdown >/dev/null 2>&1; then
      ifdown "$VM_IFACE" 2>/dev/null || true
      ifup   "$VM_IFACE" 2>/dev/null || true
    else
      ip link set "$VM_IFACE" down 2>/dev/null || true
      ip addr flush dev "$VM_IFACE" 2>/dev/null || true
      ip addr add "${VM_IP}/${VM_PREFIX}" dev "$VM_IFACE" 2>/dev/null || true
      ip link set "$VM_IFACE" up 2>/dev/null || true
      ip route add default via "$VM_GATEWAY" 2>/dev/null || true
    fi

    log_ok "Static IP applied via ifupdown on $VM_IFACE"
    return 0
  fi

  ## ── NetworkManager path (nmcli) ─────────────────────────────────────────
  if command -v nmcli >/dev/null 2>&1; then
    CON_NAME="static-${VM_IFACE}"

    log_info "Configuring static IP via NetworkManager connection: $CON_NAME"

    ## Delete any existing connection for this interface to start clean
    nmcli connection delete "$CON_NAME" 2>/dev/null || true

    nmcli connection add \
      type ethernet \
      con-name "$CON_NAME" \
      ifname "$VM_IFACE" \
      ipv4.method manual \
      ipv4.addresses "${VM_IP}/${VM_PREFIX}" \
      ipv4.gateway "$VM_GATEWAY" \
      ipv4.dns "${VM_DNS:-}" \
      connection.autoconnect yes

    nmcli connection up "$CON_NAME"
    log_ok "Static IP applied via NetworkManager on $VM_IFACE"
    return 0
  fi

  log_error "apply_static_ip: no supported network manager found (ifupdown or nmcli required)."
  return 1
}

## =============================================================================
## Parameter Parsing
## Supports long flags only. Both "--flag value" and "--flag=value" are accepted.
## =============================================================================
parse_args() {
  while [ $# -gt 0 ]; do
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
      --config-file)
        if [ -z "$VALUE" ]; then
          VALUE="$2"
          shift
        fi
        CONFIG_FILE="$VALUE"
        ;;
      --logger)
        if [ -z "$VALUE" ]; then
          VALUE="$2"
          shift
        fi
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
  load_logger

  if [ -z "$CONFIG_FILE" ]; then
    log_error "CONFIG_FILE is not set. Pass --config-file or set the environment variable."
    exit 1
  fi

  collect_system_info
  apply_system_settings
}

main "$@"