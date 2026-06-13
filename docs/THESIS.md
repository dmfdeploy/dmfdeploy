# The DMF thesis — one page

**The claim:** a software-defined media facility, as described by the
[EBU](https://tech.ebu.ch/) *Dynamic Media Facility* Reference Architecture,
can run on one commodity ARM64 box using only open-source infrastructure — and
a stranger can stand it up and verify it without talking to a vendor or to me.

**Where the claim stands:** the first half is demonstrated — first-party, on
the author's environments
([Move 1 learnings](reviews/dmf-platform-move-1-learnings-2026-06-04.md)). The
second half — *stranger*-reproducibility — has not happened yet and is the
entire point of the current
[v0.1 plan](plans/DMF%20v0.1%20Commitment%20%26%2030-Day%20Focus-Cut%20Plan%202026-06-06.md).
If you run the loop below, you are the experiment.

## Who it's for

Broadcast and media-tech engineers who need the *operational fabric* of an
IP-media facility — identity, secrets custody, source-of-truth inventory,
deployment, monitoring — at OB-truck or small-facility scale, and who today
choose between a proprietary vendor stack and a months-long DIY integration
project. Also: anyone who wants to study a complete, working EBU-DMF-aligned
build whose every decision is on the record.

## The first pain it solves

Deploying a media function (an NMOS registry, an MXL — Media eXchange Layer —
fabric) is the easy 10%.
The hard 90% is everything around it: who may operate it, where its secrets
live, what the facility's source of truth says is running, how it gets deployed
repeatably, and how you know it's healthy. DMF packages that 90% as a
bootable whole: one installer container takes a **blank Debian node** to a
running facility — k3s, Authentik (passkey-first identity), OpenBao (secrets),
NetBox (source of truth), AWX (commissioning engine), Prometheus/Grafana
(NetBox-driven monitoring), and an operator console — with a deployable
media-function catalog on top.

## What a stranger validates in under an hour — the v0.1 gate

This loop has been run first-party; making it stranger-runnable from public
artifacts is the v0.1 release gate, not an accomplished fact.

1. **Bootstrap:** run the [dmf-init](https://github.com/dmfdeploy/dmf-init)
   container against a blank ARM64 Debian node (one node, ≥4 vCPU / 8 GiB —
   a small cloud instance or a local VM); watch it converge to a full platform.
2. **Identity:** enroll a passkey and log into the operator console — no
   passwords in the steady state, by decision
   ([ADR-0015](decisions/0015-dmf-console-passkey-only.md)).
3. **Deploy:** click *Deploy* on the NMOS registry catalog entry.
4. **Inspect the receipts:** the AWX job that ran, the NetBox lifecycle tag it
   flipped, the Helm release it created, and the Prometheus targets that
   appeared — generated from NetBox, not from a static config.

That loop — catalog intent → actuated deployment → source-of-truth state →
observed health — *is* the platform. Everything else is depth.

## What v0.1 does **not** claim

The non-claims are explicit by decision (see
[ADR-0031](decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
and [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md)): no production ST-2110/PTP/multicast
correctness, no real-time media-plant claims, no multi-node HA, no cross-site
federation, no performance numbers. Single-node is the proof surface; the rest
is named future work, not implied capability.

## Why believe it

The thesis was tested as a falsifiable experiment, not asserted: the
[Move 1 learnings](reviews/dmf-platform-move-1-learnings-2026-06-04.md) record
six architectural assumptions and their verdicts, including the one still
unproven. The full arc is in [JOURNEY.md](JOURNEY.md); the decisions are in the
[ADR record](decisions/INDEX.md#start-here).
