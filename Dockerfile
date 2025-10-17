# syntax=docker/dockerfile:1.7

FROM alpine:3.20

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
      cups cups-libs cups-client cups-filters \
      ghostscript \
      hplip \
      avahi inotify-tools \
      python3 py3-pycups rsync wget perl \
      font-noto ttf-dejavu ghostscript-fonts

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
      --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
      cups-pdf

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
      --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
      brlaser gutenprint gutenprint-cups

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
    if ! grep -q '^DefaultPaperSize ' /etc/cups/cupsd.conf; then echo 'DefaultPaperSize A4' >> /etc/cups/cupsd.conf; else sed -i 's/DefaultPaperSize .*/DefaultPaperSize A4/' /etc/cups/cupsd.conf; fi; \
    echo "pdftops-renderer ghostscript" >> /etc/cups/cupsd.conf

CMD ["/root/run_cups.sh"]
