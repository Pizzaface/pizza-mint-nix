#!/usr/bin/env bash
set -euo pipefail

cd /src

if [[ ! -f iso-overlay/usr/local/bin/nix-bootstrap.sh ]]; then
  echo "Expected to be run with repo mounted at /src." >&2
  exit 1
fi

# Provide the bootstrap config the unit would normally supply.
cat >/etc/default/nix-bootstrap <<'EOF'
BOOTSTRAP_USER=jordan
BOOTSTRAP_REPO=/src
BOOTSTRAP_REF=main
BOOTSTRAP_DIR=/home/jordan/pizza-mint-nix
EOF

# Git inside the container sees the bind-mounted repo as "dubious ownership" (host UID/GID mismatch).
sudo -u jordan git config --global --add safe.directory /src || true
sudo -u jordan git config --global --add safe.directory /src/.git || true

# Stub out Nix so the test doesn't try to install the daemon inside a container.
mkdir -p /nix/var/nix/profiles/default/bin
cat >/nix/var/nix/profiles/default/bin/nix <<'EOF'
#!/usr/bin/env bash
echo "nix (stub) 0.0.0"
EOF
chmod +x /nix/var/nix/profiles/default/bin/nix

rm -f /var/lib/nix-bootstrap/done || true

env -u HOME \
  BOOTSTRAP_TEST_MODE=1 \
  BOOTSTRAP_SKIP_NIX_INSTALL=1 \
  BOOTSTRAP_SKIP_SYSTEMD=1 \
  BOOTSTRAP_SKIP_FLATPAK=1 \
  BOOTSTRAP_SKIP_APT_EXTRAS=1 \
  BOOTSTRAP_SKIP_JETBRAINS=1 \
  BOOTSTRAP_SKIP_HOME_MANAGER=1 \
  bash /src/iso-overlay/usr/local/bin/nix-bootstrap.sh --force

test -f /var/lib/nix-bootstrap/done
echo "OK: bootstrap smoke test passed (HOME unset + sentinel written)."
