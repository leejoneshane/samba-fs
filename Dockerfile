FROM alpine

COPY entrypoint.sh /usr/bin/
COPY smb.conf /etc/samba/

RUN apk update \
    && apk --no-cache --no-progress add bash samba shadow \
    && adduser -D -G users -H -g 'Samba User' -h /tmp smbuser \
    && rm -rf /tmp/*

EXPOSE 137/udp 138/udp 139 445
VOLUME ["/etc/samba", "/mnt"]
ENTRYPOINT ["entrypoint.sh"]
