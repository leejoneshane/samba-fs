#!/bin/sh
set -e

# Configure the AD DC with OpenLDAP backend
if [[ ! -f /etc/samba/smb.conf ]]; then
      echo "$SAMBA_DOMAIN - Begin Domain Provisioning..."
      samba-tool domain provision \
        --domain="CC" \
        --realm="CC.samba.org" \
        --adminpass="$SAMBA_ADMIN_PASSWORD" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --ldap-backend-type=openldap \
        --slapd-path=/usr/local/libexec/slapd \
        --use-ntvfs
      echo "$SAMBA_DOMAIN - Domain Provisioning Successfully."
fi

if [[ ! -f /etc/krb5.conf ]]; then
    ln -sf /var/lib/samba/private/krb5.conf /etc/krb5.conf
fi      

if [[ -f /etc/samba/smb.conf ]]; then
    exec /usr/sbin/samba -i
fi

if [ "$#" -lt 1 ]; then
  exec bash
else
  exec "$@"
fi
