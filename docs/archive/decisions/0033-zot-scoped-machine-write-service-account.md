# ADR-0033 archive: Zot machine-write operations use a scoped service account, never the admin/break-glass account

This file holds material moved out of [ADR-0033](../../decisions/0033-zot-scoped-machine-write-service-account.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

1. **Project the machine identity from Authentik (OIDC/SAML).** Rejected — and it is a category error: ADR-0028 C3 makes machine authority *native per-app service accounts in OpenBao*, explicitly **not** Authentik (which is the *human* authority, C1). OIDC/SAML are interactive browser flows; `skopeo` and cron jobs cannot perform them, and machine work must not depend on the IdP being reachable. Even Zot's OIDC grant targets the human `ops-admin` group.
2. **Keep using `admin` (just document it).** Rejected — that is the status quo C3/C4 violation; documenting a routine path onto the break-glass account does not make it compliant.
3. **Give `zot-svc` full `delete`/admin too (simpler policy).** Rejected — least privilege: a seeder/mirror never deletes. `read,create,update` is the minimal write scope.
4. **Store the `zot-svc` secret under `secret/apps/zot/admin` to dodge the ESO policy change.** Rejected — collapses the two identities back into one custody path and defeats the separation. A distinct path + a one-line policy widening is the clean form.
