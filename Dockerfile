# syntax=docker/dockerfile:1.7

############################
# Builder (compile brlaser + gutenprint)
############################
FROM alpine:3.20 AS build

# Build deps + cups-dev (for cups-config)
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
      build-base git cmake wget perl coreutils tar xz \
      cups-dev

# brlaser
RUN --mount=type=cache,target=/root/.cache \
    git clone https://github.com/pdewacht/brlaser.git /tmp/brlaser && \
    cd /tmp/brlaser && \
    cmake . && \
    make -j"$(nproc)" && \
    make install

# gutenprint (optional but handy if sharing other printers)
RUN --mount=type=cache,target=/root/.cache \
    wget -O /tmp/gutenprint.tar.xz \
      "https://downloads.sourceforge.net/project/gimp-print/gutenprint-5.3/5.3.5/gutenprint-5.3.5.tar.xz" && \
    mkdir -p /tmp/gutenprint && \
    tar -xJf /tmp/gutenprint.tar.xz -C /tmp/gutenprint --strip-components=1 && \
    cd /tmp/gutenprint && \
    find src/testpattern -type f -exec sed -i 's/\bPAGESIZE\b/GPT_PAGESIZE/g' {} + && \
    ./configure && \
    make -j"$(nproc)" && \
    make install && \
    sed -i '1s|.*|#!/usr/bin/perl|' /usr/sbin/cups-genppdupdate

############################
# Final (runtime: CUPS + Avahi + fonts)
############################
FROM alpine:3.20

# Optional: match your original edge repos (keep if you need specific packages there)
RUN --mount=type=cache,target=/var/cache/apk \
    printf '%s\n%s\n' \
      "https://dl-cdn.alpinelinux.org/alpine/edge/testing" \
      "https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    apk add --no-cache \
      cups cups-libs cups-pdf cups-client cups-filters \
      ghostscript \
      hplip \
      avahi inotify-tools \
      python3 py3-pycups rsync wget perl \
      # fonts for better Ghostscript rasterization
      font-noto ttf-dejavu ghostscript-fonts

# Bring in the stuff we built
COPY --from=build /usr/local/ /usr/local/

EXPOSE 631
VOLUME ["/config", "/services"]

# Scripts
ADD root /root
RUN chmod +x /root/*

# AirPrint-friendly CUPS + Avahi tweaks
RUN set -eux; \
    sed -i 's/Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf; \
    sed -i 's/Browsing Off/Browsing On/' /etc/cups/cupsd.conf; \
    sed -i 's/IdleExitTimeout/#IdleExitTimeout/' /etc/cups/cupsd.conf; \
    sed -i 's#<Location />#<Location />\n  Allow All#' /etc/cups/cupsd.conf; \
    sed -i 's#<Location /admin>#<Location /admin>\n  Allow All\n  Require user @SYSTEM#' /etc/cups/cupsd.conf; \
    sed -i 's#<Location /admin/conf>#<Location /admin/conf>\n  Allow All#' /etc/cups/cupsd.conf; \
    sed -i 's/.*enable-dbus=.*/enable-dbus=no/' /etc/avahi/avahi-daemon.conf; \
    printf '\nServerAlias *\nDefaultEncryption Never\n' >> /etc/cups/cupsd.conf; \
    printf 'ReadyPaperSizes A4,TA4,4X6FULL,T4X6FULL,2L,T2L,A6,A5,B5,L,TL,INDEX5,8x10,T8x10,4X7,T4X7,Postcard,TPostcard,ENV10,EnvDL,ENVC6,Letter,Legal\n' >> /etc/cups/cupsd.conf; \
    # NZ default
    if ! grep -q '^DefaultPaperSize ' /etc/cups/cupsd.conf; then echo 'DefaultPaperSize A4' >> /etc/cups/cupsd.conf; else sed -i 's/DefaultPaperSize .*/DefaultPaperSize A4/' /etc/cups/cupsd.conf; fi; \
    echo "pdftops-renderer ghostscript" >> /etc/cups/cupsd.conf

CMD ["/root/run_cups.sh"]
