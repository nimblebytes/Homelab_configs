#!/bin/sh
## better_logs.sh — Shared logging & colour library
## Source this file from any script to get consistent, coloured log output.
##
## Usage (in another script):
##   LOG_FILE="/var/log/my_script.log"
##   . /path/to/better_logs.sh
##   log_file_init
##   log_info  "Something happened"
##   log_warn  "Watch out"
##   log_error "Something broke"
##   log_debug "Verbose detail"
##   log_ok    "Step completed"
##   log_step  "Starting phase 2"
##
## Colour variables are also exported for use in printf / echo directly:
##   printf "${C_RED}Error:${C_RESET} bad value\n"
##
## Colour output is suppressed automatically when stdout is not a terminal
## (e.g. when piped or redirected), unless LOG_FORCE_COLOUR=true is set.
##
## Variables consumed (set these before sourcing or via the calling script):
##   LOG_FILE          — path to append log lines to (default: no file logging)
##   LOG_LEVEL         — minimum level to display: DEBUG|INFO|STEP|OK|WARN|ERROR
##                       (default: INFO)
##   LOG_FORCE_COLOUR  — set to "true" to keep colour even when not a terminal
##   LOG_SHOW_PID      — set to "true" to include PID in every log line
## =============================================================================

## =============================================================================
## Configuration Defaults
## =============================================================================
LOG_FILE="${LOG_FILE:-}"
LOG_LEVEL="${LOG_LEVEL:-OK}"
LOG_FORCE_COLOUR="${LOG_FORCE_COLOUR:-false}"
LOG_SHOW_PID="${LOG_SHOW_PID:-false}"

## =============================================================================
## Log File Init
## =============================================================================
## log_file_init — Creates the log file if it does not exist, then sets
## permissions to 666 so both privileged (sudo) and unprivileged runs can
## append to the same file. Call this once before any log functions are used.
##
## Usage:
##   LOG_FILE="/var/log/my_script.log"
##   log_file_init
##
## If LOG_FILE is empty this function does nothing.
log_file_init() {
  if [ -z "${LOG_FILE:-}" ]; then return 0; fi

  ## Check if running as root (sudo) and if "/tmp" is used for the log path
  if [ "$(id -u)" -eq 0 ] && [ "${LOG_FILE#/tmp/}" != "$LOG_FILE" ]; then
    LOG_FILE="${LOG_FILE}_root"
    printf "[WARN]  log_file_init: due to kernel level protection for directory /tmp/, using %s for logging.\n" "$LOG_FILE" >&2
  fi
 
  ## Create parent directory if it does not exist
  LOG_DIR="$(dirname "$LOG_FILE")"
  if [ ! -d "$LOG_DIR" ]; then
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
      printf '[WARN]  log_file_init: could not create directory %s\n' "$LOG_DIR" >&2
      return 1
    fi
  fi
 
  ## Create the file if it does not exist
  if [ ! -f "$LOG_FILE" ]; then
    if ! touch "$LOG_FILE" 2>/dev/null; then
      printf '[WARN]  log_file_init: could not create log file %s\n' "$LOG_FILE" >&2
      return 1
    fi
  fi
 
  ## Set permissions so both root and the owning user can always append
  chmod 666 "$LOG_FILE" 2>/dev/null || true
}

## =============================================================================
## Colour Detection
## =============================================================================
## Only emit escape codes when writing to a real terminal (or when forced).
_log_colours_enabled() {
  if [ "$LOG_FORCE_COLOUR" = "true" ]; then return 0; fi
  ## fd 1 is a tty?
  if [ -t 1 ]; then return 0; fi
  return 1
}

## =============================================================================
## Colour Palette
## =============================================================================
## Foreground — normal
if _log_colours_enabled; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_ITALIC='\033[3m'
  C_UNDERLINE='\033[4m'

  ## Normal foreground colours
  C_BLACK='\033[30m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_MAGENTA='\033[35m'
  C_CYAN='\033[36m'
  C_WHITE='\033[37m'

  ## Light / bright foreground colours
  C_LBLACK='\033[90m'
  C_LRED='\033[91m'
  C_LGREEN='\033[92m'
  C_LYELLOW='\033[93m'
  C_LBLUE='\033[94m'
  C_LMAGENTA='\033[95m'
  C_LCYAN='\033[96m'
  C_LWHITE='\033[97m'

  ## Background colours
  C_BG_BLACK='\033[40m'
  C_BG_RED='\033[41m'
  C_BG_GREEN='\033[42m'
  C_BG_YELLOW='\033[43m'
  C_BG_BLUE='\033[44m'
  C_BG_MAGENTA='\033[45m'
  C_BG_CYAN='\033[46m'
  C_BG_WHITE='\033[47m'

  ## Light background colours
  C_BG_LBLACK='\033[100m'
  C_BG_LRED='\033[101m'
  C_BG_LGREEN='\033[102m'
  C_BG_LYELLOW='\033[103m'
  C_BG_LBLUE='\033[104m'
  C_BG_LMAGENTA='\033[105m'
  C_BG_LCYAN='\033[106m'
  C_BG_LWHITE='\033[107m'
else
  ## No colour — set every variable to an empty string so callers don't break
  C_RESET=''    C_BOLD=''       C_DIM=''         C_ITALIC=''    C_UNDERLINE=''
  C_BLACK=''    C_RED=''        C_GREEN=''        C_YELLOW=''
  C_BLUE=''     C_MAGENTA=''    C_CYAN=''         C_WHITE=''
  C_LBLACK=''   C_LRED=''       C_LGREEN=''       C_LYELLOW=''
  C_LBLUE=''    C_LMAGENTA=''   C_LCYAN=''        C_LWHITE=''
  C_BG_BLACK='' C_BG_RED=''     C_BG_GREEN=''     C_BG_YELLOW=''
  C_BG_BLUE=''  C_BG_MAGENTA='' C_BG_CYAN=''      C_BG_WHITE=''
  C_BG_LBLACK=''  C_BG_LRED=''    C_BG_LGREEN=''  C_BG_LYELLOW=''
  C_BG_LBLUE=''   C_BG_LMAGENTA='' C_BG_LCYAN=''  C_BG_LWHITE=''
fi

## =============================================================================
## Log Level Ordering
## Returns 0 (true) if $1 level is at or above the current LOG_LEVEL threshold.
## =============================================================================
_log_level_value() {
  case "$1" in
    DEBUG) printf '0' ;;
    INFO)  printf '1' ;;
    STEP)  printf '2' ;;
    OK)    printf '3' ;;
    WARN)  printf '4' ;;
    ERROR) printf '5' ;;
    *)     printf '1' ;;
  esac
}

_log_should_print() {
  THRESHOLD="$(_log_level_value "$LOG_LEVEL")"
  CURRENT="$(_log_level_value "$1")"
  [ "$CURRENT" -ge "$THRESHOLD" ]
}

## =============================================================================
## Core Log Function
## =============================================================================
_log() {
  LEVEL="$1"; shift
  MSG="$*"
  TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

  ## Build optional PID segment
  PID_PART=""
  if [ "$LOG_SHOW_PID" = "true" ]; then
    PID_PART=" [$$]"
  fi

  ## Store the padded string (len=5) in variable "LEVEL_PADD"
  # printf -v LEVEL_PADD "%5s" "${LEVEL}"
  LEVEL_PADD=$(printf "%5s" "$LEVEL")

  ## Plain text line (always written to log file if set)
  PLAIN_LINE="[${TIMESTAMP}]${PID_PART} [${LEVEL}] ${MSG}"

  ## Colour + label styling per level
  case "$LEVEL" in
    DEBUG) LABEL="${C_DIM}${C_LBLACK}[${LEVEL_PADD}]${C_RESET}" ;;
    INFO)  LABEL="${C_BOLD}${C_CYAN}[${LEVEL_PADD}]${C_RESET}" ;;
    STEP)  LABEL="${C_BOLD}${C_BLUE}[${LEVEL_PADD}]${C_RESET}" ;;
    OK)    LABEL="${C_BOLD}${C_GREEN}[${LEVEL_PADD}]${C_RESET}" ;;
    WARN)  LABEL="${C_BOLD}${C_YELLOW}[${LEVEL_PADD}]${C_RESET}" ;;
    ERROR) LABEL="${C_BOLD}${C_LRED}[${LEVEL_PADD}]${C_RESET}" ;;
    *)     LABEL="[${LEVEL_PADD}]" ;;
  esac

  TIMESTAMP_PART="${C_DIM}${TIMESTAMP}${C_RESET}"
  if [ -n "$PID_PART" ]; then
    PID_COLOUR="${C_DIM}${PID_PART}${C_RESET}"
  else  
    PID_COLOUR=""
  fi

  ## Coloured line to terminal
  printf "${TIMESTAMP_PART}${PID_COLOUR} ${LABEL} ${MSG}\n"

  ## Plain line to log file (no colour codes)
  if [ -n "$LOG_FILE" ]; then
    # printf "%s\n" "$PLAIN_LINE" >> "$LOG_FILE"
    printf '%s\n' "$PLAIN_LINE" | tee -a "${LOG_FILE}" >/dev/null
  fi
}

## =============================================================================
## Public Log Functions
## =============================================================================
log_debug() { if _log_should_print DEBUG; then _log DEBUG "$*"; fi }
log_info()  { if _log_should_print INFO;  then _log INFO  "$*"; fi }
log_step()  { if _log_should_print STEP;  then _log STEP  "$*"; fi }
log_ok()    { if _log_should_print OK;    then _log OK    "$*"; fi }
log_warn()  { if _log_should_print WARN;  then _log WARN  "$*"; fi }
log_error() { if _log_should_print ERROR; then _log ERROR "$*"; fi }

## =============================================================================
## Banner / Divider Helpers
## =============================================================================

## log_banner <text>  — bold header bar
log_banner() {
  LINE="============================================="
  printf "${C_BOLD}${C_LWHITE}%s${C_RESET}\n" "$LINE"
  printf "${C_BOLD}${C_LWHITE}  %s${C_RESET}\n" "$*"
  printf "${C_BOLD}${C_LWHITE}%s${C_RESET}\n" "$LINE"
}

## log_divider  — subtle section separator
log_divider() {
  printf "${C_DIM}---------------------------------------------${C_RESET}\n"
}