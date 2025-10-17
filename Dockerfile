# syntax=docker/dockerfile:1.7

############################
# Builder: brlaser + gutenprint
############################
FROM alpine:3.20 AS build

ARG GUTENPRINT_VER=5.3.5

# Faster, repeatable apk + build caches with BuildKit
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
      build-base git cmake wget perl coreutils tar xz

# Build brlaser
RUN --mount=type=cache,target=/root/.cache \
    git clone https://github.com/pdewacht/brlaser.git /tmp/brlaser && \
    cd /tmp/brlaser && \
    cmake . && \
    make -j"$(nproc)" && \
    make install

# Build gutenprint (optional but handy if this box will share other printers)
RUN --mount=type=cache,target=/root/.cache \
    wget -O /tmp/gutenprint.tar.xz \
      "https://downloads.sourceforge.net/project/gimp-print/gutenprint-${GUTENPRINT_VER}/${GUTENPRINT_VER}/gutenprint-${GUTENPRINT_VER}.tar.xz" && \
    mkdir -p /tmp/gutenprint && \
    tar -xJf /tmp/gutenprint.tar.xz -C /tmp/gutenprint --strip-components=1 && \
    cd /tmp/gutenprint && \
    # Fix conflicting PAGESIZE identifiers in testpattern
    find src/testpattern -type f -exec sed -i 's/\bPAGESIZE\b/GPT_PAGESIZE/g' {} + && \
    ./configure && \
    make -j"$(nproc)" && \
    make install && \
    sed -i '1s|.*|#!/usr/bin/perl|' /usr/sbin/cups-genppdupdate

############################
# Final: CUPS + Avahi + fonts
############################
FROM alpine:3.20

# Add edge repos only if/when you truly need them; keeping them here to match your source image
RUN --mount=type=cache,target=/var/cache/apk \
    printf '%s\n%s\n' \
      "https://dl-cdn.alpinelinux.org/alpine/edge/testing" \
      "https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    apk add --no-cache \
      cups cups-libs cups-pdf cups-client cups-filters cups-dev \
      ghostscript \
      hplip \
      avahi inotify-tools \
      python3 python3-dev py3-pycups \
      build-base rsync wget perl \
      # Fonts for sane Ghostscript rasterization
      font-noto ttf-dejavu ghostscript-fonts

# Bring in brlaser + gutenprint from the builder
COPY --from=build /usr/local/ /usr/local/

# Expose IPP
EXPOSE 631

# Persist config/service files
VOLUME ["/config", "/services"]

# Add your existing scripts (expects /root/run_cups.sh etc.)
ADD root /root
RUN chmod +x /root/*

# Baseline config hardening + AirPrint friendly defaults
# - Listen on all IFs, enable browsing, allow admin from LAN (tighten to your subnet if you want)
# - Disable DBus in Avahi (simpler inside containers)
# - Default to A4 in NZ; set Ghostscript renderer
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
    # NZ default—change if you live that Letter life
    sed -i 's/DefaultPaperSize Letter/DefaultPaperSize A4/' /etc/cups/cupsd.conf || echo "DefaultPaperSize A4" >> /etc/cups/cupsd.conf; \
    echo "pdftops-renderer ghostscript" >> /etc/cups/cupsd.conf

# Run script handles avahi + cupsd (and any env like admin user)
CMD ["/root/run_cups.sh"]
