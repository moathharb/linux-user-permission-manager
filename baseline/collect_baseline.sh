#!/usr/bin/env bash
# Security baseline collector for the target VM (Phase 1).
# Read-only: it only runs inspection commands. Run with: sudo ./collect_baseline.sh
# Output: ~/baseline_<hostname>_<date>/NN_name.txt  + baseline_summary.txt

set -u
if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo $0" >&2
    exit 1
fi

REAL_HOME="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
OUT="${1:-$REAL_HOME/baseline_$(hostname)_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"

# run <file> <title> <command...> : saves the command line and its output
run() {
    local file="$1" title="$2"; shift 2
    {
        echo "=== $title ==="
        echo "\$ $*"
        echo
        bash -c "$*" 2>&1
    } > "$OUT/$file"
    echo "[ok] $title -> $file"
}

run 00_system.txt        "System information"          'hostnamectl; echo; uname -a; echo; uptime; echo; date'

# --- Users and groups ---
run 01_users.txt         "All user accounts"           'getent passwd | cut -d: -f1,3,4,6,7'
run 02_users_uid0.txt    "Accounts with UID 0"         "awk -F: '\$3==0 {print \$1}' /etc/passwd"
run 03_users_login.txt   "Accounts with a login shell" "grep -vE '(nologin|false)\$' /etc/passwd | cut -d: -f1,3,6,7"
run 04_groups.txt        "All groups"                  'getent group | cut -d: -f1,3,4'
run 05_privileged_groups.txt "Members of sudo/adm/admin groups" 'getent group sudo adm admin root shadow'
run 06_password_status.txt   "Password status (L=locked, NP=no password, P=has password)" 'passwd -S -a'
run 07_empty_passwords.txt   "Accounts with an empty password" "awk -F: '\$2==\"\" {print \$1}' /etc/shadow"
run 08_password_aging.txt    "Password aging policy"   "grep -E '^(PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_WARN_AGE|UMASK)' /etc/login.defs; echo; chage -l \$(logname 2>/dev/null || echo root)"
run 09_last_logins.txt   "Recent logins"               'last -n 15'

# --- sudo rights ---
run 10_sudoers.txt       "sudoers (active lines)"      "grep -vE '^\s*(#|\$)' /etc/sudoers; echo; ls -l /etc/sudoers.d; echo; grep -rvE '^\s*(#|\$)' /etc/sudoers.d/ 2>/dev/null"
run 11_sudo_nopasswd.txt "NOPASSWD entries in sudoers" "grep -rn NOPASSWD /etc/sudoers /etc/sudoers.d/ 2>/dev/null || echo 'none found'"

# --- Files and permissions ---
run 12_suid.txt          "SUID files"                  'find / -xdev -perm -4000 -type f 2>/dev/null | sort'
run 13_sgid.txt          "SGID files"                  'find / -xdev -perm -2000 -type f 2>/dev/null | sort'
run 14_world_writable.txt "World-writable files (excl. /proc,/sys)" 'find / -xdev \( -path /proc -o -path /sys \) -prune -o -type f -perm -0002 -print 2>/dev/null'
run 15_no_owner.txt      "Files with no owner or group" 'find / -xdev \( -nouser -o -nogroup \) 2>/dev/null'
run 16_home_perms.txt    "Home directory permissions"  'ls -ld /home/* /root'
run 17_key_file_perms.txt "Permissions of key files"   'ls -l /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers'

# --- Services and network ---
run 18_services_running.txt "Running services"         'systemctl list-units --type=service --state=running --no-pager'
run 19_services_enabled.txt "Services enabled at boot" 'systemctl list-unit-files --type=service --state=enabled --no-pager'
run 20_listening_ports.txt  "Listening ports"          'ss -tulpn'
run 21_firewall.txt      "Firewall status"             'ufw status verbose; echo; iptables -L -n 2>&1 | head -30'

# --- SSH ---
run 22_sshd_config.txt   "SSH config (active lines)"   "grep -vE '^\s*(#|\$)' /etc/ssh/sshd_config; echo; grep -vE '^\s*(#|\$)' /etc/ssh/sshd_config.d/*.conf 2>/dev/null"
run 23_sshd_effective.txt "SSH effective settings (key ones)" "sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|permitemptypasswords|x11forwarding|maxauthtries|logingracetime|usepam|protocol|allowusers|allowgroups) '"

# --- Short summary for the report ---
{
    echo "BASELINE SUMMARY  $(hostname)  $(date)"
    echo "----------------------------------------"
    echo "User accounts total:            $(getent passwd | wc -l)"
    echo "Accounts with login shell:      $(grep -cvE '(nologin|false)$' /etc/passwd)"
    echo "Accounts with UID 0:            $(awk -F: '$3==0' /etc/passwd | wc -l)"
    echo "Accounts with empty password:   $(awk -F: '$2==""' /etc/shadow | wc -l)"
    echo "Groups total:                   $(getent group | wc -l)"
    echo "NOPASSWD sudoers entries:       $(grep -rh NOPASSWD /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -vc '^\s*#')"
    echo "SUID files:                     $(find / -xdev -perm -4000 -type f 2>/dev/null | wc -l)"
    echo "SGID files:                     $(find / -xdev -perm -2000 -type f 2>/dev/null | wc -l)"
    echo "World-writable files:           $(find / -xdev \( -path /proc -o -path /sys \) -prune -o -type f -perm -0002 -print 2>/dev/null | wc -l)"
    echo "Files with no owner/group:      $(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | wc -l)"
    echo "Running services:               $(systemctl list-units --type=service --state=running --no-legend | wc -l)"
    echo "Listening TCP/UDP sockets:      $(ss -tuln | tail -n +2 | wc -l)"
    echo "SSH PermitRootLogin:            $(sshd -T | awk '/^permitrootlogin/ {print $2}')"
    echo "SSH PasswordAuthentication:     $(sshd -T | awk '/^passwordauthentication/ {print $2}')"
} > "$OUT/baseline_summary.txt"

echo
cat "$OUT/baseline_summary.txt"
echo
echo "Results saved in: $OUT"
