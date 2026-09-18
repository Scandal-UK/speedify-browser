FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    gpg \
    dbus-x11 \
    firefox-esr \
    iproute2 \
    qbittorrent \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Speedify repository
RUN curl -SL 'https://get.speedify.com/pgp.key' \
    | gpg --dearmor \
    > /usr/share/keyrings/connectify-archive-keyring.gpg \
    && echo \
    'deb [signed-by=/usr/share/keyrings/connectify-archive-keyring.gpg] http://apt.connectify.me/ speedify main' \
    > /etc/apt/sources.list.d/connectify.list

RUN apt-get update \
    && apt-get install -y speedify speedifyui \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/vpn-browser-entrypoint
RUN chmod +x /usr/local/bin/vpn-browser-entrypoint

ENTRYPOINT ["/usr/local/bin/vpn-browser-entrypoint"]

