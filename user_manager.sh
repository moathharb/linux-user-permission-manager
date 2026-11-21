#!/usr/bin/env bash
# =============================================================================
# user_manager.sh - Linux User & Permission Security Manager
# Phase 1: create users and groups from a CSV file with strong passwords,
#          password expiry and secure home-directory permissions (700/750) + umask.
#
# CSV format (header line optional, '#' lines ignored):
#   username,primary_group,home_mode,shell[,password]
#   alice,developers,700,/bin/bash
#   bob,developers,750,/bin/bash,Str0ng!Passw0rd#1
#
#   home_mode : 700 or 750 (anything else is rejected)
#   password  : optional. If empty a strong random one is generated.
#               If given it must pass the strength check.
#
# Usage:  sudo ./user_manager.sh -f users.csv [-n] [-l logfile] [-c credfile]
#   -f FILE   CSV input file (required)
#   -n        dry run: validate and show actions, change nothing
#   -l FILE   log file   (default /var/log/user_manager.log)
#   -c FILE   file where generated credentials are saved, mode 600
#             (default ./credentials_<date>.txt)
#   -h        help
# =============================================================================

set -u

# ---- settings ---------------------------------------------------------------
PASS_MAX_DAYS=90      # password must be changed every 90 days
PASS_MIN_DAYS=1       # at least 1 day between changes
PASS_WARN_DAYS=7      # warn 7 days before expiry
PASS_MIN_LEN=12
DEFAULT_SHELL="/bin/bash"

CSV_FILE=""
DRY_RUN=0
LOG_FILE="/var/log/user_manager.log"
CRED_FILE="./credentials_$(date +%Y%m%d_%H%M%S).txt"

CNT_OK=0; CNT_SKIP=0; CNT_FAIL=0

# ---- output helpers ---------------------------------------------------------
if [[ -t 1 ]]; then
    R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; N=$'\e[0m'
else
    R=""; G=""; Y=""; B=""; N=""
fi

log() {   # log LEVEL message  -> log file + screen
    local level="$1"; shift
    local msg="$*" ts color
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$ts [$level] $msg" >> "$LOG_FILE" 2>/dev/null
    case "$level" in
        OK)   color="$G" ;;
        WARN) color="$Y" ;;
        ERROR) color="$R" ;;
        *)    color="$B" ;;
    esac
    echo "${color}[$level]${N} $msg"
}

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ---- validation -------------------------------------------------------------
valid_name()  { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; }
valid_mode()  { [[ "$1" == "700" || "$1" == "750" ]]; }
valid_shell() { [[ -x "$1" ]] && grep -qxF "$1" /etc/shells; }

strong_password() {   # >= PASS_MIN_LEN chars with upper, lower, digit and symbol
    local p="$1"
    (( ${#p} >= PASS_MIN_LEN )) || return 1
    [[ "$p" =~ [A-Z] ]]        || return 1
    [[ "$p" =~ [a-z] ]]        || return 1
    [[ "$p" =~ [0-9] ]]        || return 1
    [[ "$p" =~ [^A-Za-z0-9] ]] || return 1
    return 0
}

gen_password() {      # random 16-char password that always passes strong_password
    local p
    while :; do
        p="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^*_+=' < /dev/urandom | head -c 16)"
        strong_password "$p" && { echo "$p"; return; }
    done
}

# ---- actions ----------------------------------------------------------------
ensure_group() {
    local g="$1"
    if getent group "$g" >/dev/null; then
        return 0
    fi
    if (( DRY_RUN )); then log INFO "[dry-run] would create group '$g'"; return 0; fi
    if groupadd "$g"; then log OK "group '$g' created"; else log ERROR "could not create group '$g'"; return 1; fi
}

create_user() {   # username group mode shell password
    local user="$1" grp="$2" mode="$3" shell="$4" pass="$5" generated=0

    if id "$user" >/dev/null 2>&1; then
        log WARN "user '$user' already exists - skipped"; (( CNT_SKIP++ )); return
    fi

    if [[ -z "$pass" ]]; then
        pass="$(gen_password)"; generated=1
    elif ! strong_password "$pass"; then
        log ERROR "user '$user': password too weak (need >=$PASS_MIN_LEN chars with upper, lower, digit, symbol)"
        (( CNT_FAIL++ )); return
    fi

    if (( DRY_RUN )); then
        log INFO "[dry-run] would create '$user' group=$grp home=$mode shell=$shell expiry=${PASS_MAX_DAYS}d"
        (( CNT_OK++ )); return
    fi

    ensure_group "$grp" || { (( CNT_FAIL++ )); return; }

    if ! useradd -m -g "$grp" -s "$shell" -K UMASK=077 "$user"; then
        log ERROR "useradd failed for '$user'"; (( CNT_FAIL++ )); return
    fi

    echo "$user:$pass" | chpasswd || { log ERROR "could not set password for '$user'"; (( CNT_FAIL++ )); return; }

    # password expiry; -d 0 forces a change at first login
    chage -M "$PASS_MAX_DAYS" -m "$PASS_MIN_DAYS" -W "$PASS_WARN_DAYS" -d 0 "$user"

    # secure home directory
    local home; home="$(getent passwd "$user" | cut -d: -f6)"
    chmod "$mode" "$home"
    chown "$user:$grp" "$home"

    # umask for the user's sessions: 077 for private homes, 027 for 750
    local um="077"; [[ "$mode" == "750" ]] && um="027"
    printf '\n# set by user_manager.sh\numask %s\n' "$um" >> "$home/.profile"
    chown "$user:$grp" "$home/.profile"

    log OK "user '$user' created (group=$grp, home=$mode, umask=$um, password expires in ${PASS_MAX_DAYS}d, change forced at first login)"
    if (( generated )); then
        ( umask 077; printf '%s  %s\n' "$user" "$pass" >> "$CRED_FILE" )
    fi
    (( CNT_OK++ ))
}

# ---- main -------------------------------------------------------------------
while getopts ":f:nl:c:h" opt; do
    case "$opt" in
        f) CSV_FILE="$OPTARG" ;;
        n) DRY_RUN=1 ;;
        l) LOG_FILE="$OPTARG" ;;
        c) CRED_FILE="$OPTARG" ;;
        h) usage 0 ;;
        :) echo "Option -$OPTARG needs a value" >&2; usage 1 ;;
        *) echo "Unknown option -$OPTARG" >&2; usage 1 ;;
    esac
done

if [[ -z "$CSV_FILE" ]]; then echo "${R}Error:${N} no input file. Use -f users.csv" >&2; usage 1; fi
if [[ ! -r "$CSV_FILE" ]]; then echo "${R}Error:${N} cannot read '$CSV_FILE'" >&2; exit 1; fi
if [[ $EUID -ne 0 ]] && (( ! DRY_RUN )); then echo "${R}Error:${N} run as root (sudo), or use -n for a dry run" >&2; exit 1; fi

# fall back to a local log if /var/log is not writable (dry run as normal user)
if ! touch "$LOG_FILE" 2>/dev/null; then LOG_FILE="./user_manager.log"; touch "$LOG_FILE"; fi
chmod 600 "$LOG_FILE" 2>/dev/null

log INFO "=== user_manager started: file=$CSV_FILE dry_run=$DRY_RUN ==="

lineno=0
while IFS=',' read -r user grp mode shell pass _; do
    (( lineno++ ))
    user="${user//[$'\r ']/}"                    # strip CR and spaces
    grp="${grp//[$'\r ']/}"; mode="${mode//[$'\r ']/}"
    shell="${shell//[$'\r ']/}"; pass="${pass//$'\r'/}"

    [[ -z "$user" || "$user" == \#* ]] && continue          # blank / comment
    [[ "$user" == "username" ]] && continue                  # header

    if ! valid_name "$user"; then log ERROR "line $lineno: invalid username '$user'"; (( CNT_FAIL++ )); continue; fi
    if [[ "$user" == "root" ]]; then log ERROR "line $lineno: refusing to touch 'root'"; (( CNT_FAIL++ )); continue; fi
    [[ -z "$grp" ]] && grp="$user"
    if ! valid_name "$grp"; then log ERROR "line $lineno: invalid group name '$grp'"; (( CNT_FAIL++ )); continue; fi
    [[ -z "$mode" ]] && mode="700"
    if ! valid_mode "$mode"; then log ERROR "line $lineno: home_mode must be 700 or 750 (got '$mode')"; (( CNT_FAIL++ )); continue; fi
    [[ -z "$shell" ]] && shell="$DEFAULT_SHELL"
    if ! valid_shell "$shell"; then log ERROR "line $lineno: shell '$shell' not installed or not in /etc/shells"; (( CNT_FAIL++ )); continue; fi

    create_user "$user" "$grp" "$mode" "$shell" "$pass"
done < "$CSV_FILE"

log INFO "=== finished: created=$CNT_OK skipped=$CNT_SKIP failed=$CNT_FAIL ==="
[[ -s "$CRED_FILE" ]] && log WARN "generated passwords saved in $CRED_FILE (mode 600) - hand them out, then delete the file"
(( CNT_FAIL > 0 )) && exit 2
exit 0
