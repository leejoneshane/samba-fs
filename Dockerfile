FROM alpine

COPY entrypoint.sh /usr/sbin/
COPY smb.conf /etc/samba/

RUN apk update \
    && apk --no-cache --no-progress add bash sudo acl attr git perl \
    && adduser -G admin,users -h /mnt admin \
    && echo "admin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/admin; \
    && chmod 0440 /etc/sudoers.d/admin \
    && chmos +x /usr/sbin/entrypoint.sh \
    && cd /tmp \
    && git clone git://git.openldap.org/openldap.git \
    && cd /tmp/openldap
    && CFLAGS="-fno-omit-frame-pointer" \
    && ./configure --with-cyrus-sasl --disable-bdb --disable-hdb --enable-overlays=mod --enable-modules \
    && make clean all AC_CFLAGS=-g \
    && make install STRIP= \
    && cd contrib/slapd-modules/samba4 \
    && make clean all AC_CFLAGS=-g \
    && make install STRIP= \
    && cd /tmp \
    && git clone https://git.samba.org/samba.git \
    && ./autogen.sh \
    && ./configure --enable-developer \
    && make \
    && make install
    

EXPOSE 137/udp 138/udp 139 901
VOLUME ["/etc/samba", "/mnt"]
ENTRYPOINT ["entrypoint.sh"]
