FROM alpine

COPY entrypoint.sh /usr/sbin/
COPY smb.conf /etc/samba/

RUN apk update \
    && apk --no-cache --no-progress add bash sudo acl attr samba-server openldap perl \
    && adduser -G admin,users -h /mnt admin \
    && echo "admin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/admin; \
    && chmod 0440 /etc/sudoers.d/admin \
    && chmos +x /usr/sbin/entrypoint.sh    

EXPOSE 137/udp 138/udp 139 12000
VOLUME ["/etc/samba", "/mnt"]
ENTRYPOINT ["entrypoint.sh"]
