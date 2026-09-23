# Directory Services Lab

_Status: Built and verified September 22–23, 2026. Every result below came from a real run._

A working Active Directory domain — Kerberos, LDAP, DNS and SMB — with a joined client that
authenticates real users against it. Built on **Samba AD**, which implements the same protocols as
Windows Server AD, so the concepts, the tooling and the troubleshooting are the same.

```
  [ dc1 172.28.10.10 ]  LAB.EXAMPLE.COM  (Kerberos KDC, LDAP, internal DNS, SYSVOL)
        │  OU=Staff · OU=Servers · OU=Workstations · OU=ServiceAccounts · OU=Groups
        │  7 groups · 6 users · 2 service accounts · password policy · a linked GPO
        │
  [ client1 172.28.10.20 ]  domain member via winbind — domain users log in here
```

## Verified end to end — `tests/test_directory.sh`

**30 checks, 0 failures.** The ones that matter:

```
== joined client
  PASS  client has joined the domain            (net ads testjoin -> "Join is OK")
  PASS  client resolves domain users            (getent passwd a.okafor)
  PASS  client resolves domain groups           (getent group Engineering)
  PASS  domain user can authenticate            (wbinfo -a -> challenge/response succeeded)
  PASS  wrong password is rejected
== offboarding
  PASS  offboarded account cannot authenticate
  PASS  offboarded account moved to OU=Disabled
== password policy
  PASS  minimum length 14 · complexity on · lockout after 5 · maximum age 90 days
```

The offboarding check is the one worth pointing at: the test runs the real offboarding script and
then tries to authenticate as that user *from the client*. Access is actually gone, not just
marked disabled in a directory nobody verified.

## What is in the directory

| | |
|---|---|
| OUs | Staff, Servers, Workstations, ServiceAccounts, Groups, Disabled |
| Groups | IT-Admins, Helpdesk, Finance, Engineering, VPN-Users, FileShare-RW, FileShare-RO |
| Users | 6 staff with job titles, departments and mail attributes; 2 service accounts |
| Policy | 14-character minimum, complexity on, 12-password history, 90-day maximum age, lockout after 5 attempts for 15 minutes |
| GPO | "Workstation Baseline", created and linked to OU=Workstations |

Access is granted through **groups**, never to individual accounts — so when someone changes team or
leaves, there is one place to look and one place to change.

## Scripts

| Script | What it does |
|---|---|
| [`setup_directory.sh`](scripts/setup_directory.sh) | Builds the whole structure — OUs, groups, users, memberships, password policy, GPO. Idempotent, so it can be re-run after an edit |
| [`join_domain.sh`](scripts/join_domain.sh) | Joins a Linux host: krb5.conf, smb.conf with `security = ADS`, `net ads join`, winbind in nsswitch |
| [`offboard.sh`](scripts/offboard.sh) | Disable → strip group memberships → move to `OU=Disabled`. Deliberately does **not** delete |
| [`audit_report.sh`](scripts/audit_report.sh) | Password policy, privileged group membership, every account with enabled status and groups |

### Why offboarding disables rather than deletes

Deleting an account destroys its SID. File ownership and audit records then point at nothing, and
restoring access later means rebuilding every permission by hand. Disable, strip groups, move to a
holding OU, and delete after the retention period as a separate deliberate action.

## Run it

```bash
git clone https://github.com/prhoguns/directory-services-lab.git && cd directory-services-lab
cd compose && docker compose up -d --build     # provisions the domain on first boot (~2 min)
docker exec dc1 bash /scripts/setup_directory.sh
docker exec client1 bash /scripts/join_domain.sh
bash ../tests/test_directory.sh                # 30 checks
docker exec dc1 bash /scripts/audit_report.sh  # the report an auditor asks for
```

Explore it the way you would a real domain:

```bash
docker exec dc1 samba-tool user list
docker exec dc1 samba-tool group listmembers 'Domain Admins'
docker exec dc1 ldapsearch -x -H ldap://127.0.0.1 -b 'DC=lab,DC=example,DC=com' '(objectClass=user)' sAMAccountName
docker exec client1 wbinfo -u
docker exec client1 kinit a.okafor@LAB.EXAMPLE.COM     # password: InitialP@ssw0rd!2026
```

## Runbooks

- [User management](runbooks/01-user-management.md) — onboarding, password resets, unlocking accounts, offboarding, and how to answer "who has admin".
- [I can't log in](runbooks/02-authentication-troubleshooting.md) — work outward from the client: account state, `net ads testjoin`, **clock skew** (the single most common cause of "it worked yesterday"), DNS SRV records, then Kerberos itself.

## Things learned the hard way

- `samba-tool domain provision` fails with an unhelpful `ERROR(ldb): uncaught exception - None`
  when **`samba-dsdb-modules`** is missing. The real message — "Unable to load modules for
  secrets.ldb" — is two lines above the traceback.
- Provisioning also refuses to run while the distribution's default `smb.conf` exists, because its
  `server role = standalone server` contradicts the DC role. Remove it and let provision write its own.
- A DC has to resolve its own domain through itself, so `/etc/resolv.conf` must point at `127.0.0.1`
  on the DC and at the DC on every member.
- Rebuilding an image by hand does not update what Compose runs; `docker compose build` is a
  separate cache.

## Next

- A second DC and replication between them (`samba-tool drs showrepl`), then a failure test.
- Kerberos-authenticated SMB shares with access driven by the FileShare-RW/RO groups.
- Real GPO content instead of an empty linked policy.
- Join a Windows client and compare `Get-ADUser` output with `samba-tool user show`.
