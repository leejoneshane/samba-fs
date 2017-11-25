FROM alpine

ENV SAMBA_ADMIN_PASSWORD S@mba

ADD entrypoint.sh /usr/sbin/
ADD smb.conf /etc/samba/smb.conf
ADD example.conf /etc/samba/example.conf
ADD samba.schema /etc/openldap/schema/samba.schema
ADD samba.ldif /etc/openldap/schema/samba.ldif
ADD slapd.conf /etc/openldap/slapd.conf
ADD slapd.ldif /etc/openldap/slapd.ldif
ADD initldap.ldif /etc/openldap/initldap.ldif

RUN apk update \
    && apk --no-cache --no-progress add bash sudo wget make gcc acl attr samba openldap perl openssl \
    && adduser -G wheel -D -h /mnt admin \
    && echo "wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel \
    && chmod +x /usr/sbin/entrypoint.sh

RUN perl -MCPAN -e 'install App::cpanminus' \
    && cpanm local::lib \
    && cpanm Mojolicious \
    && cpanm File::Samba \
    && cpanm Samba::LDAP

EXPOSE 137/udp 138/udp 139 3000
VOLUME ["/mnt"]
ENTRYPOINT ["entrypoint.sh"]
