#!/usr/bin/env bash
# === Aetheric Shell: lockscreen system setup (run as root) ===
#
# 1. Installs hyprlock from the official repositories.
# 2. Installs a dedicated PAM stack at /etc/pam.d/hyprlock:
#
#      #%PAM-1.0
#      auth      sufficient  /usr/lib/security/pam_howdy.so   (if present)
#      auth      include     system-local-login
#      account   include     system-local-login
#      password  include     system-local-login
#      session   include     system-local-login
#
#    Howdy (face) runs first and is "sufficient": a match unlocks without the
#    password. A failure, timeout, missing camera or absent enrolled model all
#    fall through to this system's standard local-login stack
#    (system-local-login -> system-login -> system-auth), so the account
#    password always remains a valid unlock. On systems without
#    /etc/pam.d/system-local-login the script includes 'login' instead (that
#    same stack plus an extra pam_nologin check). Nothing is copied out of
#    system-auth and no rule is weakened: pam_faillock, pam_shells, pam_nologin
#    and pam_access keep the distribution's behavior. Shared PAM files
#    (/etc/pam.d/login, system-local-login, system-login, system-auth) are
#    never modified.
# 3. Preserves whatever existed before writing:
#      - the hyprlock package's shipped default (auth include login), and
#      - any file created by an earlier run of this script and later edited.
#    Every overwrite is preceded by a timestamped backup; byte-identical
#    re-runs change nothing and create no backup. Backups never collide
#    (suffix -1, -2, ...).
# 4. Removes the user-local staged hyprlock from the development phase.
#
# Face unlock stays INACTIVE until a Howdy model exists for the user
# (sudo howdy add). No biometric enrollment is performed by this script.
#
# Rollback / precise restore (also printed after every run):
#   sudo cp -a <backup-file> /etc/pam.d/hyprlock   # exact previous state
#   sudo pacman -S hyprlock                        # reinstall package default
#   sudo rm /etc/pam.d/hyprlock                    # hyprlock falls back to /etc/pam.d/su
#   sudo pacman -Rns hyprlock                      # remove the locker entirely
#
# Note: hyprlock's package does not mark /etc/pam.d/hyprlock as a pacman
# backup file, so a future package upgrade may replace this stack; re-run
# this script afterwards (a fresh backup of the replacement is taken).
#
# Usage:
#   sudo ./setup-lockscreen.sh     perform the steps above (root required)
#        ./setup-lockscreen.sh --self-test
#                                  rehearse backup/write/verify logic in a
#                                  private temp dir; needs no root and
#                                  touches nothing outside that dir
#
# Safe to re-run.

set -euo pipefail

PAM_FILE="/etc/pam.d/hyprlock"
PAM_HEADER="#%PAM-1.0"
PAM_MODULE_DIRS=(/usr/lib/security /lib/security)
HOWDY_CANDIDATES=(/usr/lib/security/pam_howdy.so /lib/security/pam_howdy.so)
STAMP="$(date +%Y%m%d-%H%M%S)"

STACK_ACTION=""
STACK_BACKUP=""

say() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

find_howdy_module() {
    local cand
    for cand in "${HOWDY_CANDIDATES[@]}"; do
        if [[ -f $cand ]]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    return 1
}

choose_include_target() { # <pam.d-dir> -> stdout
    local pamd="$1"
    if [[ -f $pamd/system-local-login ]]; then
        printf '%s\n' "system-local-login"
        return 0
    fi
    if [[ -f $pamd/login ]]; then
        printf '%s\n' "login"
        return 0
    fi
    return 1
}

render_stack() { # <howdy-module-path|""> <include-target> -> stdout
    local howdy="$1" stack="$2"
    printf '%s\n' "$PAM_HEADER"
    printf '%s\n' "# /etc/pam.d/hyprlock - GPS lockscreen PAM stack."
    printf '%s\n' "# Managed by my-rice/scripts/setup-lockscreen.sh - edit the script, not this file."
    printf '%s\n' "#"
    printf '%s\n' "# Face unlock (Howdy) is attempted first and is marked \"sufficient\"."
    printf '%s\n' "# If it fails, times out, or no model is enrolled, every section"
    printf '%s\n' "# below falls through to the local-login stack '$stack' -"
    printf '%s\n' "# the account password always remains a valid unlock:"
    printf '%s\n' "#   system-local-login -> system-login -> system-auth"
    printf '%s\n' "# Nothing is copied out of system-auth and no rule is weakened."
    if [[ -n $howdy ]]; then
        printf 'auth      sufficient  %s\n' "$howdy"
    else
        printf '%s\n' "# pam_howdy.so was not found at setup time - password-only stack."
    fi
    printf 'auth      include     %s\n' "$stack"
    printf 'account   include     %s\n' "$stack"
    printf 'password  include     %s\n' "$stack"
    printf 'session   include     %s\n' "$stack"
}

verify_stack() { # <pam-file> <pam.d-dir>; 0 = valid
    local file="$1" pamd="$2"
    local line ln=0 type ctrl mod _extra
    local first_auth="" have_auth=0 have_account=0 have_password=0 have_session=0

    while IFS= read -r line || [[ -n $line ]]; do
        ln=$((ln + 1))
        if [[ $ln -eq 1 ]]; then
            [[ $line == "$PAM_HEADER" ]] || { err "$file:1: first line must be exactly $PAM_HEADER"; return 1; }
            continue
        fi
        [[ -z ${line//[[:space:]]/} ]] && continue
        [[ $line == \#* ]] && continue
        read -r type ctrl mod _extra <<<"$line" || true
        case $type in
            auth | account | password | session) ;;
            *) err "$file:$ln: invalid type '$type'"; return 1 ;;
        esac
        [[ -n ${ctrl:-} && -n ${mod:-} ]] || { err "$file:$ln: expected type, control and module"; return 1; }
        case $ctrl in
            required | requisite | sufficient | optional | include | substack) ;;
            \[*\]) ;;
            *) err "$file:$ln: invalid control '$ctrl'"; return 1 ;;
        esac
        case $type in
            auth) have_auth=1 ;;
            account) have_account=1 ;;
            password) have_password=1 ;;
            session) have_session=1 ;;
        esac
        if [[ $type == auth ]]; then
            if [[ $ctrl == sufficient && -n $first_auth ]]; then
                err "$file:$ln: face-auth (sufficient) must be the first auth rule"
                return 1
            fi
            [[ -n $first_auth ]] || first_auth="$ctrl"
        fi
        if [[ $ctrl == include || $ctrl == substack ]]; then
            [[ -f $pamd/$mod ]] || { err "$file:$ln: include target '$mod' not found under $pamd"; return 1; }
        elif [[ $mod == /* ]]; then
            [[ -f $mod ]] || { err "$file:$ln: module '$mod' not found"; return 1; }
        else
            local d found=""
            for d in "${PAM_MODULE_DIRS[@]}"; do [[ -f $d/$mod ]] && found=1; done
            [[ -n $found ]] || { err "$file:$ln: module '$mod' not found in ${PAM_MODULE_DIRS[*]}"; return 1; }
        fi
    done <"$file"

    ((have_auth && have_account && have_password && have_session)) \
        || { err "$file: stack must define auth, account, password and session rules"; return 1; }
    return 0
}

make_backup() { # <file> <desired-path> -> stdout actual path
    local src="$1" cand="$2" n=0
    while [[ -e $cand ]]; do
        n=$((n + 1))
        cand="$2-$n"
    done
    cp -a "$src" "$cand" || return 1
    printf '%s\n' "$cand"
}

install_stack() { # <target> <content-file> <pam.d-dir>
    STACK_ACTION=""
    STACK_BACKUP=""
    verify_stack "$2" "$3" || die "refusing to install: generated stack failed verification (nothing written)"

    local iargs=(-m 0644)
    ((EUID == 0)) && iargs+=(-o root -g root)

    if [[ -f $1 ]]; then
        if cmp -s "$1" "$2"; then
            STACK_ACTION="unchanged"
            return 0
        fi
        STACK_BACKUP="$(make_backup "$1" "$1.bak-$STAMP")" || die "could not back up $1"
        install "${iargs[@]}" "$2" "$1" || die "could not write $1"
        cmp -s "$1" "$2" || {
            cp -a "$STACK_BACKUP" "$1"
            die "post-write check failed; original restored from $STACK_BACKUP"
        }
        STACK_ACTION="updated"
        return 0
    fi

    install "${iargs[@]}" "$2" "$1" || die "could not write $1"
    cmp -s "$1" "$2" || {
        rm -f "$1"
        die "post-write check failed; partial file removed"
    }
    STACK_ACTION="created"
    return 0
}

main() {
    ((EUID == 0)) || die "installs a package and writes $PAM_FILE - run: sudo $0"

    local user_name="${SUDO_USER:-rice}"
    local user_home
    user_home="$(getent passwd "$user_name" | cut -d: -f6)" || true
    [[ -n $user_home ]] || die "could not resolve home directory for '$user_name'"

    local howdy=""
    howdy="$(find_howdy_module)" || true

    local include_target
    include_target="$(choose_include_target /etc/pam.d)" \
        || die "neither /etc/pam.d/system-local-login nor /etc/pam.d/login exists - unsupported PAM layout"

    local content
    content="$(mktemp)"
    trap "rm -f '$content'" EXIT
    render_stack "$howdy" "$include_target" >"$content"
    verify_stack "$content" /etc/pam.d || die "generated stack failed pre-flight verification (nothing written)"

    say "==> [1/6] Installing hyprlock from the official repositories"
    pacman -S --needed --noconfirm hyprlock

    say "==> [2/6] Inspecting current $PAM_FILE"
    if [[ -f $PAM_FILE ]]; then
        say "    found existing file (sha256 $(sha256sum "$PAM_FILE" | cut -c1-16)...):"
        sed 's/^/      | /' "$PAM_FILE" | head -n 12
        if grep -q "PAM configuration file for hyprlock" "$PAM_FILE"; then
            say "      (this is the hyprlock package's shipped default)"
        fi
    else
        say "    no existing file"
    fi

    say "==> [3/6] Writing lockscreen PAM stack"
    if [[ -n $howdy ]]; then
        say "    face unlock via pam_howdy: enabled, inactive until enrolled"
        say "    module: $howdy (sha256 $(sha256sum "$howdy" | cut -c1-16)...)"
    else
        say "    WARNING: pam_howdy.so not found - writing password-only stack"
    fi
    say "    password fallback: include $include_target"
    install_stack "$PAM_FILE" "$content" /etc/pam.d
    case $STACK_ACTION in
        created) say "    wrote $PAM_FILE (no previous file existed)" ;;
        updated)
            say "    previous file preserved: $STACK_BACKUP"
            say "    wrote $PAM_FILE"
            ;;
        unchanged) say "    $PAM_FILE already matches this script - no write, no backup" ;;
    esac

    say "==> [4/6] Howdy enrollment status"
    if [[ -f /etc/howdy/config.ini ]]; then
        if [[ -f "/etc/howdy/models/${user_name}.dat" ]]; then
            say "    model for '$user_name': present"
        else
            say "    model for '$user_name': MISSING - face unlock inactive"
            say "    enroll manually when ready (interactive, done by you):  sudo howdy add"
        fi
    else
        say "    WARNING: /etc/howdy/config.ini not found - Howdy will decline face auth"
    fi

    say "==> [5/6] Removing user-local staged hyprlock"
    local staged_dir="$user_home/.local/opt/hyprlock"
    local staged_link="$user_home/.local/bin/hyprlock"
    if [[ -L $staged_link && $(readlink -f -- "$staged_link") == "$staged_dir/bin/hyprlock" ]]; then
        rm -f -- "$staged_link"
        say "    removed symlink: $staged_link"
    fi
    if [[ -x $staged_dir/bin/hyprlock ]]; then
        rm -rf -- "$staged_dir"
        say "    removed: $staged_dir"
    fi

    say "==> [6/6] Verifying"
    bash -n "$0"
    verify_stack "$PAM_FILE" /etc/pam.d
    say "    PAM stack: valid ($(grep -c -v '^#' "$PAM_FILE") active rule(s) in $PAM_FILE)"
    local user_shell
    user_shell="$(getent passwd "$user_name" | cut -d: -f7)"
    if [[ -n $user_shell ]] && ! grep -qx "$user_shell" /etc/shells; then
        say "    WARNING: login shell $user_shell is not listed in /etc/shells;"
        say "             pam_shells will reject password unlock until it is added"
    fi
    hyprlock --version
    say "    binary: $(command -v hyprlock)"

    say ""
    say "Rollback / precise restore"
    if [[ -n $STACK_BACKUP ]]; then
        say "  exact previous state:     sudo cp -a '$STACK_BACKUP' $PAM_FILE"
        say "  (backup taken this run:   $STACK_BACKUP)"
    else
        say "  no previous $PAM_FILE existed - nothing to restore"
        say "  safe removal:             sudo rm $PAM_FILE"
        say "                            (hyprlock then uses /etc/pam.d/su)"
    fi
    say "  package default:          sudo pacman -S hyprlock"
    say "  remove locker:            sudo pacman -Rns hyprlock"
    say "  note: a future hyprlock package upgrade may replace this stack"
    say "        (not a pacman backup file); re-run this script afterwards."

    say ""
    say "Done. Test the lock at a safe moment (keep a TTY available):"
    say "  hyprlock            # lock now; unlock with password (face optional)"
    say "  loginctl lock-session"
    say "If a lock ever misbehaves: switch to a TTY and run  pkill -x hyprlock"
}

run_self_test() {
    say "== setup-lockscreen.sh self-test (private temp dir; /etc untouched) =="
    local tmp
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/setup-lockscreen-test.XXXXXX")"
    trap "rm -rf '$tmp'" EXIT

    local pass=0 fail=0
    ok() { pass=$((pass + 1)); printf '  PASS  %s\n' "$1"; }
    no() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

    mkdir -p "$tmp/pam.d"
    local stub
    for stub in login system-local-login system-login system-auth su; do
        printf '%s\n' "$PAM_HEADER" >"$tmp/pam.d/$stub"
    done

    local content="$tmp/stack" content_nohowdy="$tmp/stack-nohowdy"
    local include_target="system-local-login"
    local target="$tmp/pam.d/hyprlock"

    render_stack /usr/lib/security/pam_howdy.so "$include_target" >"$content"
    render_stack "" "$include_target" >"$content_nohowdy"

    if [[ $(head -n1 "$content") == "$PAM_HEADER" ]]; then ok "header is exactly $PAM_HEADER"; else no "header is exactly $PAM_HEADER"; fi
    if [[ $(grep -c "^auth      include     $include_target\$" "$content") -eq 1 ]]; then ok "auth includes $include_target once"; else no "auth includes $include_target once"; fi
    if [[ $(grep -c -E '^(auth|account|password|session) ' "$content") -eq 5 ]]; then ok "five stacked rules (face + 4 includes)"; else no "five stacked rules"; fi
    if grep -qxF "auth      sufficient  /usr/lib/security/pam_howdy.so" "$content"; then ok "face rule uses verified absolute path"; else no "face rule uses verified absolute path"; fi
    if verify_stack "$content" "$tmp/pam.d" 2>/dev/null; then ok "verify accepts howdy stack"; else no "verify accepts howdy stack"; fi
    if verify_stack "$content_nohowdy" "$tmp/pam.d" 2>/dev/null; then ok "verify accepts password-only stack"; else no "verify accepts password-only stack"; fi
    if grep -qE '^auth[[:space:]]+sufficient' "$content_nohowdy"; then no "password-only stack has no sufficient rule"; else ok "password-only stack has no sufficient rule"; fi

    if [[ $(choose_include_target "$tmp/pam.d") == system-local-login ]]; then ok "include target prefers system-local-login"; else no "include target prefers system-local-login"; fi
    mkdir -p "$tmp/pam-login-only"
    printf '%s\n' "$PAM_HEADER" >"$tmp/pam-login-only/login"
    if [[ $(choose_include_target "$tmp/pam-login-only") == login ]]; then ok "include target falls back to login"; else no "include target falls back to login"; fi
    mkdir -p "$tmp/pam-empty"
    if choose_include_target "$tmp/pam-empty" >/dev/null 2>&1; then no "missing login stacks rejected"; else ok "missing login stacks rejected"; fi

    printf '%s\n' "# PAM configuration file for hyprlock" "auth        include     login" >"$target"
    install_stack "$target" "$content" "$tmp/pam.d"
    local pkg_backup="${STACK_BACKUP:-}"
    if [[ $STACK_ACTION == updated && -n $pkg_backup && -f $pkg_backup ]]; then ok "package default preserved before replace"; else no "package default preserved before replace"; fi
    if [[ -n $pkg_backup ]] && grep -qxF "auth        include     login" "$pkg_backup"; then ok "package default backup intact"; else no "package default backup intact"; fi
    if cmp -s "$target" "$content"; then ok "package default replaced by our stack"; else no "package default replaced by our stack"; fi
    if [[ $(ls "$tmp/pam.d" | grep -c '\.bak-' || true) -eq 1 ]]; then ok "exactly one backup after package-default replace"; else no "exactly one backup after package-default replace"; fi

    install_stack "$target" "$content" "$tmp/pam.d"
    if [[ $STACK_ACTION == unchanged && -z $STACK_BACKUP ]]; then ok "identical re-run is a no-op"; else no "identical re-run is a no-op"; fi
    if [[ $(ls "$tmp/pam.d" | grep -c '\.bak-' || true) -eq 1 ]]; then ok "no backup created on no-op"; else no "no backup created on no-op"; fi

    printf '# user edit one\n' >>"$target"
    install_stack "$target" "$content" "$tmp/pam.d"
    local first_backup="${STACK_BACKUP:-}"
    if [[ $STACK_ACTION == updated && -n $first_backup && -f $first_backup ]]; then ok "edited managed file backed up then updated"; else no "edited managed file backed up then updated"; fi
    if [[ -n $first_backup ]] && grep -q 'Managed by my-rice' "$first_backup"; then ok "managed marker did not suppress the backup"; else no "managed marker did not suppress the backup"; fi
    if [[ -n $first_backup ]] && grep -qxF '# user edit one' "$first_backup"; then ok "backup preserves the user edit"; else no "backup preserves the user edit"; fi
    if cmp -s "$target" "$content"; then ok "target restored to rendered stack"; else no "target restored to rendered stack"; fi

    printf '# user edit two\n' >>"$target"
    install_stack "$target" "$content" "$tmp/pam.d"
    local second_backup="${STACK_BACKUP:-}"
    if [[ -n $second_backup && $second_backup != "$first_backup" && -f $second_backup ]]; then ok "second overwrite gets a unique backup name"; else no "second overwrite gets a unique backup name"; fi
    if [[ $second_backup == *-2 ]]; then ok "collision suffix -2 used"; else no "collision suffix -2 used"; fi
    if [[ -n $second_backup ]] && grep -qxF '# user edit two' "$second_backup"; then ok "second backup preserves its own state"; else no "second backup preserves its own state"; fi
    if [[ $(ls "$tmp/pam.d" | grep -c '\.bak-' || true) -eq 3 ]]; then ok "three distinct backups exist"; else no "three distinct backups exist"; fi

    cp -a "$pkg_backup" "$target"
    if grep -qxF "auth        include     login" "$target" && ! grep -q 'Managed by my-rice' "$target"; then ok "restore from package-default backup reproduces original"; else no "restore from package-default backup reproduces original"; fi

    local fresh="$tmp/pam.d/hyprlock-fresh"
    install_stack "$fresh" "$content" "$tmp/pam.d"
    if [[ $STACK_ACTION == created && -z $STACK_BACKUP ]]; then ok "fresh install creates file"; else no "fresh install creates file"; fi
    if cmp -s "$fresh" "$content"; then ok "installed content matches render"; else no "installed content matches render"; fi
    if [[ $(stat -c %a "$fresh") == 644 ]]; then ok "installed mode is 644"; else no "installed mode is 644"; fi

    printf 'auth include login\n' >"$tmp/bad1"
    if verify_stack "$tmp/bad1" "$tmp/pam.d" 2>/dev/null; then no "missing header rejected"; else ok "missing header rejected"; fi
    {
        printf '%s\n' "$PAM_HEADER"
        printf '%s\n' "auth      include     login"
        printf '%s\n' "auth      sufficient  /usr/lib/security/pam_howdy.so"
        printf '%s\n' "account   include     login"
        printf '%s\n' "password  include     login"
        printf '%s\n' "session   include     login"
    } >"$tmp/bad2"
    if verify_stack "$tmp/bad2" "$tmp/pam.d" 2>/dev/null; then no "face rule after include rejected"; else ok "face rule after include rejected"; fi
    {
        printf '%s\n' "$PAM_HEADER"
        printf '%s\n' "auth      include     nonexistent-stack"
        printf '%s\n' "account   include     login"
        printf '%s\n' "password  include     login"
        printf '%s\n' "session   include     login"
    } >"$tmp/bad3"
    if verify_stack "$tmp/bad3" "$tmp/pam.d" 2>/dev/null; then no "missing include target rejected"; else ok "missing include target rejected"; fi
    {
        printf '%s\n' "$PAM_HEADER"
        printf '%s\n' "auth      include     login"
    } >"$tmp/bad4"
    if verify_stack "$tmp/bad4" "$tmp/pam.d" 2>/dev/null; then no "incomplete stack rejected"; else ok "incomplete stack rejected"; fi

    printf '\n%d passed, %d failed\n' "$pass" "$fail"
    ((fail == 0))
}

case "${1:-}" in
    "") main ;;
    --self-test) run_self_test ;;
    --help | -h) awk 'NR > 1 { if ($0 == "") exit; sub(/^# ?/, ""); print }' "$0" ;;
    *)
        err "unknown argument: $1 (try --help)"
        exit 2
        ;;
esac
