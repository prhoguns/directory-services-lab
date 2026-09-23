#!/bin/bash
# Build the directory structure: OUs, groups, users, group memberships, password policy and a GPO.
# Idempotent - every create is guarded, so it can be re-run after a change.
set -uo pipefail
REALM_DN="DC=lab,DC=example,DC=com"
st() { samba-tool "$@" >/dev/null 2>&1; }

echo "== password policy"
samba-tool domain passwordsettings set \
  --complexity=on --history-length=12 --min-pwd-length=14 \
  --min-pwd-age=1 --max-pwd-age=90 --account-lockout-threshold=5 \
  --account-lockout-duration=15 --reset-account-lockout-after=15 2>&1 | grep -v "^$" | head -3

echo "== organisational units"
for ou in Staff Servers Workstations ServiceAccounts Groups; do
  samba-tool ou list | grep -qx "OU=$ou,$REALM_DN" || st ou create "OU=$ou,$REALM_DN"
  echo "   OU=$ou"
done

echo "== groups"
create_group() {  # name, description, ou
  samba-tool group list | grep -qx "$1" || st group add "$1" --description="$2" --groupou="OU=$3"
  echo "   $1"
}
create_group "IT-Admins"      "Full administrative access"            Groups
create_group "Helpdesk"       "Password reset and workstation admin"  Groups
create_group "Finance"        "Finance department"                    Groups
create_group "Engineering"    "Engineering department"                Groups
create_group "VPN-Users"      "Permitted to use the VPN"              Groups
create_group "FileShare-RW"   "Read-write on the department share"    Groups
create_group "FileShare-RO"   "Read-only on the department share"     Groups

echo "== users"
create_user() {  # sam, given, surname, ou, title, department
  if ! samba-tool user list | grep -qx "$1"; then
    st user create "$1" 'InitialP@ssw0rd!2026' \
      --given-name="$2" --surname="$3" --userou="OU=$4" \
      --job-title="$5" --department="$6" \
      --mail-address="$1@lab.example.com" \
      --use-username-as-cn
    # Force a password change at first logon, the way a real onboarding does.
    st user setexpiry "$1" --noexpiry
  fi
  echo "   $1 ($5)"
}
create_user a.okafor  Ada     Okafor    Staff "Systems Administrator" IT
create_user j.tremblay Jean   Tremblay  Staff "Help Desk Analyst"     IT
create_user m.singh   Meera   Singh     Staff "Financial Analyst"     Finance
create_user r.chen    Robert  Chen      Staff "Software Engineer"     Engineering
create_user s.patel   Sara    Patel     Staff "Engineering Manager"   Engineering
create_user contractor Temp   Contractor Staff "Contractor"           External

echo "== service accounts"
for svc in svc-backup svc-monitoring; do
  samba-tool user list | grep -qx "$svc" || st user create "$svc" 'Svc#Acct!2026Pass' --userou="OU=ServiceAccounts" --description="Service account"
  st user setexpiry "$svc" --noexpiry
  echo "   $svc"
done

echo "== memberships"
addmem() { st group addmembers "$1" "$2"; echo "   $2 -> $1"; }
addmem IT-Admins    a.okafor
addmem Helpdesk     j.tremblay
addmem Finance      m.singh
addmem Engineering  "r.chen,s.patel"
addmem VPN-Users    "a.okafor,r.chen,s.patel"
addmem FileShare-RW "a.okafor,s.patel"
addmem FileShare-RO "m.singh,r.chen"
addmem "Domain Admins" a.okafor

echo "== group policy"
if ! samba-tool gpo listall 2>/dev/null | grep -q "Workstation Baseline"; then
  samba-tool gpo create "Workstation Baseline" -U Administrator --password="${ADMIN_PASS:-LabAdminPass123!}" >/dev/null 2>&1 \
    && samba-tool gpo setlink "OU=Workstations,$REALM_DN" \
         "$(samba-tool gpo listall | grep -B2 'Workstation Baseline' | grep 'GPO *:' | awk '{print $3}')" \
         -U Administrator --password="${ADMIN_PASS:-LabAdminPass123!}" >/dev/null 2>&1
fi
samba-tool gpo listall 2>/dev/null | grep -A1 "display name" | head -6

echo "== done"
