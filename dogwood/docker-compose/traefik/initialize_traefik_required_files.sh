#!/bin/sh

## ---------------------------------------------------------------------------
## The purpose of this script is to initialize all the files and folders that
## are used within the traefik compose file to ensure that:
## - The container start properly as all the required files or volume exist
## - The create files/folders created are not owned by root to prevent debug 
##   random error in the container as a result of file permission issues
## - When file are defined as volume mounts, to create files instead of folders
## - Files have the correct permissions (600 acme.json)

# set -x      ## Enable debugging

SCRIPT_FOLDER="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="${SCRIPT_FOLDER}/$(basename "$0")"

# Define ANSI color codes
BLACK="\033[0;30m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"  # Yellow is often used for orange
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
LIGHT_GRAY="\033[0;37m"

DARK_GRAY="\033[1;30m"
LIGHT_RED="\033[1;31m"
LIGHT_GREEN="\033[1;32m"
LIGHT_YELLOW="\033[1;33m"
LIGHT_BLUE="\033[1;34m"
LIGHT_MAGENTA="\033[1;35m"
LIGHT_CYAN="\033[1;36m"
WHITE="\033[1;37m"

RESET="\033[0m"

LOG_ERR="${RED}[ERR ]${RESET}"
LOG_WARN="${YELLOW}[WARN]${RESET}"
LOG_OK="${GREEN}[ OK ]${RESET}"
LOG_INFO="${LIGHT_BLUE}[INFO]${RESET}"

## Function to insert a warning message into a file
insert_warning_in_file(){
  [ -z "$1" ] && return
  [ ! -e "$1" ] && return
  cat <<EOF > "$1"
## If this file is empty, it could be that:
## a) In the compose file, the log file/folder is not bind mounted as a volume
## b) In the traefik static configuration, the log/access log is disabled
## c) In the traefik static configuration, the log/access log is routed to the container stdout instead a file
EOF
  return 0
}

## Source the env file for Traefik, to use the same variables
. .${SCRIPT}/.env 

## Check that the variables are not empty
if [ -z ${DOCKER_SECRETS} ]; then
  echo "${LOG_ERR} Path to Docker Secrets is empty. Exiting to prevent files being created in root folder"
  exit 1
fi
if [ -z ${CONTAINER_CONFIG} ]; then
  echo "${LOG_ERR} Path to Traefik Config is empty. Exiting to prevent file being created in root folder"
  exit 1
fi
if [ -z ${CONTAINER_VOLUME} ]; then
  echo "${LOG_ERR} Path to Traefik Volume (modified by Traefik) is empty. Exiting to prevent file being created in root folder"
  exit 1
fi

## Check if folder exists and initialize secrets used by Traefik
if [ -d "${CONTAINER_CONFIG}" ]; then
  touch ${DOCKER_SECRETS}/acme_email_admin
  touch ${DOCKER_SECRETS}/cloudflare_email
  touch ${DOCKER_SECRETS}/cloudflare_api_${HOSTNAME:-host}
  touch ${DOCKER_SECRETS}/.htpasswd
  echo "${LOG_INFO} Created empty secret files used by traefik in '${CYAN}${DOCKER_SECRETS}${RESET}'"
else
  echo "${LOG_ERR} Path for Docker secrets folder is defined but does not exist. Create the folder '${CYAN}${DOCKER_SECRETS}${RESET}' manually, and re-run this script. Exiting"
  exit 1
fi


## Create folders for Traefik
if [ ! -e "${CONTAINER_CONFIG}" ]; then 
  mkdir -p ${CONTAINER_CONFIG:?}/dynamic_config.d
  echo "${LOG_INFO} Created folder for traefik configs in '${CYAN}${CONTAINER_CONFIG}${RESET}'."
else
  echo "${LOG_INFO} Folder already exists: '${CYAN}${CONTAINER_CONFIG}${RESET}'. ${YELLOW}Skipping...${RESET}"
fi
if [ ! -e "${CONTAINER_VOLUME}" ]; then 
  mkdir ${CONTAINER_VOLUME:?}
  echo "${LOG_INFO} Created folder for traefik working files in '${CYAN}${CONTAINER_VOLUME}${RESET}'."
else
  echo "${LOG_INFO} Folder already exists: '${CYAN}${CONTAINER_VOLUME}${RESET}'. ${YELLOW}Skipping...${RESET}"
fi

## Check if the folders exists and create config files used by Traefik
if [ -d "${CONTAINER_CONFIG}" ]; then
  touch ${CONTAINER_CONFIG:?}/traefik_static_config.yml
  if [ ! -d "${CONTAINER_CONFIG}/dynamic_config.d" ]; then
    touch ${CONTAINER_CONFIG:?}/dynamic_config.d/middleware.yml
  fi
  echo "${LOG_INFO} Created empty config files for traefik in '${CYAN}${CONTAINER_CONFIG}${RESET}'."
else
  echo "${LOG_WARN} Cannot create files, as '${CYAN}${CONTAINER_CONFIG}${RESET}' needs to be a folder. Remove or rename the file and re-run this script!"
fi

## Check if the folder exists and create files that Traefik uses and modifies
if [ -d "${CONTAINER_VOLUME}" ]; then
  touch ${CONTAINER_VOLUME}/acme.json
  chmod 600 ${CONTAINER_VOLUME}/acme.json   ## Access needs to be restricted else Traefik generates error warnings in logs

  if [ ! -e "${CONTAINER_VOLUME}/traefik.log" ]; then 
    touch ${CONTAINER_VOLUME}/traefik.log
    insert_warning_in_file ${CONTAINER_VOLUME}/traefik.log
  fi

  if [ ! -e "${CONTAINER_VOLUME}/traefik_access.log" ]; then 
    touch ${CONTAINER_VOLUME}/traefik_access.log
    insert_warning_in_file ${CONTAINER_VOLUME}/traefik_access.log
  fi
  echo "${LOG_INFO} Created empty files for traefik outputs and applied the correct permisions in '${CYAN}${CONTAINER_CONFIG}${RESET}'."
else
  echo "${LOG_WARN} Cannot create files, as '${CYAN}${CONTAINER_VOLUME}${RESET}' needs to be a folder. Remove or rename the file and re-run this script."
fi