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
    && apk --no-cache --no-progress add bash sudo make gcc acl attr samba openldap perl openssl \
    && adduser -G wheel -D -h /mnt admin \
    && echo "wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel \
    && chmod +x /usr/sbin/entrypoint.sh \
    && wget --no-check-certificate -O /usr/bin/cpanm https://raw.githubusercontent.com/miyagawa/cpanminus/master/cpanm \
    && chmod +x /usr/bin/cpanm \
    && cpanm local::lib \
    && cpanm Mojolicious

EXPOSE 137/udp 138/udp 139 3000
VOLUME ["/mnt"]
ENTRYPOINT ["entrypoint.sh"]
