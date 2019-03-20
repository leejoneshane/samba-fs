FROM alpine

ENV SAMBA_ADMIN_PASSWORD S@mba

ADD entrypoint.sh /usr/sbin/
ADD smb.conf /etc/samba/smb.conf
ADD samba.schema /etc/openldap/schema/samba.schema
ADD samba.ldif /etc/openldap/schema/samba.ldif
ADD slapd.conf /etc/openldap/slapd.conf
ADD initldap.ldif /etc/openldap/initldap.ldif
ADD web /web

RUN apk update \
    && apk --no-cache --no-progress add bash sudo zip acl attr wget gcc make libc-dev \
                                        samba openldap-clients openldap openldap-back-mdb \
                                        perl perl-dev perl-ldap perl-mojolicious perl-locale-maketext-lexicon \
    && wget --no-check-certificate http://bit.ly/cpanm -O /usr/local/bin/cpanm \
    && chmod +x /usr/local/bin/cpanm \
    && cpanm Mojolicious::Plugin::RenderFile \
    && cpanm Mojolicious::Plugin::Thumbnail --force \
    && adduser -G wheel -D -h /mnt -s /bin/bash admin \
    && echo "wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel \
    && chmod +x /usr/sbin/entrypoint.sh \
    && mkdir -p /sam/openldap \
    && mv /etc/passwd /root/passwd \
    && mv /etc/shadow /root/shadow \
    && mv /etc/group /root/group \
    && cp -p /root/passwd /sam/passwd \
    && cp -p /root/shadow /sam/shadow \
    && cp -p /root/group /sam/group \
    && ln -s /sam/passwd /etc/passwd \
    && ln -s /sam/shadow /etc/shadow \
    && ln -s /sam/group /etc/group

EXPOSE 137/udp 138/udp 139 3000
VOLUME ["/mnt", "/sam", "/web"]
ENTRYPOINT ["entrypoint.sh"]
