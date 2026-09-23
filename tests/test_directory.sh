#!/usr/bin/env bash
# End-to-end verification of the domain: it exists, the structure is right, authentication works
# from a joined client, group membership is correct, and offboarding actually disables access.
set -uo pipefail
pass=0; fail=0
check() { # description, command, expected substring
  local desc="$1" cmd="$2" want="$3" got
  got=$(eval "$cmd" 2>&1 || true)
  if printf '%s' "$got" | grep -qi -- "$want"; then
    printf '  PASS  %s\n' "$desc"; pass=$((pass+1))
  else
    printf '  FAIL  %s\n        got: %s\n' "$desc" "$(printf '%s' "$got" | head -2 | tr '\n' ' ')"; fail=$((fail+1))
  fi
}
DC="docker exec dc1"
CL="docker exec client1"

echo "== domain"
check "domain controller is up"              "$DC samba-tool domain info 127.0.0.1"        "Domain *: LAB"
check "realm is LAB.EXAMPLE.COM"             "$DC samba-tool domain info 127.0.0.1"        "lab.example.com"
check "DNS resolves the domain"              "$DC dig +short lab.example.com @127.0.0.1"   "172.28.10.10"
check "LDAP responds"                        "$DC ldapsearch -x -H ldap://127.0.0.1 -b '' -s base namingContexts" "DC=lab,DC=example,DC=com"

echo "== structure"
for ou in Staff Servers Workstations ServiceAccounts Groups; do
  check "OU=$ou exists"                      "$DC samba-tool ou list"                      "OU=$ou"
done
for g in IT-Admins Helpdesk Finance Engineering VPN-Users; do
  check "group $g exists"                    "$DC samba-tool group list"                   "^$g\$"
done

echo "== accounts and membership"
check "a.okafor exists"                      "$DC samba-tool user list"                    "a.okafor"
check "a.okafor is a Domain Admin"           "$DC samba-tool group listmembers 'Domain Admins'" "a.okafor"
check "s.patel is in Engineering"            "$DC samba-tool group listmembers Engineering" "s.patel"
check "m.singh is NOT in Engineering"        "$DC samba-tool group listmembers Engineering | grep -c m.singh || echo 0" "0"
check "service account svc-backup exists"    "$DC samba-tool user list"                    "svc-backup"

echo "== password policy"
check "minimum length 14"                    "$DC samba-tool domain passwordsettings show" "Minimum password length: 14"
check "complexity on"                        "$DC samba-tool domain passwordsettings show" "Password complexity: on"
check "lockout after 5 attempts"             "$DC samba-tool domain passwordsettings show" "Account lockout threshold (attempts): 5"
check "maximum age 90 days"                  "$DC samba-tool domain passwordsettings show" "Maximum password age (days): 90"

echo "== joined client"
check "client has joined the domain"         "$CL net ads testjoin"                        "Join is OK"
check "client resolves domain users"         "$CL getent passwd a.okafor"                  "a.okafor"
check "client resolves domain groups"        "$CL getent group Engineering"                "Engineering"
check "domain user can authenticate"         "$CL wbinfo -a 'a.okafor%InitialP@ssw0rd!2026'" "challenge/response password authentication succeeded"
check "wrong password is rejected"           "$CL wbinfo -a 'a.okafor%WrongPassword1!' 2>&1 | grep -ci 'succeeded' || echo 0" "0"

echo "== offboarding"
$DC /scripts/offboard.sh contractor >/dev/null 2>&1
check "offboarded account cannot authenticate" "$CL wbinfo -a 'contractor%InitialP@ssw0rd!2026' 2>&1 | grep -ci succeeded || echo 0" "0"
check "offboarded account moved to OU=Disabled" "$DC samba-tool user show contractor --attributes=distinguishedName" "OU=Disabled"

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
