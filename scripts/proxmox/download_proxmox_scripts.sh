#!/bin/sh

## =============================================================================
## Script Name: download_proxmox_scripts.sh
## Description: Downloads the proxmox automation scripts from this repository
##   into the /usr/lib/scripts_cloud_init folder and makes them executable
##
## Author: nimblebytes (GitHub)
## =============================================================================

SOURCE_REPO=https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/proxmox/
TARGET_FOLDER="${HOME}/bin/proxmox_scripts"
START_MARK="## >>> Proxmox automation scripts >>>"
END_MARK="## <<< Proxmox automation scripts <<<"

PROXMOX_SCRIPTS="download_cloud_vm_image.sh create_pve_template.sh create_vm.sh build_test_labrat_vm.sh build_debian13_template.sh"

mkdir -p "$TARGET_FOLDER"
cd "$TARGET_FOLDER"

for SCRIPT in $PROXMOX_SCRIPTS; do
  wget -q -N --show-progress "${SOURCE_REPO}/${SCRIPT}"
  if [ -f ${SCRIPT} ]; then 
    chmod +x ${SCRIPT}
  else
    printf "Warn: failed to download script: %s\n" "$SCRIPT"
  fi
done

## Just download this helper library (from a different repo folder), but do not make it executable
wget -q -N --show-progress "https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/lib/better_logs.sh"

## Add the script folder to the paths variable
if ! grep -Fq "$START_MARK" "$HOME/.bashrc"; then
  {
      printf "\n%s\n" "$START_MARK"
      printf 'export PATH="%s:%s"\n' "$TARGET_FOLDER" "$PATH"
      printf "%s\n" "$END_MARK"
  } >> "$HOME/.bashrc"
fi

printf "Scripts downloaded into folder: %s\n" "$TARGET_FOLDER"
printf "Environment variables updated. Reload with 'source \$HOME/.bashrc'\n"



