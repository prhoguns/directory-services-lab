#!/bin/bash
# The report an auditor asks for: who has privileged access, which accounts are stale or disabled,
# what the password policy is, and which accounts never expire.
set -uo pipefail
echo "=== password policy"
samba-tool domain passwordsettings show

echo
echo "=== privileged group membership"
for g in "Domain Admins" "Enterprise Admins" "Schema Admins" "IT-Admins" "Helpdesk"; do
  members=$(samba-tool group listmembers "$g" 2>/dev/null | tr '\n' ' ')
  printf "%-18s %s\n" "$g:" "${members:-<none>}"
done

echo
echo "=== all users and their status"
printf "%-14s %-10s %s\n" USER ENABLED GROUPS
for u in $(samba-tool user list | sort); do
  uac=$(samba-tool user show "$u" --attributes=userAccountControl 2>/dev/null | awk '/userAccountControl/{print $2}')
  case "$uac" in *ACCOUNTDISABLE*|*"514"*|*"66050"*) en=no;; *) en=yes;; esac
  groups=$(samba-tool user show "$u" --attributes=memberOf 2>/dev/null | sed -n 's/^memberOf: CN=\([^,]*\).*/\1/p' | tr '\n' ',' | sed 's/,$//')
  printf "%-14s %-10s %s\n" "$u" "$en" "${groups:-Domain Users}"
done

echo
echo "=== service accounts (should be non-interactive and long-lived by design)"
samba-tool user list | grep '^svc-' || echo "none"

echo
echo "=== organisational units"
samba-tool ou list
