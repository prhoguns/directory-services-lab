#!/bin/bash
# Join this host to the domain and configure it to authenticate domain users through winbind.
# The Linux equivalent of joining a Windows workstation to Active Directory.
set -euo pipefail
REALM="${REALM:-LAB.EXAMPLE.COM}"
DOMAIN="${DOMAIN:-LAB}"
ADMIN_PASS="${ADMIN_PASS:-LabAdminPass123!}"
DC_IP="${DC_IP:-172.28.10.10}"
REALM_LOWER=$(echo "$REALM" | tr 'A-Z' 'a-z')

printf 'nameserver %s\nsearch %s\n' "$DC_IP" "$REALM_LOWER" > /etc/resolv.conf

cat > /etc/krb5.conf <<KRB
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true
KRB

cat > /etc/samba/smb.conf <<SMB
[global]
    workgroup = $DOMAIN
    realm = $REALM
    security = ADS
    winbind use default domain = yes
    winbind offline logon = no
    winbind enum users = yes
    winbind enum groups = yes
    template shell = /bin/bash
    template homedir = /home/%U
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config $DOMAIN : backend = rid
    idmap config $DOMAIN : range = 10000-999999
    kerberos method = secrets and keytab
SMB

echo "[join] joining $REALM"
echo "$ADMIN_PASS" | net ads join -U Administrator --no-dns-updates

# Authenticate and resolve domain identities through winbind.
sed -i 's/^passwd:.*/passwd:         files winbind/; s/^group:.*/group:          files winbind/' /etc/nsswitch.conf
pkill winbindd 2>/dev/null || true
winbindd -D
sleep 3
echo "[join] joined. testing:"
net ads testjoin
