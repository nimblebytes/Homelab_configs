#!/bin/sh

## =============================================================================
## Script Name: download_proxmox_scripts.sh
## Description: Downloads the proxmox automation scripts from this repository
##   into the /usr/lib/scripts_cloud_init folder and makes them executable
##
## Author: nimblebytes (GitHub)
## =============================================================================

SOURCE_REPO=https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/proxmox/
TARGET_FOLDER=/usr/local/lib/scripts_cloud_init

mkdir -p "$TARGET_FOLDER"
cd "$TARGET_FOLDER"

wget -q -N --show-progress \
  "${SOURCE_REPO}/download_cloud_vm_image.sh" \
  "${SOURCE_REPO}/create_pve_template.sh" \
  "${SOURCE_REPO}/create_vm.sh" \
  "${SOURCE_REPO}/build_test_labrat_vm.sh" \
  "${SOURCE_REPO}/build_debian12_template_vm.sh" \
  "https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/lib/better_logs.sh"

if [ $? -ne 0 ]; then 
  printf "Failed to download the files. Exiting."
  exit
fi

chmod +x \
  download_cloud_vm_image.sh \
  create_pve_template.sh \
  create_vm.sh \
  build_test_labrat_vm.sh

printf "Scripts downloaded into folder: %s\n" "$TARGET_FOLDER"

