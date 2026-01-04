FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git sudo \
  && rm -rf /var/lib/apt/lists/*

# Match the flake user.
RUN useradd -m -s /bin/bash jordan \
  && echo 'jordan ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-jordan \
  && chmod 0440 /etc/sudoers.d/90-jordan

WORKDIR /src

CMD ["/bin/bash"]
