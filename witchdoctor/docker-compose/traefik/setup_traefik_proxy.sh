#!/bin/sh

## Variables that can be changed by the User
LOG_LEVEL=2                                     # Options: ERROR=0; WARNING=1; INFO=2; DEBUG=3
SCRIPT_FILE=create_docker_proxy_network.sh

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

# Define message type levels as numbers
LOG_LEVEL_ERROR=0
LOG_LEVEL_WARNING=1
LOG_LEVEL_INFO=2
LOG_LEVEL_DEBUG=3

# Function to output status messages with colors
status_message() {
    MESSAGE_LEVEL=$1
    MESSAGE=$2

    # Exit if the message level is higher (less important) than the current log level
    [ "$MESSAGE_LEVEL" -gt "$LOG_LEVEL" ] && return

    # Determine the color and message type string
    if [ "$MESSAGE_LEVEL" -eq "$LOG_LEVEL_ERROR" ]; then
        COLOR=$RED
        MESSAGE_TYPE="ERR"
    elif [ "$MESSAGE_LEVEL" -eq "$LOG_LEVEL_WARNING" ]; then
        COLOR=$YELLOW
        MESSAGE_TYPE="WRN"
    elif [ "$MESSAGE_LEVEL" -eq "$LOG_LEVEL_INFO" ]; then
        COLOR=$LIGHT_BLUE
        MESSAGE_TYPE="INF"
    elif [ "$MESSAGE_LEVEL" -eq "$LOG_LEVEL_DEBUG" ]; then
        COLOR=$LIGHT_BLUE
        MESSAGE_TYPE="DBG"
    else
        COLOR=$WHITE
        MESSAGE_TYPE="???"
    fi

    # Output the message with the appropriate color and message type string
    printf "[${COLOR}${MESSAGE_TYPE}${RESET}] ${MESSAGE}\n"
}

## Check to see if the docker variable exists
if [ -z "$DOCKER_VOLUMES" ]; then
  status_message "$LOG_LEVEL_ERROR " "Enviroment variables used for docker are missing. Create ${LIGHT_CYAN}.bashrc file to export variables the needed"
  exit 1
fi

## Save the current folder into a temporary variable
CURRENT_DIR=$PWD

. ./.env                                                      ## Parse the environment variables

lvar_SCRIPT_STATUS=0                                          ## Flag to check if ALL the required environment variables exist

if [ ! -z "${CONTAINER_CONFIG}" ]; then
  status_message "$LOG_LEVEL_INFO" "Creating folder for container config files: ${LIGHT_CYAN}${CONTAINER_CONFIG}${RESET}"
  [ ! -d "${CONTAINER_CONFIG}" ] && mkdir -p mkdir -p "${CONTAINER_CONFIG}" || status_message "$LOG_LEVEL_DEBUG" "Folder already exists: ${LIGHT_CYAN}${CONTAINER_CONFIG}${RESET}"
else
  status_message "$LOG_LEVEL_ERROR " "Variable CONTAINER_CONFIG is not defined or empty. Defines where to store configs files needed by the container."
  lvar_SCRIPT_STATUS=1
fi

if [ ! -z "${CONTAINER_VOLUME}" ]; then
  status_message "$LOG_LEVEL_INFO" "Creating folder for container persistant files: ${LIGHT_CYAN}${CONTAINER_VOLUME}${RESET}"
  [ ! -d "${CONTAINER_VOLUME}" ] && mkdir -p mkdir -p "${CONTAINER_VOLUME}" || status_message "$LOG_LEVEL_DEBUG" "Folder already exists: ${LIGHT_CYAN}${CONTAINER_VOLUME}${RESET}"
else
  status_message "$LOG_LEVEL_ERROR " "Variable CONTAINER_VOLUME is not defined or empty. Defines where the container needs to store persistant data"
  lvar_SCRIPT_STATUS=1
fi

if [ ! -z "${DOCKER_SECRETS}" ]; then
  status_message "$LOG_LEVEL_INFO" "Creating folder for secrets: ${LIGHT_CYAN}${DOCKER_SECRETS}${RESET}"
  [ ! -d "${DOCKER_SECRETS}" ] && mkdir -p mkdir -p "${DOCKER_SECRETS}" || status_message "$LOG_LEVEL_DEBUG" "Folder already exists: ${LIGHT_CYAN}${DOCKER_SECRETS}${RESET}"
else
  status_message "$LOG_LEVEL_ERROR " "Variable DOCKER_SECRETS is not defined or empty. Defines where SECRETS are stored."
  lvar_SCRIPT_STATUS=1
fi

## Check if any environment variables where missing
if [ "$lvar_SCRIPT_STATUS" != "0" ]; then
  status_message "$LOG_LEVEL_ERROR " "Required environment variables are missing. ${RED}Exiting${RESET} to prevent files being created in the root folder."
fi


## Create files in the container persistant storage
cd ${CONTAINER_VOLUME}

status_message "$LOG_LEVEL_DEBUG" "Creating required files within folder ${LIGHT_CYAN}${CONTAINER_VOLUME}${RESET}"
touch acme.json
status_message "$LOG_LEVEL_DEBUG" "Created file: ${LIGHT_CYAN}acme.json${RESET}"
chmod 600 acme.json
status_message "$LOG_LEVEL_DEBUG" "Restricting access to: ${LIGHT_CYAN}acme.json${RESET}. Required by Traefik."
touch traefik.log
status_message "$LOG_LEVEL_DEBUG" "Created file: ${LIGHT_CYAN}traefik.log${RESET}"
touch traefik_access.log
status_message "$LOG_LEVEL_DEBUG" "Created file: ${LIGHT_CYAN}traefik_access.log${RESET}"


## Create secret files used by container
cd ${DOCKER_SECRETS:?}

status_message "$LOG_LEVEL_DEBUG" "Creating required files within folder ${LIGHT_CYAN}${CONTAINER_VOLUME}${RESET}"
touch cloudflare_email
status_message "$LOG_LEVEL_DEBUG" "Created file: ${LIGHT_CYAN}cloudflare_email${RESET}"
touch cloudflare_api
status_message "$LOG_LEVEL_DEBUG" "Created file: ${LIGHT_CYAN}cloudflare_api${RESET}"


## Script to create docker network for traefik. Check if the script exists and run it.
cd ${CURRENT_DIR}
if [ -f "${SCRIPT_FILE}" ]; then
  status_message "$LOG_LEVEL_INFO" "Running script to create docker network for Traefik: ${LIGHT_CYAN}${SCRIPT_FILE}${RESET}"
  . ${CURRENT_DIR}/$SCRIPT_FILE
fi

