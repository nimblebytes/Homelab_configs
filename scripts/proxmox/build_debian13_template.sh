#!/bin/sh

## =============================================================================
## Script Name: build_debian13_template.sh
## Description: Example how chain the other proxmox scripts to:
##  - Download a specific OS
##  - Modify/patch the OS
##  - Create a VM Template
##
## Author: nimblebytes (GitHub)
## =============================================================================

# set -x

## Default values that can be changed
DEF_TEMPLATE_ID=9000
DEF_TEMPLATE_NAME="Debian13-dns-search"
DEF_DOWNLOAD_OS_TYPE="d13"                          ## Debian 13 (Trixie)

DEF_PATH_DIR_ISO=/var/lib/vz/template/iso           ## The location depends on the configuration of Proxmox 

## ## Variables used in the script
DEF_OS_IMAGE=""
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && $PWD)

## Download the latest OS Image and patch it
${SCRIPT_DIR}/download_cloud_vm_image.sh -${DEF_DOWNLOAD_OS_TYPE}
if [ $? -ne 0 ]; then
  printf "Error occurred running script to download and customize OS image. Aborting.\n"
  printf "To debug the issue, run the command for verbose output: %s/download_cloud_vm_image.sh -v -S -d13" "$SCRIPT_DIR"
  exit 1
fi

## Get the filepath of the (modified) OS Image
DEF_OS_IMAGE=$(${SCRIPT_DIR}/download_cloud_vm_image.sh -m -${DEF_DOWNLOAD_OS_TYPE})

## Create the template image
${SCRIPT_DIR}/create_pve_template.sh -f -i ${DEF_PATH_DIR_ISO}/${DEF_OS_IMAGE} -n $DEF_TEMPLATE_ID -N ${DEF_TEMPLATE_NAME}
if [ $? -ne 0 ]; then
  printf "Error running script to create template. Aborting.\n"
  printf "To debug the issue, run the command for verbose output: %s/create_pve_template.sh -v -i %s/%s -n %s -N %s" "$SCRIPT_DIR" "$DEF_PATH_DIR_ISO" "$DEF_OS_IMAGE" "$DEF_TEMPLATE_ID" "$DEF_TEMPLATE_NAME"
  exit 1
fi
