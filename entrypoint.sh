#!/bin/sh
set -e

if [[ ! -f /sam/passwd ]]; then
	cp -p /root/passwd /sam/passwd
fi

if [[ ! -f /sam/shadow ]]; then
	cp -p /root/shadow /sam/shadow
fi

if [[ ! -f /sam/group ]]; then
	cp -p /root/group /sam/group
fi

if [[ ! -f /etc/openldap/is.done ]]; then
    SECRET=`slappasswd -s "$SAMBA_ADMIN_PASSWORD" -n`
    sed -ri "s#SAMBA_ADMIN_SECRET#$SECRET#g" /etc/openldap/initldap.ldif
    sed -ri "s#SAMBA_ADMIN_SECRET#$SECRET#g" /etc/openldap/slapd.conf
    slapadd -v -l /etc/openldap/initldap.ldif
    slapindex -f /etc/openldap/slapd.conf
    slapd -f /etc/openldap/slapd.conf
    smbpasswd -w $SAMBA_ADMIN_PASSWORD
    echo -e "$SAMBA_ADMIN_PASSWORD\n$SAMBA_ADMIN_PASSWORD" | smbpasswd -as admin
    touch /etc/openldap/is.done
else
    slapd -f /etc/openldap/slapd.conf
fi

if [[ -f /etc/samba/smb.conf ]]; then
    exec smbd -FS
    exec nmbd -FS
fi

exec /web/wam.pl daemon -m production

if [ "$#" -lt 1 ]; then
  exec bash
else
  exec "$@"
fi
