FROM alpine

ADD entrypoint.sh /usr/sbin/
ADD smb.conf /etc/samba/smb.conf
ADD samba.schema /etc/openldap/schema/samba.schema
ADD slapd.conf /etc/openldap/slapd.conf
ADD initldap.ldif /etc/openldap/initldap.ldif

RUN apk update \
    && apk --no-cache --no-progress add bash sudo acl attr samba openldap perl \
    && adduser -G admin,users -h /mnt admin \
    && echo "admin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/admin; \
    && chmod 0440 /etc/sudoers.d/admin \
    && chmos +x /usr/sbin/entrypoint.sh    

EXPOSE 137/udp 138/udp 139 12000
VOLUME ["/mnt"]
ENTRYPOINT ["entrypoint.sh"]
