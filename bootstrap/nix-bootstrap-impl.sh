#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

usage() {
  cat <<'EOF'
Usage: nix-bootstrap-impl.sh [--force]

Runs first-boot provisioning:
  - Installs Nix (multi-user daemon) if missing
  - Enables flakes
  - Installs a few baseline packages + Flatpaks
  - Applies Home Manager config from this repo

Options:
  --force   Run even if already completed
EOF
}

force=0
for arg in "${@:-}"; do
  case "$arg" in
    --force) force=1 ;;
    -h|--help) usage; exit 0 ;;
    *) ;;
  esac
done

SENTINEL_DIR="/var/lib/nix-bootstrap"
SENTINEL_FILE="$SENTINEL_DIR/done"

if [[ "$force" -ne 1 && -f "$SENTINEL_FILE" ]]; then
  exit 0
fi

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

log() {
  echo "[nix-bootstrap] $*"
}

export DEBIAN_FRONTEND=noninteractive

if [[ -f /etc/default/nix-bootstrap ]]; then
  # shellcheck disable=SC1091
  . /etc/default/nix-bootstrap
fi

BOOTSTRAP_USER="${BOOTSTRAP_USER:-jordan}"

if ! id "$BOOTSTRAP_USER" >/dev/null 2>&1; then
  log "User '$BOOTSTRAP_USER' does not exist; set BOOTSTRAP_USER in /etc/default/nix-bootstrap."
  exit 1
fi

ensure_home

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

apt_install() {
  apt-get install -y --no-install-recommends "$@"
}

apt-get update
apt_install ca-certificates curl git xz-utils flatpak gpg sudo

# Ensure Flathub is available.
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

if [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  if [[ -z "${HOME:-}" ]]; then
    log "\$HOME is not set; refusing to run Nix installer."
    exit 1
  fi

  log "Installing Nix (multi-user daemon)..."
  curl --proto '=https' --tlsv1.2 -fsSL https://nixos.org/nix/install | sh -s -- --daemon
fi

mkdir -p /etc/nix
if [[ ! -f /etc/nix/nix.conf ]]; then
  touch /etc/nix/nix.conf
fi
if ! grep -qE '^\s*experimental-features\s*=.*\bflakes\b' /etc/nix/nix.conf; then
  printf '\nexperimental-features = nix-command flakes\n' >>/etc/nix/nix.conf
fi

if getent group nix-users >/dev/null 2>&1; then
  usermod -aG nix-users "$BOOTSTRAP_USER" || true
fi

systemctl daemon-reload || true
systemctl enable --now nix-daemon.socket >/dev/null 2>&1 || true
systemctl start nix-daemon.service >/dev/null 2>&1 || true

# --- GUI apps: Flatpak-first ---
flatpak install -y flathub com.brave.Browser || true
flatpak install -y flathub com.valvesoftware.Steam || true
flatpak install -y flathub com.visualstudio.code || true

# --- APT installs when Flatpak isn't the right fit ---
apt_install wine winetricks

# --- Keyboard: swap Ctrl and Alt (X11) ---
apt_install x11-xkb-utils
cat >/etc/profile.d/ctrl-alt-swap.sh <<'EOF'
setxkbmap -option ctrl:swap_lalt_lctl >/dev/null 2>&1 || true
EOF

# --- JetBrains Toolbox (optional convenience) ---
apt_install tar
JB_DIR="/opt/jetbrains-toolbox"
JB_BIN="/usr/local/bin/jetbrains-toolbox"
JB_DESKTOP="/usr/share/applications/jetbrains-toolbox.desktop"
TOOLBOX_TAR_URL="https://data.services.jetbrains.com/products/download?platform=linux&code=TBA"

mkdir -p "$JB_DIR"
tmpdir="$(mktemp -d)"
if curl -fL "$TOOLBOX_TAR_URL" -o "$tmpdir/toolbox.tar.gz"; then
  if tar -xzf "$tmpdir/toolbox.tar.gz" -C "$tmpdir"; then
    toolbox_folder="$(find "$tmpdir" -maxdepth 1 -type d -name "jetbrains-toolbox-*" | head -n 1 || true)"
    if [[ -n "${toolbox_folder:-}" && -d "$toolbox_folder" ]]; then
      rm -rf "$JB_DIR/current"
      mkdir -p "$JB_DIR/current"
      cp -a "$toolbox_folder"/* "$JB_DIR/current/"
      chmod -R a+rX "$JB_DIR"
      ln -sf "$JB_DIR/current/jetbrains-toolbox" "$JB_BIN"
      cat >"$JB_DESKTOP" <<'EOF'
[Desktop Entry]
Name=JetBrains Toolbox
Comment=Manage JetBrains IDE installations
Exec=/usr/local/bin/jetbrains-toolbox
Terminal=false
Type=Application
Categories=Development;IDE;
EOF
      chmod 644 "$JB_DESKTOP"
    else
      log "JetBrains Toolbox download did not unpack correctly; skipping."
    fi
  else
    log "JetBrains Toolbox archive extract failed; skipping."
  fi
else
  log "JetBrains Toolbox download failed; skipping."
fi

rm -rf "$tmpdir"

# Apply Home Manager config from this repo.
as_user "$BOOTSTRAP_USER" bash -lc "
  set -euo pipefail
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  export NIX_CONFIG='experimental-features = nix-command flakes'
  cd '$repo_root'
  nix run github:nix-community/home-manager -- switch --flake '.#${BOOTSTRAP_USER}@mint'
"

mkdir -p "$SENTINEL_DIR"
touch "$SENTINEL_FILE"
