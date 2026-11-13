# Sources and status for the sandbox security concept

This working presentation describes the planned sandbox lane. Implementation is pending. Recommendations on the final four slides are proposals for the operator to consider.

- [Operator unlock plan](../../plans/operator-unlock-tier2-plan.md): sandbox posture, lifecycle, executor, restore and check-in; especially the sandbox decisions and the sections on approvals, enrolment, check-in and restore. The plan has not yet incorporated the November 12 storage decision.
- The tracking issue for the unlock plan: the operator's decision of 12 November stores one encrypted copy of the recovery keys and the seal key on the system for each enrolled passkey, and the device test results establish that a synced passkey gives the same PRF output on another device. Hardware-key PRF and the full approval session are untested.
- [ADR-0029](../../decisions/0029-tiered-unseal-posture.md): accepted tier vocabulary and deferred implementation. Its amendment for the sandbox remains outstanding.
- [OpenBao seal and recovery keys](https://openbao.org/docs/2.5.x/concepts/seal/): recovery keys and the seal mechanism have different roles. Recovery keys alone cannot recover an unavailable seal mechanism. Verify details against the selected and pinned OpenBao version.

## Matters for design review

The plan calls for a recovery package to support restore, check-in and replacement enrolment. It does not establish how a package containing only a direct seal-material copy performs all three. Specify its contents and test the recovery procedures.

The approval page and executor run on the machine. A malicious administrator who controls either could capture material during a later legitimate approval. Pinned policies and audit checks do not by themselves establish a boundary against control of those components. The deck therefore does not claim that a compromised machine can never create a root token.

The recommended setup sequence, snapshot cadence, optional email, independent credentials, and removal approval are proposals awaiting an operator decision.

The picture story (slides 2 to 11) draws these same claims. `illustrations/scene-notes.txt` lists what each scene shows, and the security explainer checked each scene against the text slides and these sources.

## Added claims on the core-idea and root-token slides

- Root token after the planned vault upgrade: the operator's decision of 13 November records that generate-root moves to an authenticated path. A caller logs in as the admin account first, and the quorum (unseal shares or recovery keys) is still required. The change is not merged yet, so the deck says "after the planned vault upgrade". Source: the operator decision comment on the platform backlog, <https://github.com/dmfdeploy/dmfdeploy/issues/902#issuecomment-6847936906>. `docs/decisions/0051-eso-main-store-kubernetes-auth.md` (Decision 3, Consequences) already says each installed-environment config write needs a generate-root quorum, and says nothing yet about the authenticated caller. It needs a clarification, which goes through an RFC first.
- "When the vault is closed, nothing new can be issued or rotated": a sealed vault serves nothing until it gets its key. Source: `docs/decisions/0029-tiered-unseal-posture.md` (Context) and `docs/decisions/0009-shamir-dr-model.md` (Context). No repo source says what apps do with secrets they already hold while the vault is closed, so the deck makes no claim about it.
- What the open vault does (secrets to apps through the External Secrets helper, narrow machine accounts, day-to-day app secret administration): `docs/decisions/0008-openbao-secrets-architecture.md` (Decision, Consequences); `docs/decisions/0021-openbao-approle-reconciler-identity.md`; `docs/decisions/0032-catalog-launcher-scoped-netbox-writer.md`. Every request still needing a sign-in follows from the scoped identities in those decisions.

## Icons

The fingerprint, closed padlock and open padlock glyphs come from Material Icons and Material Symbols by Google, Apache License 2.0 (<https://github.com/google/material-design-icons>, browse at <https://fonts.google.com/icons>). The path data is in `illustrations/icons.py`, and `illustrations/icon-credits.txt` repeats the credit. Everything else in the scenes and diagrams is drawn by hand. The open padlock (outlined, with a lifted shackle, green) and the closed padlock (filled, with a closed shackle, red) differ in shape as well as colour. The padlock shows the state of the vault wherever it appears.

