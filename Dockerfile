FROM alpine

ADD entrypoint.sh /usr/sbin/
ADD smb.conf /etc/samba/smb.conf
ADD samba.schema /etc/openldap/schema/samba.schema
ADD samba.ldif /etc/openldap/schema.samba.ldif
ADD slapd.conf /etc/openldap/slapd.conf

RUN apk update \
    && apk --no-cache --no-progress add bash sudo acl attr samba openldap perl \
    && adduser -G wheel -D -h /mnt admin \
    && echo "wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel \
    && chmos +x /usr/sbin/entrypoint.sh

EXPOSE 137/udp 138/udp 139 12000
VOLUME ["/mnt"]
ENTRYPOINT ["entrypoint.sh"]
