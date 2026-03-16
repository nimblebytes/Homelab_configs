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
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

## Load external function library if the file exists
if [ -r "${SCRIPT_DIR}/prettier_logs.sh" ]; then 
  . "${SCRIPT_DIR}/prettier_logs.sh"
else
  printf "Warning: prettier_logs.sh not found, using fallback logging.\n" >&2
fi

## Fallback function definitions the external script/function exist.
## Each function needs to be tested seperately in case this scripts assumes/uses one function that does not exists
command -v msg_done >/dev/null 2>&1  || msg_done()  { printf 'DONE: %s\n' "$@" >&2; }
command -v msg_err >/dev/null 2>&1   || msg_err()   { printf 'ERROR: %s\n' "$@" >&2; }
command -v msg_info >/dev/null 2>&1  || msg_info()  { printf 'INFO: %s\n' "$@" >&2; }
command -v msg_start >/dev/null 2>&1 || msg_start() { printf 'START: %s\n' "$@" >&2; }
command -v msg_warn >/dev/null 2>&1  || msg_warn()  { printf 'WARN: %s\n' "$@" >&2; }

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
## - Proxmox uses or contains a ZFS partition (local-zfs)
## - SSH keys to add to the template are stored in the file /root/.ssh/cloud_init_authorized_keys
## ------------------------------------------------------------------------------------------------
create_template(){
  msg_start "Create PVE Template: VMID=${LIGHT_YELLOW}${TEMPLATE_NUM}${RESET}, OS=${LIGHT_BLUE}${PATH_OS}${RESET}"
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
            msg_info "Removing old template"
            run_cmd qm destroy "$TEMPLATE_NUM" --purge 1
            [ "$?" -ne 0 ] && msg_err "Failed to remove old template Aborting."
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
      msg_info "Removing old template"
      run_cmd qm destroy "$TEMPLATE_NUM" --purge 1
      [ "$?" -ne 0 ] && msg_err "Failed to remove old template. Aborting."
    fi
  fi

  msg_info "Create VM"
  run_cmd qm create $TEMPLATE_NUM --name "${TEMPLATE_NAME}"
  [ "$?" -ne 0 ] && msg_err "Failed to create VM for the template. Aborting."

  #qm importdisk $TEMPLATE_NUM ${PATH_DIR_ISO}/${OS_IMAGE} local-zfs

  msg_info "Customize VM (it takes a while to transfer the OS image into the VM)"
  run_cmd qm set $TEMPLATE_NUM --ostype l26 --scsi0 local-zfs:0,discard=on,ssd=1,import-from=${PATH_OS} \
    --serial0 socket --vga serial0 --machine q35 --scsihw virtio-scsi-pci --agent enabled=1 \
    --bios ovmf --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=1 \
    --boot order=scsi0 \
    --scsi2 local-zfs:cloudinit,media=cdrom \
    --cpu host --cores 1 --memory 2048 \
    -net0 virtio,bridge=${DEF_NETWORK_BRIDGE0} \
    --ciuser $DEF_USER_NAME --cipassword $DEF_PASSWORD --sshkeys /root/.ssh/cloud_init_authorized_keys \
    --nameserver "${DEF_NAME_SERVER}" \
    --searchdomain "${DEF_SEARCH_DOMAIN}" \
    --ipconfig0 ip=dhcp

  if [ "$?" -ne 0 ]; then 
    msg_err "Error occurred configuring the VM. Removing the tempory VM and aborting."
    run_cmd qm destroy "$TEMPLATE_NUM" --purge 1
  fi
  
  msg_info "Convert VM into template"
  qm template $TEMPLATE_NUM
  if [ "$?" -ne 0 ]; then
    msg_err "Failed to convert the VM into a Template. Removing the tempory VM and aborting."
    run_cmd qm destroy "$TEMPLATE_NUM" --purge 1
  fi

  msg_done "Create PVE Template"
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