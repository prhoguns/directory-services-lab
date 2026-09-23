# Runbook: "I can't log in"

Work outward from the client. Most cases are one of the first three.

## 1. Is it the account?
```bash
samba-tool user show <user> --attributes=userAccountControl,badPwdCount,lockoutTime,pwdLastSet
```
`userAccountControl` with `ACCOUNTDISABLE` means disabled. A non-zero `lockoutTime` means locked.
`pwdLastSet = 0` means they must change the password at next logon — which fails silently in some clients.

## 2. Is it the client's view of the domain?
```bash
net ads testjoin                 # "Join is OK" or the reason it is not
wbinfo -u | head                 # can it see domain users at all
getent passwd <user>             # is nsswitch actually using winbind
wbinfo -a '<user>%<password>'    # authenticate directly, bypassing the application
```
`testjoin` failing with a clock or password error usually means the machine account password has
expired — rejoin with `net ads join`.

## 3. Is it time or DNS?
Kerberos fails if the clocks differ by more than five minutes. This is the single most common cause
of "it worked yesterday".
```bash
date; timedatectl status                # compare with the DC
dig +short lab.example.com
dig +short _ldap._tcp.lab.example.com SRV     # clients find the DC through these records
```
If the client's DNS does not point at the domain controller, nothing else will work.

## 4. Is it Kerberos specifically?
```bash
kinit <user>@LAB.EXAMPLE.COM     # get a ticket
klist                            # see it
kdestroy                         # clear cached tickets before retrying
```
A working `wbinfo -a` with a failing `kinit` points at the realm configuration in `/etc/krb5.conf`.

## 5. Is it the DC?
```bash
samba-tool domain info 127.0.0.1
samba-tool dbcheck                        # directory consistency
tail -f /var/log/samba/log.samba
ldapsearch -x -H ldap://dc1 -b '' -s base namingContexts
```
