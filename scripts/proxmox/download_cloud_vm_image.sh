#!/bin/sh

## =============================================================================
## Script Name: download_cloud_vm_image.sh
## Description: Downloads the requested cloud OS image. Defaults to Debian 13
##  - Downloads only newer versions of the image, if available. Can be skipped.
##  - Patches a copy of the OS, with qemu-guest, and fixes DNS search string 
##    request. Can be skipped.
##
## Author: nimblebytes (GitHub)
## =============================================================================

# set -x

## Default values that can be changed
OS_TYPE=debian
OS_VERSION=13
OS_VERSION_NAME=""
OS_IMAGE=""
OS_IMAGE_MODIFIED=""
URL_OS_IMAGE=""

ISO_DIR_PATH=/var/lib/vz/template/iso           ## The location depends on the configuration of Proxmox 

## Variables used in the script
FLAG_OUTPUT_FILEPATH=0
FLAG_SKIP_CUSTOMIZE=0
FLAG_SKIP_DOWNLOAD=0
FLG_VERBOSE=0

## Resolve directory of this script (POSIX safe)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

## Load external function library if the file exists
if [ -r "${SCRIPT_DIR}/better_logs.sh" ]; then 
  . "${SCRIPT_DIR}/better_logs.sh"
else
  printf "Warning: better_logs.sh not found, using fallback logging.\n" >&2
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
## Check and install required tools
##  - libguestfs-tools is used to modify the OS images without bootup them up first
## ------------------------------------------------------------------------------------------------
install_required_tools(){
  msg_start "Install required tools"
  if dpkg -s libguestfs-tools > /dev/null 2>&1; then
    msg_info "Already installed: ${PURPLE}libguestfs-tools${RESET}"
  else
    msg_info "Installing: ${PURPLE}libguestfs-tools${RESET}"
    run_cmd apt-get update -y
    run_cmd apt-get install libguestfs-tools -y
    [ "$?" -ne 0 ] && msg_warn "Failed to install libguestfs-tools. Check internet connection."
  fi
  msg_done "Install required tools"
}

## ------------------------------------------------------------------------------------------------
## Function to download the required OS Image
## ------------------------------------------------------------------------------------------------
download_image(){
  msg_start "Download OS image: ${PURPLE}${OS_IMAGE}${RESET}"
  cd ${ISO_DIR_PATH}
  if [ -e ${OS_IMAGE} ]; then 
    msg_info "Local copy of image exists. Checking for newer version."
  else
    msg_info "No local copy of image. Downloading..."
  fi
  ## -q Suppress verbose output
  ## -S Show server header
  ## -N Mirror option. Download only if it is newer; output file does not need to be defined.
  # run_cmd wget -q --show-progress -N ${URL_OS_IMAGE} 2> /dev/null
  run_cmd wget -q --show-progress -N ${URL_OS_IMAGE} 
  [ "$?" -ne 0 ] && msg_err "Failed to download image. Aborting."
  msg_done "Download OS Image"
}

## ------------------------------------------------------------------------------------------------
## Function to customize the os image
## - Force the OS to request the DNS search string when using DHCP
## - Install the qemu-guest-agent
## - Do NOT add "cloud-init clean --machine-id", this breaks the network configuration for DHCP
## - Clean up apt cache
## ------------------------------------------------------------------------------------------------
customize_os_image(){
  msg_start "Customize Image: ${PURPLE}${OS_IMAGE_MODIFIED}${RESET}"
  cd ${ISO_DIR_PATH}

  msg_info "Create copy: ${LIGHT_BLUE}${OS_IMAGE}${RESET} --> ${LIGHT_BLUE}${OS_IMAGE_MODIFIED}${RESET}"
  cp ${OS_IMAGE} ${OS_IMAGE_MODIFIED}

  #virt-customize -a ${ISO_DIR_PATH}/${OS_IMAGE} --root-password password:NewPassword!

  msg_info "Customize: Request domain from DHCP; Install Guest-Agent; Cleanup "
  ## Modify the base OS
  ## Do NOT add "cloud-init clean --machine-id". This breaks the DHCP client configuration, with a
  ## file not found error, because systemd-networkd uses the machine-id for:
  ## - Generating DHCP Client Identifier
  ## - Generating DUID (for DHCPv6)
  ## - Stable interface identity
  ## - Lease persistence
  run_cmd virt-customize \
    -a ${ISO_DIR_PATH}/${OS_IMAGE_MODIFIED}  \
    --mkdir /etc/systemd/network/10-netplan-eth0.network.d \
    --write /etc/systemd/network/10-netplan-eth0.network.d/10-dhcp-options.conf:"# Customization - Ensure DNS search string (option 119) is requested when using DHCP
[DHCPv4]
UseDNS=yes
UseDomains=yes
#RequestOptions=119

[DHCPv6]
UseDNS=yes
UseDomains=yes
" \
    --install qemu-guest-agent \
    --run-command "cloud-init clean --logs --seed --machine-id" \
    --run-command "apt clean" 

  [ "$?" -ne 0 ] && msg_err "Error while customizing the image. Aborting."
  msg_done "Customize Image"

}

## ------------------------------------------------------------------------------------------------
## Function to shrink the image, by remove unused/unallocated space and drives
## ------------------------------------------------------------------------------------------------
shrink_modified_image(){
  msg_start "Shrink image: ${PURPLE}${OS_IMAGE_MODIFIED}${RESET}"
  run_cmd virt-sparsify --in-place ${OS_IMAGE_MODIFIED}
  [ "$?" -ne 0 ] && msg_warn "Error shrinking the image. Continuing."
  msg_done "Shrink image"
}

## ------------------------------------------------------------------------------------------------
## Usage function
## ------------------------------------------------------------------------------------------------
usage(){
  printf "Script to download and customize OS Images.\n"
  printf " - Supported images: Debian 12 (bookworm); Debian 13 (trixie)\n"
  printf "Usage:\n"
  printf "  %s [-C] [-S] [-v] -i <STRING> -V <NUM>\n" "${0##*/}"
  printf "  %s [-C] [-S] [-v] -d12|d13 \n" "${0##*/}"
  printf "  %s -h | --help \n" "${0##*/}"
  printf "  %s -o|-m [-d12|-d13] | [-i <STRING> -V <NUM>]  \n" "${0##*/}"
  printf "\n"
  printf "    -C | --skip-customize     Skip customization of the downloaded OS.\n"
  printf "    -d12                      Download Debian 12 (Bookworm).\n"
  printf "    -d13                      Download Debian 13 (Trixie).\n"
  printf "    -h | --help               Display this usage guide \n"
  printf "    -i | --os-image <STRING>  OS type to download. Options: Debian; Ubuntu \n"
  printf "    -m | --mod-os-path        Output the filename of the modified OS file. Default=Debian 13\n"
  printf "    -o | --os-path            Output the filename of the base OS file. Default=Debian 13\n"
  printf "    -S | --skip-download      Skip downloading the OS file. Useful if the OS is already present and the latest build in not required.\n"
  printf "    -V | --version            Version of OS to download.\n"
  printf "    -v | --verbose            Verbose output to show all the commands that are\n"
  printf "                              executed. Useful for debugging script issues. \n"
  printf "\n"
}


## ------------------------------------------------------------------------------------------------
## Argument parsing
## ------------------------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -C|--skip-cutomize)
      FLAG_SKIP_CUSTOMIZE=1
      shift 1
      ;;
    -i|--os-image)
      # Requires a string argument
      if [ -n "$2" ] && [ "$2" != -* ]; then
          OS_TYPE="$2"
          shift 2
      else
          printf "Error: -i requires a OS name: [debian|ubuntu].\n"
          exit 1
      fi
      ;;
    -d12)
      OS_TYPE=debian
      OS_VERSION="12"
      shift
      ;;
    -d13)
      OS_TYPE=debian
      OS_VERSION="13"
      shift
      ;;
    -h|--help)
      usage
      exit
      ;;
    -o|--os-path)
      ## Output the filename of the OS image file
      FLAG_OUTPUT_FILEPATH=1
      shift
      ;;
    -m|--mod-os-path)
      ## Output the filename of the mod OS image file
      FLAG_OUTPUT_FILEPATH=2
      shift
      ;;
    -S|--skip-download)
      FLAG_SKIP_DOWNLOAD=1
      shift 1
      ;;
    -V|--version)
      # Requires a numeric argument
      if [ -n "$2" ] && ["$2" != -* ]; then
          OS_VERSION="$2"
          shift 2
      else
          printf "Error: -i requires a OS version number: [debian|ubuntu].\n"
          exit 1
      fi
      ;;
    -v|--verbose)
      FLG_VERBOSE=1
      shift 1
      ;;
    *)
      printf "Unknown option: %s\n" "$1"
      usage
      exit 1
      ;;
  esac
done

## Finishing setting up internal variables based on user input parameters
if [ "$OS_TYPE" = "debian" ]; then
  if [ "$OS_VERSION" = "12" ]; then
    OS_VERSION_NAME=bookworm
  elif [ "$OS_VERSION" = "13" ]; then
    OS_VERSION_NAME=trixie
  else
    printf "Script does not handle Debian version: ""%s""\n" "$OS_IMAGE_VERSION"
    exit 1
  fi

  OS_IMAGE=debian-${OS_VERSION}-genericcloud-amd64.qcow2
  OS_IMAGE_MODIFIED=debian-${OS_VERSION}-genericcloud-amd64_patched.qcow2
  URL_OS_IMAGE=https://cloud.debian.org/images/cloud/${OS_VERSION_NAME}/latest/${OS_IMAGE}

elif [ $OS_TYPE="ubuntu" ]; then 
  if [ "$OS_IMAGE_VERSION"="99" ]; then
    OS_VERSION_NAME=TBC
  else
    printf "Script does not handle Ubuntu version: ""%s""\n" "$OS_IMAGE_VERSION"
    exit 1
  fi
else
  printf "Script does not handle OS type: ""%s""\n" "$OS_TYPE"
  exit 1
fi


## ------------------------------------------------------------------------------------------------
## Main 
## ------------------------------------------------------------------------------------------------

## Output the filename of the modified OS image file
if [ $FLAG_OUTPUT_FILEPATH -gt 0 ]; then
  if [ $FLAG_OUTPUT_FILEPATH -eq 1 ]; then 
    printf "%s\n" "$OS_IMAGE"
  elif [ $FLAG_OUTPUT_FILEPATH -eq 2 ]; then 
    printf "%s\n" "$OS_IMAGE_MODIFIED"
  else
    printf "Script error: unexpected flag value\n"
    exit 1
  fi
  exit
fi

install_required_tools

if [ $FLAG_SKIP_DOWNLOAD -eq 0 ]; then
  download_image
fi

if [ $FLAG_SKIP_CUSTOMIZE -eq 0 ]; then
  if [ -f "$OS_IMAGE" ]; then 
    customize_os_image
    shrink_modified_image
  else
    msg_warn "Image file not found: ${OS_IMAGE}. Cannot modify or shrink the image."
    [ $FLAG_SKIP_DOWNLOAD -eq 0 ] && msg_warn "Skip download flag is set. Run the script without the '-S' flag."
  fi
fi

return 0