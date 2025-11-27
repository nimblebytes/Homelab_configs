#!/bin/sh

## =============================================================================
## Script Name: install_host_git_project.sh
## Description: Script to install Git and the host projects in the git repo
##  - Repo package updates and upgrades
##  - Install Git
##  - Install host project from the Git repo
##
## Author: nimblebytes (GitHub)
## =============================================================================

#set -x  # Enable script debugging

## Script variables - default values
var_HOSTNAME=${HOSTNAME}
var_REPO_NAME=nimblebytes
var_REPO_PROJECT=Homelab_configs
var_REPO_BRANCH=master
var_REPO_STR=""

var_PROJECT_FOLDER="/home/${USER}/git"


create_repo_string(){

  var_REPO_STR="https://github.com/${var_GIT_REPO_NAME}/${var_GIT_PROJECT}.git"
  var_REPO_STR_RAW="https://raw.githubusercontent.com/${var_GIT_REPO_NAME}/${var_GIT_PROJECT}/refs/heads/${var_GIT_BRANCH}"
}

install_git(){
  ## Check if required privileges 
  if ! detect_root_sudo; then
    echo "Error: Root or sudo priviledges are needed for this script."
    return 1
  fi

  # Update package lists silently
  if ! $SUDO apt update -y >/dev/null 2>&1; then
    echo "ERROR: apt update failed."
    return 1
  fi

  # Install git silently
  if ! $SUDO apt install -y git >/dev/null 2>&1; then
    echo "ERROR: git installation failed."
    return 1
  fi

  # Verify git is available
  if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git installed but not found in PATH."
    return 1
  fi

  echo "SUCCESS: git installed successfully."
  return 0
}

## Detect sudo requirement
detect_root_sudo(){
  ## Get the UID of the user, to check if running as root
  UID_RESULT=`id -u 2>/dev/null`
  if [ "$UID_RESULT" = "0" ]; then
    SUDO=""
  ## Check if the 'sudo' command exists
  elif command -v sudo >/dev/null 2>&1; then
    if sudo -n true >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "ERROR: sudo available but user lacks privileges or password is required."
    fi
  else
    return 1
  fi
  return 0
}

pull_git_project(){
  create_repo_string

  ## Create the project folder if ti does not exist
  if [ ! -e ${var_PROJECT_FOLDER} ]; then
    mkdir -R ${var_PROJECT_FOLDER}
  fi

  git clone --no-checkout ${var_REPO_STR} ${var_PROJECT_FOLDER}     ## Clone the Repo to the project folder
  cd ${var_PROJECT_FOLDER}
  git sparse-checkout init --cone                                   ## Initialise a sparse checkout
  git sparse-checkout set ${var_HOSTNAME}                           ## Checkout only folders with host name
  git checkout ${var_REPO_BRANCH}                                   ## Checkout the required branch

}