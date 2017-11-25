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
    && apk --no-cache --no-progress add bash sudo acl attr samba openldap \
    && adduser -G wheel -D -h /mnt admin \
    && echo "wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel \
    && chmod +x /usr/sbin/entrypoint.sh

RUN apk --no-cache --no-progress add wget openssl make gcc perl perl-cpan perl-utils perl-mojolicious \
        perl-module-build perl-module-build-tiny perl-list-moreutils perl-digest-sha1 perl-unicode-string \
        perl-config-tiny perl-universal-require perl-net-ldap perl-readonly perl-test-pod perl-file-find-rule \
        perl-pod-coverage perl-test-pod-coverage perl-test-leaktrace perl-exporter-tiny perl-convert-asn1 \
        perl-text-soundex perl-data-dump
    && cpan install App::cpanminus \
    && cpanm local::lib \
    && cpanm File::Samba \
    && cpanm Samba::LDAP

EXPOSE 137/udp 138/udp 139 3000
VOLUME ["/mnt"]
ENTRYPOINT ["entrypoint.sh"]
