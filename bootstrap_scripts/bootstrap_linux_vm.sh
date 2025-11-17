#!/bin/sh

## =============================================================================
## Script Name: bootstrap_linux_vm.sh.sh
## Description: Script to automate initial configuration of new systems
##  - Repo package updates and upgrades
##  - Install Qemu-guest-agent (to interface with Proxmox)
##
## Author: nimblebytes (GitHub)
## =============================================================================

#set -x  # Enable script debugging

## Script variables - default values
var_HOSTNAME=${HOSTNAME}


## Flags used within the script
isROOT="false"    
hasSUDO="false"

## Check if the script is running with root privileges
check_for_root(){  
  [ "$(id -u)" = "0" ] && isROOT="true" || isROOT="false"
  sudo -n true 2> /dev/null && hasSUDO="true" || hasSUDO="false"  ## Evaluate if user has sudo right. Do NOT use [ ... ] for evaluation.
}

## Override the system parameters used for variables - useful for testing and debug 
load_overwrite_configs(){
  if [ -e "configs.override" ]; then
    source ./configs.override
  fi
  return 0
}



install_qemu_guest_agent(){

  printf " >>> Installing Qemu-guest-agent <<<<\n"
  sudo apt install qemu-guest-agent -y
  sudo systemctl start qemu-guest-agent >/dev/null 
  sudo systemctl enable qemu-guest-agent > /dev/null 2>&1

}


## Install process for Docker - https://docs.docker.com/engine/install/debian/
install_docker_rootful(){

  FLAG_PERMISSIONS="false"

  [ "${isROOT}" = "true" ] &&  FLAG_PERMISSIONS="true"
  [ "${hasSUDO}" = "true"  ] &&  FLAG_PERMISSIONS="true"
  if [ "${FLAG_PERMISSIONS}" = "false" ]; then
    return 1
  fi

  # Remove all old or conflicting packages
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
    sudo apt-get remove -y -qq $pkg; 
  done

  # Add Docker's official GPG key:
  sudo apt-get update -y -qq
  sudo apt-get install -y -qq ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y -qq

  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

echo "Install script"

