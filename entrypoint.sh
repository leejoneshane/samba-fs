#!/bin/sh
if [[ ! -f /sam/passwd ]]; then
    mkdir -p /sam/openldap
    cp -p /root/passwd /sam/passwd
    ln -s /sam/passwd /etc/passwd
fi

if [[ ! -f /sam/shadow ]]; then
    cp -p /root/shadow /sam/shadow
    ln -s /sam/shadow /etc/shadow
fi

if [[ ! -f /sam/group ]]; then
    cp -p /root/group /sam/group
    ln -s /sam/group /etc/group
fi

if [[ ! -f /web/wam.pl ]]; then
    cp -p /root/web/. /web
fi

if [[ ! -f /etc/openldap/is.done ]]; then
    rm -rf /sam/openldap/*
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
    nmbd -FS &
fi

if [ "$#" -lt 1 ]; then
    /web/wam.pl daemon -m production
else
    exec $@
fi
