# ADR-0050: Flypack mode (portable offline kit)

**Status:** Proposed
**Date:** 2026-05-11
**Deciders:** operator
**Rule:** The Mode C constraints are proposed reference text for any flypack work. They bind no implementation today.

## Context

This ADR holds Mode C, which was split out of [ADR-0020](0020-deployment-scope-and-regulatory-posture.md) on 2026-11-06. In that ADR, Mode A (OSS self-host) is the Accepted decision. See that ADR for the three-mode framing.

## Decision

### Mode C: Flypack (portable offline kit)

**Regulatory posture:** Mode B obligations *plus* ISO 27001 A.7.10
(Storage media), A.7.13 (Equipment maintenance), A.7.14 (Secure disposal)
applied to physical hardware; EBU R 143 vendor-systems acceptance for
the assembled kit. Lost or stolen flypack = mandatory 72 h GDPR Art. 33
breach assessment.

**Binding architectural constraints:**

1. **Per-flypack ephemeral identity** issued at first boot via a
   provisioning ceremony; no shared identities across flypacks.
2. **Secrets sealed to local TPM/HSM.** They are never recoverable from disk
   alone. Shamir share threshold inside the unit, recovery shares held
   by the operator off-pack.
3. **Tamper-evident enclosure + documented loss procedure** in the
   incident response runbook before any flypack ships.
4. **No automatic phone-home.** If a flypack reconnects to dmfdeploy.io
   it does so via an explicitly installed customer-side relay; the
   flypack must function disconnected.

### Amendment 2026-05-23: Mode C remains Proposed

- **Mode C (flypack) remains Proposed.** ADR-0022 (flypack-online thin
  edge) already split out the WAN-paired variant; flypack-offline (Mode C
  as originally framed) still awaits hardware-reference work. Promotion
  is gated on Status criterion 5 plus a named operator/integrator partner
  for the sealed-hardware ceremony.

## Consequences

- **Negative**
  - Mode B and Mode C *require* compliance work to ship, and cannot be
    deferred indefinitely the way Mode A can.

### Enforcement

Discipline only: no script, test or workflow checks Mode C.

- **Mode C architectural constraints (C.1–C.4):** the flypack readiness
  checklist (Tier C of the
  [Pre-Release Compliance Readiness Plan](../plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md))
  is the gate. No flypack ships without that checklist clean. People follow
  the checklist by hand; no script runs it.

## Status

Proposed

Promote from **Proposed** → **Accepted** when:

5. The flypack hardware story (C.1–C.4) has at least one identified
   reference platform (TPM-equipped mini-PC class).
