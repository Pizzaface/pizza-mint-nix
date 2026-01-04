#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

log() {
  echo "[nix-bootstrap] $*"
}

ensure_home() {
  if [[ -n "${HOME:-}" ]]; then
    return 0
  fi

  local passwd_home
  passwd_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
  if [[ -n "$passwd_home" ]]; then
    export HOME="$passwd_home"
  else
    export HOME="/root"
  fi
}

as_user() {
  local user="$1"
  shift
  if command -v sudo >/dev/null 2>&1; then
    sudo -H -u "$user" -- "$@"
  else
    runuser -u "$user" -- "$@"
  fi
}

export DEBIAN_FRONTEND=noninteractive

# If bootstrap already completed, exit before any network activity unless explicitly forced.
force=0
for arg in "${@:-}"; do
  case "$arg" in
    --force) force=1 ;;
    *) ;;
  esac
done
if [[ "$force" -ne 1 && -f /var/lib/nix-bootstrap/done ]]; then
  exit 0
fi

# Allow overrides without rebuilding the ISO.
if [[ -f /etc/default/nix-bootstrap ]]; then
  # shellcheck disable=SC1091
  . /etc/default/nix-bootstrap
fi

BOOTSTRAP_USER="${BOOTSTRAP_USER:-jordan}"
BOOTSTRAP_REPO="${BOOTSTRAP_REPO:-https://github.com/Pizzaface/pizza-mint-nix.git}"
BOOTSTRAP_REF="${BOOTSTRAP_REF:-main}"
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-/home/${BOOTSTRAP_USER}/pizza-mint-nix}"

ensure_home

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl git
fi

if ! id "$BOOTSTRAP_USER" >/dev/null 2>&1; then
  log "User '$BOOTSTRAP_USER' does not exist; set BOOTSTRAP_USER in /etc/default/nix-bootstrap."
  exit 1
fi

user_home="$(getent passwd "$BOOTSTRAP_USER" | cut -d: -f6 || true)"
if [[ -z "$user_home" ]]; then
  log "Could not resolve home directory for '$BOOTSTRAP_USER'."
  exit 1
fi

case "$BOOTSTRAP_DIR" in
  ""|"/"|"/home"|"/home/"|"/root"|"/root/"|"/var"|"/var/"|"/etc"|"/etc/"|"/usr"|"/usr/"|"/bin"|"/bin/"|"/sbin"|"/sbin/"|"/opt"|"/opt/")
    log "Refusing to use unsafe BOOTSTRAP_DIR='$BOOTSTRAP_DIR'."
    exit 1
    ;;
esac
if [[ "$BOOTSTRAP_DIR" != /* ]]; then
  log "BOOTSTRAP_DIR must be an absolute path; got '$BOOTSTRAP_DIR'."
  exit 1
fi
if [[ "$BOOTSTRAP_DIR" == "$user_home" || "$BOOTSTRAP_DIR" == "${user_home}/" ]]; then
  log "Refusing to use BOOTSTRAP_DIR equal to the user's home directory: '$BOOTSTRAP_DIR'."
  exit 1
fi

mkdir -p "$BOOTSTRAP_DIR"
chown -R "$BOOTSTRAP_USER":"$BOOTSTRAP_USER" "$BOOTSTRAP_DIR"

if [[ -d "$BOOTSTRAP_DIR/.git" ]]; then
  as_user "$BOOTSTRAP_USER" git -C "$BOOTSTRAP_DIR" remote set-url origin "$BOOTSTRAP_REPO" || true
  as_user "$BOOTSTRAP_USER" git -C "$BOOTSTRAP_DIR" fetch --prune origin
  if as_user "$BOOTSTRAP_USER" git -C "$BOOTSTRAP_DIR" rev-parse --verify --quiet "origin/$BOOTSTRAP_REF" >/dev/null; then
    as_user "$BOOTSTRAP_USER" git -C "$BOOTSTRAP_DIR" checkout -B "$BOOTSTRAP_REF" "origin/$BOOTSTRAP_REF" >/dev/null 2>&1 || true
    as_user "$BOOTSTRAP_USER" git -C "$BOOTSTRAP_DIR" reset --hard "origin/$BOOTSTRAP_REF" >/dev/null 2>&1 || true
  else
    as_user "$BOOTSTRAP_USER" git -C "$BOOTSTRAP_DIR" checkout -f "$BOOTSTRAP_REF" >/dev/null 2>&1 || true
  fi
else
  rm -rf "$BOOTSTRAP_DIR"
  if ! as_user "$BOOTSTRAP_USER" git clone --depth 1 --branch "$BOOTSTRAP_REF" "$BOOTSTRAP_REPO" "$BOOTSTRAP_DIR"; then
    as_user "$BOOTSTRAP_USER" git clone "$BOOTSTRAP_REPO" "$BOOTSTRAP_DIR"
    as_user "$BOOTSTRAP_USER" git -C "$BOOTSTRAP_DIR" checkout -f "$BOOTSTRAP_REF" >/dev/null 2>&1 || true
  fi
fi

impl="$BOOTSTRAP_DIR/bootstrap/nix-bootstrap-impl.sh"
if [[ ! -f "$impl" ]]; then
  log "Bootstrap implementation not found at '$impl'."
  exit 1
fi

chmod +x "$impl" || true
exec "$impl" "$@"
