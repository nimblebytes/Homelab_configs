#!/bin/sh

## =============================================================================
## !! Provides NO main function !!
##
## Functions to standardize the formats of io/logs outputs.
## - Provides static variables for standard colours 
##
## Author: nimblebytes (GitHub)
## =============================================================================

# Define ANSI color codes
BLACK=$(printf '\033[30m')
RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')   # Yellow is often used for orange
BLUE=$(printf '\033[34m')
MAGENTA=$(printf '\033[35m')  
PURPLE=$(printf '\033[35m')   # Same code as Magenta; Purple is easier to remeber
CYAN=$(printf '\033[36m')
LIGHT_GRAY=$(printf '\033[37m')

DARK_GRAY=$(printf '\033[1;30m')  
LIGHT_RED=$(printf '\033[1;31m')
LIGHT_GREEN=$(printf '\033[1;32m')
LIGHT_YELLOW=$(printf '\033[1;33m')
LIGHT_BLUE=$(printf '\033[1;34m')
LIGHT_MAGENTA=$(printf '\033[1;35m')
LIGHT_PURPLE=$(printf '\033[1;35m')   # Same code as Magenta; Purple is easier to remeber
LIGHT_CYAN=$(printf '\033[1;36m')
WHITE=$(printf '\033[1;37m')

# Backgorund colours
BLACK_B=$(printf '\033[40m')
RED_B=$(printf '\033[41m')
GREEN_B=$(printf '\033[42m')
BLUE_B=$(printf '\033[44m')
MAGENTA_B=$(printf '\033[45m')
PURPLE_B=$(printf '\033[45m')    # Same code as Magenta; Purple is easier to remeber
CYAN_B=$(printf '\033[46m')
LIGHT_GRAY_B=$(printf '\033[47m')

RESET=$(printf '\033[0m')
TAB=$(printf '\t')
NL=$(printf '\n')

# -----------------------------
# Helper functions
# -----------------------------
msg_error() { 
  msg_err $*
}
msg_err() { 
  printf "${RED}[ ERROR  ]${RESET} $*\n" >&2
  exit 1
}
msg_warn() { 
  printf "${YELLOW}[  WARN  ]${RESET} $*\n" >&2 
}
msg_done(){
  printf "${GREEN}[  DONE  ]${RESET} $*\n" >&2
}
msg_start(){
  printf "${CYAN}[ START  ]${RESET} $*\n" >&2
}
msg_info() { 
  printf " >> $*\n"
}