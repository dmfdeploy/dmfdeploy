# ADR-0034 archive: No public Ansible Galaxy at runtime; internal collection source

This file holds material moved out of [ADR-0034](../../decisions/0034-internal-ansible-collection-source.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Bake into EE + delete `requirements.yml`** (the v0.1 expedient).
  Accepted as the *interim* unblock, rejected as the *permanent* shape:
  it discards the declarative manifest and makes the EE opaque.
- **Vendor collections into the project repo.** Rejected as the primary
  mechanism: bloats the repo and still runs `ansible-galaxy` per sync.
- **Self-hosted Galaxy NG / Automation Hub.** Rejected: operationally
  heavy for the platform's scale; Zot-OCI or Forgejo-git achieves the
  same air-gap guarantee with existing services.
