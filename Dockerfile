FROM alpine

ENV SAMBA_ADMIN_PASSWORD S@mba

ADD entrypoint.sh /usr/sbin/
ADD smb.conf /etc/samba/smb.conf
ADD example.conf /etc/samba/example.conf
ADD samba.schema /etc/openldap/schema/samba.schema
ADD samba.ldif /etc/openldap/schema/samba.ldif
ADD slapd.conf /etc/openldap/slapd.conf
ADD initldap.ldif /etc/openldap/initldap.ldif
ADD web /web

RUN apk update \
    && apk --no-cache --no-progress add bash sudo acl attr samba openldap-clients openldap openldap-back-mdb perl perl-mojolicious \
    && adduser -G wheel -D -h /mnt admin \
    && echo "wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel \
    && chmod +x /usr/sbin/entrypoint.sh \
    && mkdir /sam

EXPOSE 137/udp 138/udp 139 3000
VOLUME ["/mnt", "/sam", "/web"]
ENTRYPOINT ["entrypoint.sh"]
