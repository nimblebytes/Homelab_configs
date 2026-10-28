#!/bin/sh
# fix_usb_serial.sh
# Replace the Debian cloud kernel with the full kernel to enable USB serial support.
#
# Background:
#   Debian 13 cloud images ship linux-image-*-cloud-amd64, a stripped kernel with
#   no USB drivers. The fix is to install linux-image-amd64 and configure GRUB to
#   boot it by default.
#
#   grub-cloud-amd64 places kernel entries inside a submenu, making GRUB_DEFAULT
#   fragile to set. This script disables submenus first (GRUB_DISABLE_SUBMENU=y),
#   which flattens all entries to the top level so the entry title can be matched
#   directly — no submenu>entry ID parsing required.
#
# Usage:
#   sudo ./fix_usb_serial.sh [--diagnose | --fix | --all | --help]
#
# POSIX-compliant. Requires: sh, apt-get, update-grub, uname, awk, ls, mkdir

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_info()  { printf '[INFO]  %s\n' "$*"; }
log_warn() { printf '[WARN]  %s\n' "$*"; }
log_error()  { printf '[ERROR] %s\n' "$*" >&2; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)."
        exit 1
    fi
}

is_cloud_kernel() {
    case "$(uname -r)" in
        *-cloud-*) return 0 ;;
        *)         return 1 ;;
    esac
}

has_usb_modules() {
    USB_DIR="/lib/modules/$(uname -r)/kernel/drivers/usb"
    [ -d "$USB_DIR" ] && find "$USB_DIR" -name '*.ko*' 2>/dev/null | grep -q .
}

# ---------------------------------------------------------------------------
# Step 1 — Diagnose (read-only, no changes)
# ---------------------------------------------------------------------------

diagnose() {
    log_info "=== Diagnostic Report ==="
    log_info "Kernel version : $(uname -r)"

    if is_cloud_kernel; then
        log_info "Kernel type    : CLOUD (USB drivers omitted — this is the problem)"
    else
        log_info "Kernel type    : FULL"
    fi

    if has_usb_modules; then
        log_info "USB modules    : Present on disk"
    else
        log_info "USB modules    : Not found on disk (expected on cloud kernel)"
    fi

    log_info "--- Installed kernel packages ---"
    dpkg -l 'linux-image-*' | grep '^ii' || log_info "None found"

    log_info "--- GRUB configuration ---"
    if [ -f /etc/default/grub ]; then
        grep 'GRUB_DEFAULT\|GRUB_DISABLE_SUBMENU' /etc/default/grub \
            || log_info "No relevant GRUB settings found"
    fi
    if [ -d /etc/default/grub.d ]; then
        log_info "--- /etc/default/grub.d drop-ins ---"
        ls /etc/default/grub.d/ 2>/dev/null || log_info "Empty"
        for f in /etc/default/grub.d/*.cfg; do
            [ -f "$f" ] && log_info "  $f:" && cat "$f"
        done
    fi

    log_info "--- Serial device nodes ---"
    ls /dev/ttyUSB* /dev/ttyACM* /dev/serial 2>/dev/null || log_info "None found"

    log_info "=== End Diagnostic ==="
    return 0
}

# ---------------------------------------------------------------------------
# Step 2 — Install the full kernel
# ---------------------------------------------------------------------------

install_full_kernel() {
    log_info "=== Installing full kernel ==="

    if has_usb_modules; then
        log_info "USB driver modules already present. Skipping kernel install."
        return 0
    fi

    if ! is_cloud_kernel; then
        log_warn "Not a cloud kernel but USB modules missing — unexpected state."
        log_warn "Proceeding with install attempt."
    fi

    log_info "Cloud kernel detected: $(uname -r)"
    log_info "Updating package lists..."
    if ! apt-get update -qq; then
        log_error "apt-get update failed. Check your network and apt sources, then re-run."
        return 1
    fi

    log_info "Installing linux-image-amd64..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-amd64; then
        log_error "Failed to install linux-image-amd64. Check apt output above, then re-run."
        return 1
    fi

    log_info "Full kernel package installed."
    return 0
}

# ---------------------------------------------------------------------------
# Step 3 — Configure GRUB to boot the full kernel by default
#
# Strategy (from Gemini's approach, which works correctly):
#   1. Write GRUB_DISABLE_SUBMENU=y to a grub.d drop-in.
#      This flattens all kernel entries to the top level, eliminating the
#      submenu>entry ID complexity that grub-cloud-amd64 introduces.
#   2. Run update-grub to regenerate grub.cfg with the flat layout.
#   3. Find the new kernel version from /boot/vmlinuz-* (non-cloud, newest).
#   4. Extract the exact menu entry title for that version using awk + index(),
#      which does a literal string match — safe against '+' in version strings
#      that would break regex-based matching.
#   5. Write GRUB_DEFAULT="<title>" to a grub.d drop-in.
#   6. Run update-grub a final time to bake the default into grub.cfg.
# ---------------------------------------------------------------------------

update_bootloader() {
    log_info "=== Updating bootloader ==="

    GRUB_D_DIR="/etc/default/grub.d"
    log_info "Creating GRUB drop-in directory: ${GRUB_D_DIR}"
    if ! mkdir -p "$GRUB_D_DIR"; then
        log_error "Failed to create ${GRUB_D_DIR}."
        return 1
    fi

    # Step 3a — disable submenus so all entries are at the top level
    log_info "Disabling GRUB submenus to flatten menu layout..."
    if ! printf 'GRUB_DISABLE_SUBMENU=y\n' > "${GRUB_D_DIR}/99-disable-submenus.cfg"; then
        log_error "Failed to write ${GRUB_D_DIR}/99-disable-submenus.cfg."
        return 1
    fi

    # Step 3b — first update-grub to regenerate flat layout
    log_info "Running update-grub (first pass — flatten menu)..."
    if ! update-grub 2>&1; then
        log_error "update-grub failed. Check output above."
        return 1
    fi

    # Step 3c — find the newest non-cloud kernel version in /boot
    log_info "Identifying new full kernel version..."
    NEW_KVER=$(ls -1 /boot/vmlinuz-* 2>/dev/null \
        | awk -F'/boot/vmlinuz-' '{print $2}' \
        | grep -v 'cloud' \
        | sort -V \
        | tail -1)

    if [ -z "$NEW_KVER" ]; then
        log_error "Could not find a non-cloud kernel in /boot."
        log_error "Ensure linux-image-amd64 installed correctly and try again."
        return 1
    fi

    log_info "Found full kernel version: ${NEW_KVER}"

    # Step 3d — extract exact menu entry title using literal string match
    # awk index() is used instead of regex to safely handle '+' in version strings
    log_info "Extracting GRUB menu entry title for ${NEW_KVER}..."
    MENU_ENTRY=$(awk -F"'" -v ver="$NEW_KVER" '
        /^[[:space:]]*menuentry / && index($0, ver) > 0 {
            print $2
            exit
        }
    ' /boot/grub/grub.cfg)

    if [ -z "$MENU_ENTRY" ]; then
        log_error "Could not find a GRUB menu entry for kernel ${NEW_KVER} in /boot/grub/grub.cfg."
        log_error "Run: grep 'menuentry' /boot/grub/grub.cfg"
        return 1
    fi

    log_info "Found menu entry: '${MENU_ENTRY}'"

    # Step 3e — write GRUB_DEFAULT drop-in with the exact entry title
    log_info "Writing GRUB default drop-in..."
    if ! printf 'GRUB_DEFAULT="%s"\n' "$MENU_ENTRY" \
            > "${GRUB_D_DIR}/99-set-standard-kernel.cfg"; then
        log_error "Failed to write ${GRUB_D_DIR}/99-set-standard-kernel.cfg."
        return 1
    fi

    # Step 3f — final update-grub to bake the default into grub.cfg
    log_info "Running update-grub (second pass — set default)..."
    if ! update-grub 2>&1; then
        log_error "Final update-grub failed. Check output above."
        return 1
    fi

    # Verify
    APPLIED=$(grep "set default=" /boot/grub/grub.cfg \
        | grep -v 'next_entry' | head -1)
    log_info "GRUB default is now: ${APPLIED}"
    log_info "System will boot '${MENU_ENTRY}' on next restart."
    return 0
}

# ---------------------------------------------------------------------------
# Step 4 — Add user to dialout group
# ---------------------------------------------------------------------------

add_dialout() {
    log_info "=== Configuring dialout group ==="
    TARGET_USER="${SUDO_USER:-}"

    if [ -z "$TARGET_USER" ]; then
        log_warn "SUDO_USER not set — cannot determine non-root user."
        log_warn "After rebooting, run:  sudo usermod -aG dialout <your_username>"
        return 0
    fi

    if id -nG "$TARGET_USER" | grep -qw dialout; then
        log_info "User '${TARGET_USER}' is already in the dialout group."
        return 0
    fi

    if usermod -aG dialout "$TARGET_USER"; then
        log_info "Added '${TARGET_USER}' to dialout (takes effect after reboot)."
        return 0
    else
        log_error "Failed to add '${TARGET_USER}' to dialout."
        log_error "After rebooting, run:  sudo usermod -aG dialout ${TARGET_USER}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# run_fix — strict chain; each step must succeed before the next runs
# ---------------------------------------------------------------------------

run_fix() {
    require_root

    install_full_kernel
    if [ $? -ne 0 ]; then
        log_error "Kernel installation failed — stopping. Fix the log_errorors above and re-run."
        return 1
    fi

    update_bootloader
    if [ $? -ne 0 ]; then
        log_error "Bootloader update failed — stopping."
        log_error "Do NOT reboot until the bootloader is correctly configured."
        return 1
    fi

    # dialout is independent of booting — failure is non-fatal
    add_dialout

    log_info ""
    log_info "========================================================="
    log_info "  Kernel installed and GRUB updated successfully."
    log_info "  The old cloud kernel was NOT removed (safe fallback)."
    log_info ""
    log_info "  Reboot now:  sudo reboot"
    log_info ""
    log_info "  After rebooting, verify:"
    log_info "    uname -r          (must NOT contain 'cloud')"
    log_info "    lsmod | grep -E 'cdc_acm|ftdi_sio|cp210x|ch341'"
    log_info "    ls /dev/ttyUSB* /dev/ttyACM*"
    log_info ""
    log_info "  If the VM fails to boot, select the cloud kernel from"
    log_info "  the GRUB menu via your hypervisor's console to recover."
    log_info "========================================================="
    return 0
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Options:
  --diagnose    Report kernel type, GRUB config, and device state (no changes)
  --fix         Install full kernel and configure GRUB (reboot required)
  --all         Diagnose then fix (default)
  --help        Show this help

Note:
  A reboot is required after --fix or --all.
  USB passthrough must also be configured in your hypervisor separately.

Examples:
  sudo $(basename "$0") --diagnose
  sudo $(basename "$0") --fix
  sudo $(basename "$0") --all
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    ACTION="${1:---all}"
    case "$ACTION" in
        --diagnose)
            diagnose
            ;;
        --fix)
            require_root
            run_fix
            ;;
        --all)
            require_root
            diagnose
            log_info ""
            run_fix
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: ${ACTION}"
            usage
            exit 1
            ;;
    esac
}

main "$@"