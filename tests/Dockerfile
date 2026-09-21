# Set up an Ubuntu container matching what a fresh VPS looks like
FROM ubuntu:26.04

RUN apt-get update -q && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    systemd-sysv \
    openssh-server \
    python3 \
    sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
