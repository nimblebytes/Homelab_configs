#!/bin/sh

## =============================================================================
## Script Name: create_pve_template.sh
## Description: Creates a PVE template with the embedded default parameters
##  - Possible inputs: OS Image, template name, template number
##
## Author: nimblebytes (GitHub)
## =============================================================================

# set -x

## Default values that can be changed
DEF_USER_NAME=john
DEF_PASSWORD=password
DEF_NAME_SERVER="1.1.1.1"  # Only a single IP address can be given 
DEF_SEARCH_DOMAIN="example.internal"
DEF_NETWORK_BRIDGE0=vmbr32
DEF_TEMPLATE_NUM=9000
DEF_OS_IMAGE="debian-13-genericcloud-amd64.qcow2"
DEF_AUTHORISED_SSH_KEYS="/root/.ssh/cloud_init_authorized_keys"

LOG_LEVEL=INFO    ## Options: DEBUG; INFO; STEP; OK; WARN; ERROR


## Variables used in the script
PATH_DIR_ISO=/var/lib/vz/template/iso           ## The location depends on the configuration of Proxmox 
PATH_DIR_VM_CONFIG=/etc/pve/qemu-server

PATH_OS=
TEMPLATE_NUM=${DEF_TEMPLATE_NUM}
TEMPLATE_NAME=
FLAG_OVERWRITE=0

FLAG_IMAGE=1
FLAG_NUMBER=2
FLAG_NAME=4
FLAG_PARSED=0
FLG_VERBOSE=0

## Resolve directory of this script (POSIX safe)
SCRIPT_DIR=$(dirname "$(realpath "$0")")
SCRIPT_NAME=${0##*/}

## Load external function library if the file exists
if [ -r "${SCRIPT_DIR}/better_logs.sh" ]; then 
  . "${SCRIPT_DIR}/better_logs.sh"
else
  printf "Warning: better_logs.sh not found, using fallback logging.\n" >&2
fi

## =============================================================================
## Fallback Logging
## These simple stubs are active until better_logs.sh is sourced.
## Once sourced, its definitions silently replace these.
## =============================================================================
command -v log_debug   >/dev/null 2>&1  || log_debug()   { printf '[DEBUG] %s\n' "$*"; }
command -v log_info    >/dev/null 2>&1  || log_info()    { printf '[INFO]  %s\n' "$*"; }
command -v log_step    >/dev/null 2>&1  || log_step()    { printf '[STEP]  %s\n' "$*"; }
command -v log_ok      >/dev/null 2>&1  || log_ok()      { printf '[OK]    %s\n' "$*"; }
command -v log_warn    >/dev/null 2>&1  || log_warn()    { printf '\033[33m[WARN]\033[0m  %s\n' "$*" >&2; }
command -v log_error   >/dev/null 2>&1  || log_error()   { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
command -v log_banner  >/dev/null 2>&1  || log_banner()  { printf '=== %s ===\n' "$*"; }
command -v log_divider >/dev/null 2>&1  || log_divider() { printf '%s\n' '---------------------------------------------'; }

## ------------------------------------------------------------------------------------------------
## Function to hide the output of external commands, unless flag is turned on.
## ------------------------------------------------------------------------------------------------
run_cmd() {
  if [ "$FLG_VERBOSE" -eq 1 ]; then
    printf "%s[ VEBOSE ]%s Running command: %s\n" "$YELLOW" "$RESET" "$@"
    "$@"                    # Execute the command. Use $@ and not $* to preserve quote word boundaries 
  else
    "$@" > /dev/null        # Execute the command
  fi
}

## ------------------------------------------------------------------------------------------------
## Creates a PVE template using the input parameters or defined defaults
## Following assumptions are made, that could cause script errors if not true:
## - Proxmox uses or contains a single ZFS (local-zfs) or LVM (local-lvm) Partition
## - SSH keys to add to the template are stored in the file /root/.ssh/cloud_init_authorized_keys
## ------------------------------------------------------------------------------------------------
create_template(){
  log_step "Create PVE Template: VMID=${C_LYELLOW}${TEMPLATE_NUM}${C_RESET}, OS=${C_LBLUE}${PATH_OS}${C_RESET}"

  ## Determine if proxmox is configured with local-lvm or local-zfs
  ## if both are present or there are multiple type this will break
  PROXMOX_VOL_TYPE=$(pvesm status | awk '/local-(lvm|zfs)/ {print $1}')
  if [ "$(printf '%s\n' "$PROXMOX_VOL_TYPE" | wc -l)" -gt 1 ]; then
    log_error "Multiple backend storages are present. The '$SCRIPT_NAME' script does not handle such scenarios. Aborting"
    return 1 
  fi

  PATH_TEMPLATE="${PATH_DIR_VM_CONFIG}/${TEMPLATE_NUM}.conf"
  if [ -e $PATH_TEMPLATE ]; then
    if [ $FLAG_OVERWRITE -eq 0 ]; then
      printf "Warning: VM/Template configuration with ID ""%s"" already exists in directory ""%s""\n" "$TEMPLATE_NUM" "$PATH_DIR_VM_CONFIG"

      while true; do
        printf "Do you want to continue? (yes/no): "
        read IO_ANSWER
        # Convert to lowercase (POSIX-safe)
        IO_ANSWER=$(printf '%s' "$IO_ANSWER" | tr '[:upper:]' '[:lower:]')
        case "$IO_ANSWER" in
          yes|y)
            log_info "Removing old template"
            run_cmd qm destroy "$TEMPLATE_NUM" --purge 1
            [ "$?" -ne 0 ] && log_err "Failed to remove old template Aborting."
            break
            ;;
          no|n)
            exit
            ;;
          *)
            printf "Invalid response. Please enter yes or no.\n"
            ;;
        esac
      done
    else
      log_info "Removing old template"
      run_cmd qm destroy "$TEMPLATE_NUM" --purge 1
      [ "$?" -ne 0 ] && log_err "Failed to remove old template. Aborting."
    fi
  fi

  log_info "Create VM"
  run_cmd qm create $TEMPLATE_NUM --name "${TEMPLATE_NAME}"
  [ "$?" -ne 0 ] && log_err "Failed to create VM for the template. Aborting."

  #qm importdisk $TEMPLATE_NUM ${PATH_DIR_ISO}/${OS_IMAGE} $PROXMOX_VOL_TYPE

  if [ -f "$DEF_AUTHORISED_SSH_KEYS" ]; then 
    ADD_SSH_KEYS="true"
  else
    log_warn "No ssh keys added to image. File not found: OS=${C_LRED}${DEF_AUTHORISED_SSH_KEYS}${C_RESET}."
    log_warn "Proceeding without any ssh keys."
  fi

  log_info "Customize VM (it takes a while to transfer the OS image into the VM)"
  run_cmd qm set $TEMPLATE_NUM --ostype l26 --scsi0 ${PROXMOX_VOL_TYPE}:0,discard=on,ssd=1,import-from=${PATH_OS} \
    --serial0 socket --vga serial0 --machine q35 --scsihw virtio-scsi-pci --agent enabled=1 \
    --bios ovmf --efidisk0 ${PROXMOX_VOL_TYPE}:1,efitype=4m,pre-enrolled-keys=1 \
    --boot order=scsi0 \
    --scsi2 ${PROXMOX_VOL_TYPE}:cloudinit,media=cdrom \
    --cpu host --cores 1 --memory 2048 \
    -net0 virtio,bridge=${DEF_NETWORK_BRIDGE0} \
    --ciuser "$DEF_USER_NAME" --cipassword "$DEF_PASSWORD" ${ADD_SSH_KEYS:+--sshkeys "$DEF_AUTHORISED_SSH_KEYS"}\
    --nameserver "${DEF_NAME_SERVER}" \
    --searchdomain "${DEF_SEARCH_DOMAIN}" \
    --ipconfig0 ip=dhcp

  if [ "$?" -ne 0 ]; then 
    log_err "Error occurred configuring the VM. Removing the temporary VM and aborting."
    run_cmd qm destroy "$TEMPLATE_NUM" --purge 1
    return 1
  fi
  
  log_info "Convert VM into template"
  qm template $TEMPLATE_NUM
  if [ "$?" -ne 0 ]; then
    log_err "Failed to convert the VM into a Template. Removing the temporary VM and aborting."
    run_cmd qm destroy "$TEMPLATE_NUM" --purge 1
    return 1
  fi
  if [ "$PROXMOX_VOL_TYPE" = "local-lvm" ]; then 
    log_warn "Warnings about 'Combining activation change...' are a result of the template being created on a LVM partition."
    log_warn "This particular warning comes from LVM, a non-PVE specific technology, and can be ignored."  
  fi

  log_ok "Create PVE Template"
}

## ------------------------------------------------------------------------------------------------
## Usage function
## ------------------------------------------------------------------------------------------------
usage(){
  printf "Script to create VM templates with minimal requirements and specific default values.\n"
  printf "Usage:\n"
  printf "  %s[-f] [-v] -i <FILE_PATH> -n <NUMBER> -N <STRING> \n" "${0##*/}"
  printf "  %s -h | --help \n" "${0##*/}"
  printf "\n"
  printf "    -f              Overwrite the template if it already exists.\n"
  printf "    -h | --help     Display this usage guide \n"
  printf "    -i <FILE_PATH>  Path of OS image to be used for the template.\n"
  printf "    -n <NUM>        Number to use for the template.\n"
  printf "    -N <STRING>     Name to use for the template. \n"
  printf "    -v | --verbose  Verbose output to show all the commands that are\n"
  printf "                    executed. Useful for debugging script issues. \n"
  printf "\n"
}

## ------------------------------------------------------------------------------------------------
## Argument parsing
## ------------------------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -f)
      FLAG_OVERWRITE=1
      shift 1
      ;;
    -i)
      # Requires a string argument
      if [ -n "$2" ] && [ "$2" != -* ]; then
        if [ -f "$2" ]; then
          PATH_OS="$2"
          shift 2
        elif [ -f "${PATH_DIR_ISO}/${2}" ]; then
          PATH_OS="${PATH_DIR_ISO}/${2}"
          shift 2
        else
          printf "Error: Cannot find image file ""%s""  in current folder (%s) or in %s\n" "$2" "$PWD" "$PATH_DIR_ISO"
          exit 1
        fi
      else
        printf "Error: -i requires a OS image filepath to be provided\n"
        exit 1
      fi
      FLAG_PARSED=$((FLAG_PARSED | FLAG_IMAGE)) ## Set flag
      ;;
    -h|--help)
      usage
      exit
      ;;
    -n) 
      if [ -n "$2" ] && [ "$2" != -* ]; then
          TEMPLATE_NUM="$2"
          shift 2
      else
        printf "Error: -n is missing a template number\n"
        exit 1
      fi
      FLAG_PARSED=$((FLAG_PARSED | FLAG_NUMBER)) ## Set flag
      ;;
    -N)
      if [ -n "$2" ] && [ "$2" != -* ]; then
          TEMPLATE_NAME="$2"
          shift 2
      else
          printf "Error: -N is missing name for VM to be created\n"
          exit 1
      fi
      FLAG_PARSED=$((FLAG_PARSED | FLAG_NAME)) ## Set flag
      ;;
    -v|--verbose)
      FLG_VERBOSE=1
      shift 1
      ;;
    *)
      printf "Unknown option: $1\n"
      usage
      exit 1
      ;;
  esac
done

if [ $FLAG_PARSED -ne $((FLAG_IMAGE | FLAG_NUMBER | FLAG_NAME)) ]; then
    printf "Error: Not all the required parameters were provided.\n"
    usage
    exit 1
fi

## ------------------------------------------------------------------------------------------------
## Main
## ------------------------------------------------------------------------------------------------
create_template