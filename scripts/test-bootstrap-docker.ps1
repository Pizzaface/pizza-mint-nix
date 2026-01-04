$ErrorActionPreference = "Stop"

Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location ..

docker build -t pizza-mint-nix-bootstrap-test -f docker/Dockerfile docker
docker run --rm -v "${PWD}:/src" -w /src pizza-mint-nix-bootstrap-test bash /src/docker/smoke.sh
