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
    && apk --no-cache --no-progress add bash sudo make gcc acl attr samba openldap perl \
    && adduser -G wheel -D -h /mnt admin \
    && echo "wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel \
    && chmod +x /usr/sbin/entrypoint.sh \
    && perl -MCPAN -e 'install Task::Catalyst' \
    && perl -MCPAN -e 'install Catalyst::Devel' \
    && perl -MCPAN -e 'install Catalyst::Model::DBIC::Schema'

EXPOSE 137/udp 138/udp 139 12000
VOLUME ["/mnt"]
ENTRYPOINT ["entrypoint.sh"]
