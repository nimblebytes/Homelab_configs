#!/bin/sh
# =============================================================================
# fix_dns_search_in_cloud-init_vm.sh
# Checks if a running VM has the DNS search string (DHCP option 119) fix 
# applied, and patches it if needed. 
# To patch a VM Template used: https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/proxmox/create_pve_template.sh
#
# Usage:
#   ./fix_dns_search_in_cloud-init_vm.sh [--dry-run] [--help]
#
# Options:
#   --dry-run   Check only; do not apply any changes
#   --help      Show this help message
#
# Requirements:
#   - Must run as root (or with sudo)
#   - Target is the local machine (run inside the VM or via SSH)
#   - For cloud-init based debian VM. Not designed for normal desktop 
#     installation
# =============================================================================
# END_USAGE

set -eu

# --- Config ------------------------------------------------------------------

DROPIN_DIR="/etc/systemd/network/10-netplan-eth0.network.d"
DROPIN_FILE="${DROPIN_DIR}/10-dhcp-options.conf"

DROPIN_CONTENT='# Customization - Ensure DNS search string (option 119) is requested when using DHCP
[DHCPv4]
UseDNS=yes
UseDomains=yes
#RequestOptions=119

[DHCPv6]
UseDNS=yes
UseDomains=yes
'

# --- Helpers -----------------------------------------------------------------

log_info()    { printf '[INFO ]  %s\n' "$*"; }
log_ok()      { printf '[OK   ]    %s\n' "$*"; }
log_warn()    { printf '[WARN ]  %s\n' "$*"; }
log_changed() { printf '[APPLY] %s\n' "$*"; }
log_skip()    { printf '[SKIP ]  %s\n' "$*"; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    ## Extract the usage section from the script header, up till the flag.
    sed -n '/^# ====/,/^# END_USAGE/{ /^#!/d; /^# ====/d; /^# END_USAGE/d; s/^# \?//; p }' "$0"
    exit 0
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

# --- Cloud-init detection ----------------------------------------------------

is_cloud_init_image() {
    detected=0

    # 1. cloud-init package is installed
    if command -v cloud-init > /dev/null 2>&1; then
        log_info "  - cloud-init binary present"
        detected=1
    fi

    # 2. cloud-init systemd units exist
    if systemctl list-units --all --no-legend 'cloud-init*' 2>/dev/null | grep -q 'cloud-init'; then
        log_info "  - cloud-init systemd units found"
        detected=1
    fi

    # 3. /etc/cloud directory exists with config
    if [ -d /etc/cloud ]; then
        log_info "  - /etc/cloud directory exists"
        detected=1
    fi

    # 4. /var/lib/cloud exists (populated on first boot)
    if [ -d /var/lib/cloud ]; then
        log_info "  - /var/lib/cloud state directory exists"
        detected=1
    fi

    # 5. Seed directory or datasource hints
    if [ -f /var/lib/cloud/instance/datasource ]; then
        ds=$(cat /var/lib/cloud/instance/datasource 2>/dev/null || true)
        log_info "  - datasource: ${ds}"
        detected=1
    fi

    if [ "${detected}" -eq 1 ]; then
        return 0
    else
        log_warn "No cloud-init indicators found. This may not be a cloud image."
        log_warn "Continuing anyway — patch is safe to apply on any systemd-networkd system."
        return 1
    fi
}

# --- Patch logic -------------------------------------------------------------

dropin_is_current() {
    if [ ! -f "${DROPIN_FILE}" ]; then
        return 1
    fi
    diff - "${DROPIN_FILE}" > /dev/null 2>&1 << EOF
${DROPIN_CONTENT}
EOF
}

apply_patch() {
    dry_run="${1}"

    if [ "${dry_run}" = "true" ]; then
        log_skip "Dry-run mode — would create: ${DROPIN_FILE}"
        return 0
    fi

    install -d -m 755 "${DROPIN_DIR}"
    printf '%s' "${DROPIN_CONTENT}" > "${DROPIN_FILE}"
    chmod 644 "${DROPIN_FILE}"
    log_changed "Drop-in written: ${DROPIN_FILE}"

    # Reload networkd if it is active
    if systemctl is-active --quiet systemd-networkd; then
        if networkctl reload > /dev/null 2>&1; then
            log_changed "systemd-networkd reloaded."
        else
            log_warn "networkctl reload failed — you may need to reboot."
        fi
    else
        log_warn "systemd-networkd is not active; no reload performed."
    fi
}

# --- Main --------------------------------------------------------------------

main() {
    dry_run="false"

    for arg in "$@"; do
        case "${arg}" in
            --dry-run) dry_run="true" ;;
            --help|-h) usage ;;
            *) log_error "Unknown argument: ${arg}"; exit 1 ;;
        esac
    done

    require_root

    printf '============================================================\n'
    printf ' DNS Search String (DHCP option 119) Patch Checker\n'
    printf '============================================================\n'

    # --- Cloud-init check ---
    printf '\n--- Cloud-init detection ---\n'
    if is_cloud_init_image; then
        log_info "Cloud-init image detected."
    fi

    # --- Patch status ---
    printf '\n--- Drop-in config check ---\n'
    log_info "Target: ${DROPIN_FILE}"

    if dropin_is_current; then
        log_ok "Patch already applied — no changes needed."
        printf '\nResult: ALREADY PATCHED\n'
        exit 0
    fi

    if [ -f "${DROPIN_FILE}" ]; then
        log_warn "Drop-in exists but content differs — will overwrite."
    else
        log_info "Drop-in not found — will create."
    fi

    printf '\n--- Applying patch ---\n'
    apply_patch "${dry_run}"

    printf '\n'
    if [ "${dry_run}" = "true" ]; then
        printf 'Result: DRY-RUN — no changes were made.\n'
    else
        printf 'Result: PATCHED — DNS search string fix has been applied.\n'
    fi
}

main "$@"