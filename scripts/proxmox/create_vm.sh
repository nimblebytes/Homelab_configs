#!/bin/sh

## =============================================================================
## Script Name: create_vm.sh
## Description: Creates a VM using the default embedded parameters
##  - Possible inputs: VM name, VM ID, Template ID
##
## Author: nimblebytes (GitHub)
## =============================================================================

# set -x

## Default values that can be changed
DEF_VM_NAME=gingko
DEF_VM_ID=999
DEF_TEMPLATE_ID=0


## Variables used in the script
FLAG_FORCE=0
FLAG_FULL_CLONE=1
FLG_VERBOSE=0

## Resolve directory of this script (POSIX safe)
SCRIPT_DIR=$(dirname "$(realpath "$0")")

## Load external function library if the file exists
if [ -r "${SCRIPT_DIR}/better_logs.sh" ]; then 
  . "${SCRIPT_DIR}/better_logs.sh"
else
  printf "WARN: better_logs.sh not found, using fallback logging.\n" >&2
fi

## Fallback function definitions the external script/function exist.
## Each function needs to be tested separately in case this scripts assumes/uses one function that does not exists
command -v msg_done >/dev/null 2>&1  || msg_done()  { printf 'DONE: %s\n' "$@" >&2; }
command -v msg_err >/dev/null 2>&1   || msg_err()   { printf 'ERROR: %s\n' "$@" >&2; exit 1;}
command -v msg_info >/dev/null 2>&1  || msg_info()  { printf 'INFO: %s\n' "$@" >&2; }
command -v msg_start >/dev/null 2>&1 || msg_start() { printf 'START: %s\n' "$@" >&2; }
command -v msg_warn >/dev/null 2>&1  || msg_warn()  { printf 'WARN: %s\n' "$@" >&2; }

## ------------------------------------------------------------------------------------------------
## Function to hide the output of external commands, unless flag is turned on.
## ------------------------------------------------------------------------------------------------
run_cmd() {
  if [ "$FLG_VERBOSE" -eq 1 ]; then
    printf "%s[ VERBOSE ]%s Running command: %s\n" "$YELLOW" "$RESET" "$@"
    "$@"                    # Execute the command. Use $@ and not $* to preserve quote word boundaries 
  else
    "$@" > /dev/null        # Execute the command
  fi
}

## Get next available VMID 
get_next_id(){
  DEF_VM_ID=$(pvesh get /cluster/nextid)
}

## Print a list of all the VMs (template=0), with the ID and Name
list_vm(){
  pvesh get /cluster/resources --type vm --output-format yaml | awk '
  /^  id:/ { split($2, arr, "/"); vmid=arr[2] }
  /^  name:/ { $1=""; sub(/^ /, ""); name=$0 }
  /^  template: 0/ { print vmid " - " name }
'
}

## Print a list of all templates (template=1), with the ID and Name
list_templates(){
  pvesh get /cluster/resources --type vm --output-format yaml | awk '
  /^  id:/ { split($2, arr, "/"); vmid=arr[2] }
  /^  name:/ { $1=""; sub(/^ /, ""); name=$0 }
  /^  template: 1/ { print vmid " - " name }
'
}

## Returns 0 if ID is a template, 1 if it is a VM or not found
is_vmid_template(){
  grep -q "template: 1" /etc/pve/nodes/*/qemu-server/"$1".conf 2>/dev/null
}

## Returns 0 if ID is a VM, 1 if it is a template or not found
is_vmid_vm(){
  ! grep -q "template: 1" /etc/pve/nodes/*/qemu-server/"$1".conf 2>/dev/null
  return $?
}

## ------------------------------------------------------------------------------------------------
## Create the VM with the input parameters. Following checks are preformed:
## - If the provided template ID exists, and is actually a template
## - If the VM already exists, calls function that safely handles removing the VM
## ------------------------------------------------------------------------------------------------
create_vm(){
  TL_ID=$1
  VM_ID=$2
  VM_NAME=$3

  ## Check if a full clone needs be created
  if [ "$FLAG_FULL_CLONE" -ne 0 ]; then
    OPTS_FULL=" --full"
  fi

  ## Check if the template ID is valid
  if ! (is_vmid_template $TL_ID); then 
    msg_err "Error: VMID=$TL_ID is not a template configuration. Aborting."
  fi
  
  ## Check if the vm ID already exists
  if (is_vmid_vm $VM_ID) && [ "$FLAG_FORCE" -eq 0 ]; then 
    printf "Warning: VM with VMID=%s already exists. Continuing will remove this VM.\nProceed (y/n):" "${BLUE}${VM_ID}${RESET}"
    while true; do
        printf "Do you want to continue? (yes/no): "
        read IO_ANSWER
        # Convert to lowercase (POSIX-safe)
        IO_ANSWER=$(printf '%s' "$IO_ANSWER" | tr '[:upper:]' '[:lower:]')
        case "$IO_ANSWER" in
          yes|y)
            msg_info "Removing existing VM: VMID=${BLUE}${VM_ID}${RESET}"
            run_cmd purge_vm $VM_ID
            break
            ;;
          no|n)
            exit 1
            ;;
          *)
            printf "Invalid response. Please enter yes or no.\n"
            ;;
        esac
      done
    exit 1
  elif (is_vmid_vm $VM_ID); then 
    msg_info "Removing existing VM: VMID=${BLUE}${VM_ID}${RESET}"
    run_cmd purge_vm $VM_ID
  fi
  msg_info "Cloning template: ${BLUE}${TL_ID}${RESET} => ${BLUE}${VM_ID}${RESET}"
  run_cmd qm clone $TL_ID $VM_ID --name "$VM_NAME" $OPTS_FULL
}
## ------------------------------------------------------------------------------------------------
# Function to safely stop and remove he VM
## ------------------------------------------------------------------------------------------------
purge_vm() {
    VM_ID=$1

    if (is_vmid_template $VM_ID); then 
      msg_error "VMID=$VM_ID is an ID for a template. This function is expecting a VM ID to be removed. Aborting to prevent affecting any linked clones."
    fi

    ## Check if VM exists
    if ! [ -f /etc/pve/nodes/*/qemu-server/"$VM_ID".conf ]; then
      msg_info "VM $VM_ID not found. Skipping.\n"
      return 0
    fi

    msg_info "Stopping VM $VM_ID...\n"
    ## --shutdown attempts a graceful stop; use 'qm stop' for immediate kill
    qm stop "$VM_ID" --skiplock 1 >/dev/null 2>&1

    msg_info "Removing VM $VM_ID...\n"
    ## --purge removes the VM from backup jobs and replication too
    qm destroy "$VM_ID" --purge 1

    ## Wait until the configuration file is gone
    msg_info "Waiting for cleanup to complete...\n"
    while [ -f /etc/pve/nodes/*/qemu-server/"$VM_ID".conf ]; do
        sleep 1
    done

    msg_info "VM $VM_ID has been successfully purged.\n"
    return 0
}

## ------------------------------------------------------------------------------------------------
## Usage function
## ------------------------------------------------------------------------------------------------
usage(){
  printf "Script to create VM templates with minimal requirements and specific default values.\n"
  printf "Usage:\n"
  printf "  %s [-f] [-F|-L] -i <NUM> -n <STRING> -t <NUM> \n" "${0##*/}"
  printf "  %s -h | --help \n" "${0##*/}"
  printf "  %s -l | --list \n" "${0##*/}"
  printf "\n"
  printf "    -f | --force            Force removal of VM (if it exists), without confirmation \n"
  printf "    -F | --fullclone        (Default) Create a full clone from the template. Opposite of ""linkedclone"".\n"
  printf "    -h | --help             Display this usage guide \n"
  printf "    -i | --id <NUM>         ID (vmid) to use for the new VM.\n"
  printf "    -l | --list             Path of OS image to be used for the template.\n"
  printf "    -L | --linkedclone      Create a clone linked to the template. Changes to the template with also affect this VM. Opposite of ""fullclone"".\n"
  printf "    -n | --name <STRING>    Name for the new VM. Must confirm to DNS naming conventions; special characters and underscore are not allowed. \n"
  printf "    -t | --templateid <NUM> ID (vmid) of the template to be cloned for the new VM.\n"
  printf "    -v | --verbose          Verbose output to show all the commands that are executed. Useful for debugging script issues. \n"
  printf "\n"
}


## ------------------------------------------------------------------------------------------------
## Argument parsing
## ------------------------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force)
      FLAG_FORCE=1
      shift 1
      ;;
    -F|--fullclone)
      FLAG_FULL_CLONE=1
      shift 1
      ;;  
    -h|--help)
      usage
      exit 0
      ;;
    -i|--id)
      DEF_VM_ID="$2"
      shift 2
      ;;
    -l|--list)
      printf "List of VMs available on this node/cluster:\n"
      list_vm
      printf "\nList of Templates available on this node/cluster:\n"
      list_templates
      printf "\n"
      exit 0
      ;;
    -L|--linkedclone)
      FLAG_FULL_CLONE=0
      shift 1
      ;;  
    -n|--name)
      DEF_VM_NAME="$2"
      shift 2
      ;;
    -t|--templateid)
      DEF_TEMPLATE_ID="$2"
      shift 2
      ;;
    -v|--verbose)
      FLG_VERBOSE=1
      shift 1
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

## ------------------------------------------------------------------------------------------------
## Main 
## ------------------------------------------------------------------------------------------------
msg_start "Create VM: VMID=$DEF_VM_ID Name=$DEF_VM_NAME"
create_vm $DEF_TEMPLATE_ID $DEF_VM_ID $DEF_VM_NAME
msg_done "Create VM"