#!/bin/sh
set -e

#if [[ ! -f /etc/openldap/is.done ]]; then
#    SECRET=`slappasswd -s "$SAMBA_ADMIN_PASSWORD" -n`
#    sed -ri "s#SAMBA_ADMIN_SECRET#$SECRET#g" /etc/openldap/slapd.ldif
#    slapadd -v -l /etc/openldap/slapd.ldif
#    slapindex -f /etc/openldap/slapd.conf
#    /etc/init.d/slapd restart
#    smbpasswd -w $SAMBA_ADMIN_PASSWORD
#    smbldap-useradd -a admin
#    echo -e "$SAMBA_ADMIN_PASSWORD\n$SAMBA_ADMIN_PASSWORD" | smbpasswd -s admin
#    touch /etc/openldap/is.done
#fi

if [[ -f /etc/samba/smb.conf ]]; then
    exec /usr/sbin/samba -i
fi

if [ "$#" -lt 1 ]; then
  exec bash
else
  exec "$@"
fi
