# Mail module

Deploys a single-node Stalwart mail server and SnappyMail webmail in the
`mail` namespace.

## Public endpoints

- `mail.<domain>`: SMTP 25, SMTPS 465, Submission 587, IMAPS 993, HTTP/JMAP.
- `admin-mail.<domain>`: Stalwart administration UI.
- `webmail.<domain>`: SnappyMail.

POP3 is not routed publicly by default.

## DNS

Set `mail_server_ipv4` and optionally `mail_server_ipv6` before applying if this
server will receive mail directly from the Internet. When at least one address is
set, the module creates:

- `A` / `AAAA` for `mail.<domain>`.
- `MX` for the root domain pointing to `mail.<domain>`.
- initial SPF and DMARC TXT records.

DKIM is intentionally not created here because Stalwart generates the domain key
after the domain is configured. Add the DKIM TXT record shown in Stalwart after
creating the domain.

Reverse DNS / PTR must be configured at the VPS/provider level, outside
Cloudflare and Terraform.

## First access

After apply:

```sh
terraform output -raw mail_recovery_admin_password
```

Use `admin` plus that password at `https://admin-mail.<domain>`. Create the real
administrator, domains, mailboxes, aliases, quotas, and per-application app
passwords there.
