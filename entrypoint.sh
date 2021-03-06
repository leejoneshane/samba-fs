#!/bin/sh
if [[ ! -f /web/wam.pl ]]; then
    cp -Rp /root/web /web
fi

if [[ ! -f /etc/passwd ]]; then
    cp -Rp /root/etc /etc
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
    smbd -FS &
fi

if [ "$#" -lt 1 ]; then
    hypnotoad -f /web/wam.pl
else
    exec $@
fi
