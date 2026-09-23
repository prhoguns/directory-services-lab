# Runbook: directory user management

## Onboard
```bash
docker exec dc1 samba-tool user create j.doe 'TempP@ssw0rd!2026' \
  --given-name=Jane --surname=Doe --userou='OU=Staff' \
  --job-title='Analyst' --department=Finance --mail-address=j.doe@lab.example.com
docker exec dc1 samba-tool group addmembers Finance j.doe
docker exec dc1 samba-tool group addmembers VPN-Users j.doe
```
Group membership is how access is granted. Never grant rights to an individual account — when they
change teams or leave, nobody can find what they had.

## Password reset
```bash
docker exec dc1 samba-tool user setpassword j.doe --newpassword='NewP@ssw0rd!2026'
docker exec dc1 samba-tool user setexpiry j.doe --days=0     # force a change at next logon
```

## Unlock a locked account
```bash
docker exec dc1 samba-tool user show j.doe --attributes=badPwdCount,lockoutTime
docker exec dc1 samba-tool user enable j.doe
```
Lockout is 5 attempts for 15 minutes (see `samba-tool domain passwordsettings show`). Repeated
lockouts for one user are usually a saved credential on a phone or a scheduled task, not an attack.

## Offboard
```bash
docker exec dc1 /scripts/offboard.sh j.doe
```
Disable → strip groups → move to `OU=Disabled`. **Disable, do not delete.** Deleting the account
destroys the SID, so file ownership and audit trails point at nothing, and restoring access later
means recreating every permission. Delete after the retention period, deliberately.

## Who has admin?
```bash
docker exec dc1 /scripts/audit_report.sh
```
