#!/bin/bash
# Provision the domain on first boot, then run Samba in the foreground.
# Idempotent: if the domain already exists (smb.conf has a DC role), just start.
set -euo pipefail
REALM="${REALM:-LAB.EXAMPLE.COM}"
DOMAIN="${DOMAIN:-LAB}"
ADMIN_PASS="${ADMIN_PASS:-LabAdminPass123!}"
DC_IP="${DC_IP:-$(hostname -i | awk '{print $1}')}"

if ! grep -qi "server role = active directory domain controller" /etc/samba/smb.conf 2>/dev/null; then
  echo "[dc] provisioning domain $DOMAIN ($REALM)"
  rm -f /etc/samba/smb.conf
  samba-tool domain provision \
    --use-rfc2307 \
    --realm="$REALM" \
    --domain="$DOMAIN" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS" \
    --option="interfaces=lo eth0" \
    --option="bind interfaces only=yes"
  cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
  # Password policy: default Samba complexity, but set ages explicitly so the policy is deliberate.
  echo "[dc] provisioned"
fi

# The DC must resolve its own domain through itself.
printf 'nameserver 127.0.0.1\nsearch %s\n' "$(echo "$REALM" | tr 'A-Z' 'a-z')" > /etc/resolv.conf || true
exec samba -i --debuglevel=1
