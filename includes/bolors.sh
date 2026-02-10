#!/bin/bash
# Path: includes\bolors.sh
# This is a script that defines color variables, logging functions and utilities
# for consistent terminal output formatting.

#Reset and Attributes:
reset="\e[0m"

# Text Attributes:
bold="\e[1m"
dim="\e[2m"
italic="\e[3m"
underline="\e[4m"
double_underline="\e[21m"
blink_slow="\e[5m"
blink_rapid="\e[6m"
reverse="\e[7m"
conceal="\e[8m"
strike="\e[9m"
fraktur="\e[20m"
normal_intensity="\e[22m"
no_italic="\e[23m"
no_underline="\e[24m"
no_blink="\e[25m"
proportional_spacing="\e[26m"
no_reverse="\e[27m"
reveal="\e[28m"
no_strike="\e[29m"
framed="\e[51m"
encircled="\e[52m"
overlined="\e[53m"
no_frame_or_encircle="\e[54m"
no_overline="\e[55m"

# Foreground Text Colors:
black="\e[30m"
red="\e[31m"
green="\e[32m"
yellow="\e[33m"
blue="\e[34m"
magenta="\e[35m"
cyan="\e[36m"
white="\e[37m"
default_fg="\e[39m"
black_bright='\033[90m'
red_bright='\033[91m'
green_bright='\033[92m'
yellow_bright='\033[93m'
blue_bright='\033[94m'
magenta_bright='\033[95m'
cyan_bright='\033[96m'
white_bright='\033[97m'

# Background Text Colors:
bg_black="\e[40m"
bg_red="\e[41m"
bg_green="\e[42m"
bg_yellow="\e[43m"
bg_blue="\e[44m"
bg_magenta="\e[45m"
bg_cyan="\e[46m"
bg_white="\e[47m"
default_bg="\e[49m"
bg_black_bright='\033[100m'
bg_red_bright='\033[101m'
bg_green_bright='\033[102m'
bg_yellow_bright='\033[103m'
bg_blue_bright='\033[104m'
bg_magenta_bright='\033[105m'
bg_cyan_bright='\033[106m'
bg_white_bright='\033[107m'

# Other:
disable_proportional_spacing="\e[50m"

# Enhanced color functions
color() {
    local c="$1"
    shift
    echo -ne "${!c}$*${reset}"
}

echoc() {
    local c="$1"
    shift
    echo -ne "${!c}$*${reset}\n"
}

# Logging system
log() {
    local level="$1"
    shift
    case "$level" in
        "debug")
            [ ${verbose:-0} -eq 1 ] && echoc cyan "[DEBUG] $*"
            ;;
        "info")
            echoc blue "[INFO] $*"
            ;;
        "success")
            echoc green "[SUCCESS] $*"
            ;;
        "warn")
            echoc yellow "[WARN] $*"
            ;;
        "error")
            echoc red_bright "[ERROR] $*" >&2
            ;;
    esac
}

# Shorthand logging functions
debug() { log "debug" "$@"; }
info() { log "info" "$@"; }
success() { log "success" "$@"; }
warn() { log "warn" "$@"; }
error() { log "error" "$@"; }

# Utility function for status messages
status() {
    local status="$1"
    shift
    case "$status" in
        "ok") echoc green "✓ $*" ;;
        "fail") echoc red "✗ $*" ;;
        "warn") echoc yellow "! $*" ;;
        "info") echoc blue "i $*" ;;
    esac
}

# Example usage:
# debug "Debugging information"
# info "General information"
# success "Operation completed successfully"
# warn "Warning message"
# error "Error occurred"
# status ok "Task completed"
# status fail "Task failed"