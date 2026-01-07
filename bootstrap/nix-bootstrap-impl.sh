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

# --- Desktop progress indicator ---
PROGRESS_PIPE=""
PROGRESS_PID=""

# Find user's display environment for GUI notifications
find_user_display() {
  local user="$1"
  # Try common display values
  for display in ":0" ":1"; do
    if [[ -e "/tmp/.X11-unix/X${display#:}" ]]; then
      echo "$display"
      return 0
    fi
  done
  # Fallback: check user's processes for DISPLAY
  local user_display
  user_display="$(pgrep -u "$user" -a 2>/dev/null | head -1 | xargs -0 -I{} bash -c 'tr "\0" "\n" < /proc/{}/environ 2>/dev/null | grep ^DISPLAY= | cut -d= -f2' || true)"
  if [[ -n "$user_display" ]]; then
    echo "$user_display"
    return 0
  fi
  echo ":0"
}

# Run a command on the user's desktop
gui_as_user() {
  local user="$1"
  shift
  local display
  display="$(find_user_display "$user")"
  local xauthority="/home/$user/.Xauthority"

  if [[ ! -e "$xauthority" ]]; then
    xauthority="/run/user/$(id -u "$user")/gdm/Xauthority"
  fi

  as_user "$user" env \
    DISPLAY="$display" \
    XAUTHORITY="$xauthority" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$user")/bus" \
    "$@"
}

# Start the progress dialog
start_progress() {
  if [[ "$BOOTSTRAP_TEST_MODE" == "1" ]]; then
    return 0
  fi

  # Ensure zenity is available
  if ! command -v zenity >/dev/null 2>&1; then
    log "zenity not available; skipping progress dialog."
    return 0
  fi

  PROGRESS_PIPE="$(mktemp -u)"
  mkfifo "$PROGRESS_PIPE"

  # Start zenity progress dialog in background
  gui_as_user "$BOOTSTRAP_USER" zenity --progress \
    --title="System Setup" \
    --text="Starting first-boot setup..." \
    --percentage=0 \
    --auto-close \
    --no-cancel \
    --width=400 \
    < "$PROGRESS_PIPE" &
  PROGRESS_PID=$!

  # Open the pipe for writing (keeps it open)
  exec 3>"$PROGRESS_PIPE"
}

# Update progress: update_progress <percentage> <message>
update_progress() {
  local pct="$1"
  local msg="$2"
  log "$msg"

  if [[ -n "$PROGRESS_PIPE" && -p "$PROGRESS_PIPE" ]]; then
    echo "$pct" >&3 2>/dev/null || true
    echo "# $msg" >&3 2>/dev/null || true
  fi
}

# Close progress dialog
close_progress() {
  if [[ -n "$PROGRESS_PIPE" ]]; then
    echo "100" >&3 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
    rm -f "$PROGRESS_PIPE" 2>/dev/null || true
  fi
  if [[ -n "$PROGRESS_PID" ]]; then
    wait "$PROGRESS_PID" 2>/dev/null || true
  fi
}

# Show completion notification
show_complete_notification() {
  if [[ "$BOOTSTRAP_TEST_MODE" == "1" ]]; then
    return 0
  fi

  if command -v zenity >/dev/null 2>&1; then
    gui_as_user "$BOOTSTRAP_USER" zenity --info \
      --title="Setup Complete" \
      --text="First-boot setup finished successfully!\n\nYou may need to log out and back in for all changes to take effect." \
      --width=350 &
  fi
}

# Cleanup on exit
cleanup_progress() {
  close_progress
}
trap cleanup_progress EXIT

export DEBIAN_FRONTEND=noninteractive

if [[ -f /etc/default/nix-bootstrap ]]; then
  # shellcheck disable=SC1091
  . /etc/default/nix-bootstrap
fi

BOOTSTRAP_USER="${BOOTSTRAP_USER:-jordan}"
BOOTSTRAP_TEST_MODE="${BOOTSTRAP_TEST_MODE-}"

BOOTSTRAP_SKIP_NIX_INSTALL="${BOOTSTRAP_SKIP_NIX_INSTALL-}"
BOOTSTRAP_SKIP_SYSTEMD="${BOOTSTRAP_SKIP_SYSTEMD-}"
BOOTSTRAP_SKIP_FLATPAK="${BOOTSTRAP_SKIP_FLATPAK-}"
BOOTSTRAP_SKIP_APT_EXTRAS="${BOOTSTRAP_SKIP_APT_EXTRAS-}"
BOOTSTRAP_SKIP_JETBRAINS="${BOOTSTRAP_SKIP_JETBRAINS-}"
BOOTSTRAP_SKIP_HOME_MANAGER="${BOOTSTRAP_SKIP_HOME_MANAGER-}"
BOOTSTRAP_SKIP_DOCKER="${BOOTSTRAP_SKIP_DOCKER-}"
BOOTSTRAP_SKIP_TAILSCALE="${BOOTSTRAP_SKIP_TAILSCALE-}"

: "${BOOTSTRAP_TEST_MODE:=0}"

if [[ "$BOOTSTRAP_TEST_MODE" == "1" ]]; then
  : "${BOOTSTRAP_SKIP_NIX_INSTALL:=1}"
  : "${BOOTSTRAP_SKIP_SYSTEMD:=1}"
  : "${BOOTSTRAP_SKIP_FLATPAK:=1}"
  : "${BOOTSTRAP_SKIP_APT_EXTRAS:=1}"
  : "${BOOTSTRAP_SKIP_JETBRAINS:=1}"
  : "${BOOTSTRAP_SKIP_HOME_MANAGER:=1}"
  : "${BOOTSTRAP_SKIP_DOCKER:=1}"
  : "${BOOTSTRAP_SKIP_TAILSCALE:=1}"
else
  : "${BOOTSTRAP_SKIP_NIX_INSTALL:=0}"
  : "${BOOTSTRAP_SKIP_SYSTEMD:=0}"
  : "${BOOTSTRAP_SKIP_FLATPAK:=0}"
  : "${BOOTSTRAP_SKIP_APT_EXTRAS:=0}"
  : "${BOOTSTRAP_SKIP_JETBRAINS:=0}"
  : "${BOOTSTRAP_SKIP_HOME_MANAGER:=0}"
  : "${BOOTSTRAP_SKIP_DOCKER:=0}"
  : "${BOOTSTRAP_SKIP_TAILSCALE:=0}"
fi

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
apt_install ca-certificates curl git xz-utils flatpak gpg sudo zenity

# Start progress dialog after zenity is available
start_progress
update_progress 5 "Installing base packages..."

if [[ "$BOOTSTRAP_SKIP_FLATPAK" != "1" ]]; then
  update_progress 10 "Configuring Flathub repository..."
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
fi

if [[ "$BOOTSTRAP_SKIP_NIX_INSTALL" == "1" ]]; then
  log "Skipping Nix install (BOOTSTRAP_SKIP_NIX_INSTALL=1)."
elif [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  if [[ -z "${HOME:-}" ]]; then
    log "\$HOME is not set; refusing to run Nix installer."
    exit 1
  fi

  update_progress 15 "Installing Nix package manager (this may take a few minutes)..."
  curl --proto '=https' --tlsv1.2 -fsSL https://nixos.org/nix/install | sh -s -- --daemon
fi

update_progress 30 "Configuring Nix..."

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

if [[ "$BOOTSTRAP_SKIP_SYSTEMD" == "1" ]]; then
  log "Skipping systemd integration (BOOTSTRAP_SKIP_SYSTEMD=1)."
elif command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  update_progress 35 "Starting Nix daemon..."
  systemctl daemon-reload || true
  systemctl enable --now nix-daemon.socket >/dev/null 2>&1 || true
  systemctl start nix-daemon.service >/dev/null 2>&1 || true
else
  log "systemd not available; skipping nix-daemon systemctl steps."
fi

# --- GUI apps: Flatpak-first (parallel installs) ---
if [[ "$BOOTSTRAP_SKIP_FLATPAK" == "1" ]]; then
  log "Skipping Flatpak installs (BOOTSTRAP_SKIP_FLATPAK=1)."
else
  update_progress 40 "Installing Flatpak applications..."
  # Run flatpak installs in parallel for faster setup
  declare -A flatpak_pids

  # Browsers & Core
  flatpak install -y --noninteractive flathub com.brave.Browser &
  flatpak_pids[brave]=$!
  flatpak install -y --noninteractive flathub org.mozilla.firefox &
  flatpak_pids[firefox]=$!

  # Gaming
  flatpak install -y --noninteractive flathub com.valvesoftware.Steam &
  flatpak_pids[steam]=$!
  flatpak install -y --noninteractive flathub org.prismlauncher.PrismLauncher &
  flatpak_pids[prism]=$!

  # Development
  flatpak install -y --noninteractive flathub com.visualstudio.code &
  flatpak_pids[vscode]=$!
  flatpak install -y --noninteractive flathub com.jetbrains.PyCharm-Professional &
  flatpak_pids[pycharm]=$!
  flatpak install -y --noninteractive flathub com.jetbrains.GoLand &
  flatpak_pids[goland]=$!
  flatpak install -y --noninteractive flathub org.openscad.OpenSCAD &
  flatpak_pids[openscad]=$!

  # Media
  flatpak install -y --noninteractive flathub org.videolan.VLC &
  flatpak_pids[vlc]=$!
  flatpak install -y --noninteractive flathub com.obsproject.Studio &
  flatpak_pids[obs]=$!
  flatpak install -y --noninteractive flathub org.audacityteam.Audacity &
  flatpak_pids[audacity]=$!
  flatpak install -y --noninteractive flathub org.shotcut.Shotcut &
  flatpak_pids[shotcut]=$!
  flatpak install -y --noninteractive flathub com.spotify.Client &
  flatpak_pids[spotify]=$!

  # Utilities
  flatpak install -y --noninteractive flathub com.discordapp.Discord &
  flatpak_pids[discord]=$!
  flatpak install -y --noninteractive flathub com.bitwarden.desktop &
  flatpak_pids[bitwarden]=$!

  # Wait for all flatpak installs to complete
  for app in "${!flatpak_pids[@]}"; do
    wait "${flatpak_pids[$app]}" 2>/dev/null || log "$app install finished (may have had warnings)"
  done
fi

# --- APT installs when Flatpak isn't the right fit ---
if [[ "$BOOTSTRAP_SKIP_APT_EXTRAS" == "1" ]]; then
  log "Skipping extra APT installs (BOOTSTRAP_SKIP_APT_EXTRAS=1)."
else
  update_progress 55 "Installing Wine and extras..."
  apt_install wine winetricks
fi

# --- Keyboard: swap Ctrl and Alt (X11) ---
if [[ "$BOOTSTRAP_SKIP_APT_EXTRAS" != "1" ]]; then
  apt_install x11-xkb-utils
  cat >/etc/profile.d/ctrl-alt-swap.sh <<'EOF'
setxkbmap -option ctrl:swap_lalt_lctl >/dev/null 2>&1 || true
EOF
fi

# --- JetBrains Toolbox (optional convenience) ---
if [[ "$BOOTSTRAP_SKIP_JETBRAINS" == "1" ]]; then
  log "Skipping JetBrains Toolbox (BOOTSTRAP_SKIP_JETBRAINS=1)."
else
  update_progress 65 "Installing JetBrains Toolbox..."
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
fi

# Apply Home Manager config from this repo.
if [[ "$BOOTSTRAP_SKIP_HOME_MANAGER" == "1" ]]; then
  log "Skipping Home Manager apply (BOOTSTRAP_SKIP_HOME_MANAGER=1)."
else
  update_progress 75 "Applying Home Manager configuration (this may take several minutes)..."
  as_user "$BOOTSTRAP_USER" bash -lc "
    set -euo pipefail
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    export NIX_CONFIG='experimental-features = nix-command flakes'
    cd '$repo_root'
    nix run github:nix-community/home-manager -- switch --flake '.#${BOOTSTRAP_USER}@mint'
  "
fi

update_progress 95 "Finalizing setup..."
mkdir -p "$SENTINEL_DIR"
touch "$SENTINEL_FILE"

update_progress 100 "Setup complete!"
close_progress
show_complete_notification

log "First-boot setup completed successfully."
