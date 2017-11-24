#!/bin/sh
set -e

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
fi

if [[ -f /etc/samba/smb.conf ]]; then
    exec smbd -FS
    exec nmbd -FS
fi

if [ "$#" -lt 1 ]; then
  exec bash
else
  exec "$@"
fi
