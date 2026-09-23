#!/bin/bash
# Offboard a user the way it should be done: disable first (so nothing breaks silently and the
# account can be restored), strip group memberships, move to a holding OU, record what was done.
# Deletion happens later, after the retention period - that is a separate, deliberate action.
set -uo pipefail
USER="${1:?usage: offboard.sh <samaccountname>}"
REALM_DN="DC=lab,DC=example,DC=com"

echo "[offboard] $USER"
echo "  groups before: $(samba-tool user show "$USER" --attributes=memberOf 2>/dev/null | grep -c memberOf || echo 0)"

samba-tool user disable "$USER" && echo "  disabled"
for g in $(samba-tool user show "$USER" --attributes=memberOf 2>/dev/null | sed -n 's/^memberOf: CN=\([^,]*\).*/\1/p'); do
  [ "$g" = "Domain Users" ] && continue
  samba-tool group removemembers "$g" "$USER" >/dev/null 2>&1 && echo "  removed from $g"
done
samba-tool ou list | grep -qx "OU=Disabled,$REALM_DN" || samba-tool ou create "OU=Disabled,$REALM_DN" >/dev/null 2>&1
samba-tool user move "$USER" "OU=Disabled,$REALM_DN" >/dev/null 2>&1 && echo "  moved to OU=Disabled"
echo "  enabled now: $(samba-tool user show "$USER" --attributes=userAccountControl | grep userAccountControl)"
