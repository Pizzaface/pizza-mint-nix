# pizza-mint-nix

## Docker smoke test (no VM)

This runs the bootstrap scripts in an Ubuntu container with `HOME` intentionally unset, to catch the kind of first-boot issues you saw.

Prereqs:
- Docker Desktop (Windows) / Docker (Linux)

Run on Windows (PowerShell):
- `./scripts/test-bootstrap-docker.ps1`

What it tests:
- `iso-overlay/usr/local/bin/nix-bootstrap.sh` works with `HOME` unset
- `bootstrap/nix-bootstrap-impl.sh` runs in a container-friendly mode and writes the sentinel file

