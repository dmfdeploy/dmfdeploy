---
status: active
date: 2026-11-07
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/864
---

# Operator unseal Tier 2 plan

**Related issues:** [#12](https://github.com/dmfdeploy/dmfdeploy/issues/12),
[#396](https://github.com/dmfdeploy/dmfdeploy/issues/396),
[#866](https://github.com/dmfdeploy/dmfdeploy/issues/866)

**Source:** the RFC in
[Discussion #865](https://github.com/orgs/dmfdeploy/discussions/865) and the
operator's decisions comment on it, dated 2026-11-07, and the operator's
decisions of 2026-11-08 on the sandbox lane (decisions 12 to 20 below). The
RFC holds the evidence, the threat model and the reasoning. This plan holds
the work. The RFC calls the page that starts the unseal the unlock page. This
plan calls it the unseal page.

In this plan, an enrolled admin device is any device that holds an enrolled
credential: a phone, a laptop or tablet with a platform authenticator, or a
hardware security key with a PIN. The plan says "phone" only where it means a
phone, such as a push-notification test.

## Goal

One admin, who may not be technical, runs the sandbox lane with no manual
unseal step. OpenBao auto-unseals on every boot, with no admin action and no time
window (decision 12). The admin authorizes the rare privileged changes, a
root token or a restore, with one confirmation on an enrolled admin device,
without physical access to the node. Under ADR-0029 an auto-unseal on every
boot is Tier 3, so the declared posture of the sandbox lane is Tier 3 with
recovery keys held on enrolled admin devices (decisions 13 and 14). The plan
never describes that lane as Tier 2, because the declared posture must equal
the actual one. The seal key stays on the node in this lane. The recovery
keys do not, so material on the node cannot mint a root token.

*Changed on 2026-11-08.* Before this date the goal was ADR-0029 Tier 2
("Operator unseal") for the sandbox and open source lane, with a phone
confirming every cold-boot unseal and no unseal material at rest on the node.

A lane that needs a boot-time unseal keeps Tier 2 as this plan designs it.
For that lane, the boot-time properties of WP5 (the sealed-node notification,
the boot-bound session and the no-material-at-rest scan), WP7 and the
no-material-at-rest constraint apply in full. The device lifecycle (WP6), the
audit spool (WP9) and the check-in (WP8) apply to every lane. This plan
designs nothing for regulated lanes.

The goal is the most security achievable without adding friction for admins.
Physical and local root access to the node is a known, accepted risk in this
lane. Lanes with legal or regulatory obligations, such as dual control, a
specific authentication level and strict write-once audit, are out of scope
and need their own changes later.

## Decisions

The operator approved decisions 1 to 11 on Discussion #865 as recommended. On
2026-11-08 the operator added decisions 12 to 20 and changed the posture of
the sandbox lane. Where a change touched decisions 1, 3, 6 or 7, the decision
carries a note that says what changed on 2026-11-08. This plan carries all
twenty as written. A work package does not widen or narrow them. If a package
needs a different scope, stop and ask for a new decision.

1. HA OpenBao first for long-lived sites. A single replica is allowed in the
   sandbox lane through an ADR-0029 amendment with a visible warning. The
   signed, boot-checked tier and the audited downgrade stay. The ADR-0011
   automation quorum is retired before Tier 2 is declared, and the ADR-0009
   five-share distribution is re-checked. *Changed on 2026-11-08:* in the
   sandbox lane the automation quorum is retired when the auto-unseal seal
   replaces the Shamir seal (decision 13). The lane declares Tier 3
   (decision 12). The five-share re-check applies only to a site that keeps a
   Shamir seal.
2. A name-limited private certificate authority with its key on the kit, or a
   public certificate where the kit can renew one. No unrestricted private
   authority without explicit approval.
3. The unseal page is the source of truth. Offline alerts are tested on a
   real phone of each major mobile platform before the plan commits to them.
   *Changed on 2026-11-08:* in the sandbox lane the alert tests are optional,
   because no ceremony starts at boot (decision 20).
4. Option (b): no per-boot token for Tier 2, through an ADR-0029 amendment.
5. Spool first, then delivery. A full spool never blocks an unseal, and a lost
   record is accepted. ADR-0029's audit guardrail is amended for the sandbox
   lane.
6. The device lifecycle properties, including the rekey and the reissue of
   the recovery shares. *Changed on 2026-11-08:* in the sandbox lane a
   removal or a transfer rotates the recovery keys and the seal key, and
   re-encrypts the retained devices' copies (decision 17).
7. The single unseal session design: the wrapped copy lives on the enrolled
   admin device, the QR code carries a single-use session URL, and the device
   unwraps the key. *Changed on 2026-11-08:* in the sandbox lane the same
   session design carries root token approval and restore, and not a boot
   unseal. The wrapped copy holds the recovery keys and the seal key
   (decisions 14 and 15).
8. The ADR-0029 Tier 2 row is amended to platform user verification,
   including a device PIN.
9. Catch-up after unseal is left to a later plan. It depends on
   [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866) and
   [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396). ADR-0051
   (PR dmfdeploy/dmfdeploy#877, Proposed) removes the main ESO store from that
   catch-up, because Kubernetes auth holds no stored credential that can
   expire. The other AppRole consumers remain in it.
10. Periodic admin check-in: a 30-day period, warnings at 14, 7, 3 and 1 days,
    and on expiry privileged changes wait while workloads keep running. The
    recovery package path always works.
11. Next step: a plan in `docs/plans/` with `tracking_issue: 864`. Its first
    work package runs the real-device confirmations from Appendix B of the
    RFC.
12. Dated 2026-11-08. The sandbox lane auto-unseals on every boot, with no
    admin action and no time window. Under ADR-0029 this is Tier 3. The lane
    declares Tier 3 and is never described as Tier 2, so the declared posture
    equals the actual one.
13. Dated 2026-11-08. Unseal uses an auto-unseal seal whose recovery keys are
    separate from the seal key. Generate-root then asks for recovery keys.
    Material on the node cannot mint a root token. The seal type is one that
    the pinned OpenBao version ships, and the ADR-0029 amendment (WP2) records
    it.
14. Dated 2026-11-08. One enrolled admin device holds enough recovery key
    material to meet the threshold alone, so a single admin can approve root
    token creation. The device is a phone, a laptop or tablet with a platform
    authenticator, or a hardware security key with a PIN. The sandbox lane
    needs at least two enrolled admin devices. The ADR-0009 recovery package
    stays the last resort.
15. Dated 2026-11-08. Recovery keys cannot unseal. They only authorize, as the
    OpenBao seal documentation says. The seal key therefore needs its own
    backup: a copy encrypted to each enrolled admin device and stored with
    the Raft snapshots, and a direct copy in the recovery package.
16. Dated 2026-11-08. The device screen names the operation: unseal, root
    token or restore. A generated root token is used only by a server-side
    executor, to mint a token scoped to the one named change. The root token
    is revoked at once. The generate-root, the mint, both revokes and the
    change are audited.
17. Dated 2026-11-08. Removing a lost or stolen device rotates the recovery
    keys and the seal key, and re-encrypts the copies for the remaining
    devices.
18. Dated 2026-11-08. Synced passkeys are the sandbox-lane default. The risk
    is a takeover of the passkey sync account. That is a remote risk, and the
    accepted local-root risk does not cover it. The limits are encrypted
    copies on access-controlled storage, unseal and approval surfaces on the private
    network only, and an audit record of every use.
19. Dated 2026-11-08. After the loss of every copy of the seal key on the
    nodes, dmf-init restores the latest snapshot and asks one enrolled admin
    device to decrypt the seal key. A QR code serves the case where the
    authenticator is on another device. The Kubernetes auth config is
    portable: it uses the in-cluster API DNS name, the pod's local CA and token
    files, and no pinned CA. A snapshot restored to a new cluster then works
    without a root token write. The portable config is a property of the plan for
    [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866).
20. Dated 2026-11-08. With no boot-time unseal, every remaining device
    ceremony starts with the admin at a screen. Push notifications are
    therefore optional for the sandbox lane, including the portable kit's push
    server. The push design stays for lanes that need a boot-time unseal.

## Binding constraints

- Follow ADR-0029's guardrails as amended by WP2, ADR-0009 for the recovery
  package, and ADR-0028 for audit attribution.
- Do not print a root token, an unseal share, a recovery key, the seal key, a
  passkey output, a session URL or a ServiceAccount token in a task result,
  log, test fixture, or issue or PR body. Record metadata only.
- In a lane that keeps a boot-time unseal, no unseal material rests on the
  node: not the plaintext, and not the wrapped form. That covers disks,
  backups, swap, crash dumps and logs.
- In the sandbox lane, the seal key rests on the node by design (decisions 12
  and 13). No recovery key rests on the node in plaintext. Only copies that
  are encrypted to enrolled admin devices may rest there or in backups.
- Run cluster writes only through the sanctioned playbook path.
- Name no product as a design source. Cite standards and upstream
  documentation.
- Do not design for regulated lanes, and do not design the catch-up after
  unseal.

## Order and gate

WP1 is the gate. No code in WP5 to WP10 starts until the results of WP1 are
recorded on [#864](https://github.com/dmfdeploy/dmfdeploy/issues/864). Work
that needs no device result can run before that.

| WP | Needs first | Can run in parallel with |
|---|---|---|
| WP1 device confirmations | nothing | WP2, WP3 |
| WP2 ADR-0029 amendments | the converged RFC | WP1, WP3 |
| WP3 HA OpenBao | nothing | WP1, WP2 |
| WP5 unseal page and session | WP1 recorded, WP2 merged | WP9 |
| WP9 audit spool and delivery | WP1 recorded, WP2 merged | WP5 |
| WP6 enrollment and lifecycle | WP5 | WP9 if it is still open |
| WP7 portable kit | WP1, WP5, WP6 | WP8 |
| WP8 periodic check-in | WP6, WP9 | WP7 |
| WP10 restore with an enrolled admin device (sandbox lane) | WP5, WP6, the WP4 rehearsal, and the portable config in the #866 plan's WP3 | WP7, WP8 |
| WP4 seal transition and retiring the automation quorum | WP1, WP2, and the site's applicable packages | nothing: its live change is the last package for a site |

WP5 and WP9 ship to an environment together, because the page writes its
records to the spool. WP4 comes last in time even though it is numbered
fourth: the quorum is retired only when the replacement works, and the posture
is declared only after that. For the sandbox lane, the WP4 rehearsal runs
before WP10, and the WP4 live change runs after WP10.

### What each WP1 result opens

A result of confirmed, or confirmed with a limit, opens the work that depends
on it, and the limit goes into that work's properties. An essential property
that is unconfirmed or fails keeps the dependent work blocked until the
operator decides; only a confirmed result, or an explicitly accepted limit,
opens it. These are the essential properties: PRF output with user
verification on a platform, the end-to-end unseal session on a platform, and
the certificate path for a kit. A platform where one is unconfirmed or fails
stays out of WP5 to WP10 until the operator decides what happens to it. A failure of the
offline alert, or limited wrapped-copy storage, opens the work with its
fallback: the saved page for the alert, and the second device and the
recovery package for storage.

### Site rollout and plan completion

These are two different events.

- **A site is ready to declare its posture** when WP1 and WP2 are done and the
  packages that apply to that site are done with their evidence. These are
  WP5, WP6, WP8 and WP9 for every site, WP3 for a long-lived site, WP7 for a
  kit, and WP10 for a sandbox-lane site. The posture is Tier 3 with device-held
  recovery keys in the sandbox lane, and Tier 2 in a lane with a boot-time
  unseal. WP4 then runs for the site, with the operator's approval.
- **The plan is complete** when every package is closed. The completing PR
  archives the plan as WORKING-MODEL section 5 requires: it sets the
  frontmatter to `status: executed` with an `executed:` date, moves the plan
  to `docs/archive/plans/`, fixes the links to it, regenerates the plans
  index, and closes [#864](https://github.com/dmfdeploy/dmfdeploy/issues/864)
  with a qualified `Closes` reference. One site's rollout never closes the
  plan.

Each work package fits in one session. The "Needs from the operator" line
says when the operator must be present.

## Work packages

### WP1 real-device confirmations

**Goal.** Replace the RFC's unconfirmed items with recorded results from real
devices and a disposable environment.

**Needs from the operator.** One device of each type that the operator will
enroll, with its software version: a phone of each platform the operator
uses, a laptop or tablet with a platform authenticator, and a hardware
security key. Also a disposable environment or kit to test against.

**Dependencies.** None. The RFC's Appendix B lists the items.

**Properties that must hold.** Each item gets one recorded result: confirmed,
unconfirmed, or confirmed with a limit, with the device and software
version. No result is inferred from a vendor page.

- PRF output is available on each device type that the operator will enroll
  (phone, laptop or tablet authenticator, hardware security key) for a
  passkey enrolled at the unseal page's host name, and it is stable across two
  authentications (decisions 14 and 18).
- A synced passkey is checked as its own case. The result records whether the
  PRF output stays the same when the passkey syncs to a second device, and
  whether a copy encrypted on one device decrypts on the other.
- The PRF output is returned only after user verification, and a device PIN
  works where the device offers one, including a hardware security key.
- The single unseal session works end to end on each platform: QR code scan, the
  session page opening on the enrolled admin device, the passkey assertion,
  local unwrap, and the submission. A device that cannot scan the QR code
  records the cross-device path that covers it.
- The wrapped copy survives the device's storage rules over the check-in
  period, or the result records the eviction behavior and what covers it.
- An offline alert from a notification server on a local network reaches each
  phone platform in a time the admin can live with, or the result says it
  does not. The saved page on the home screen is tested as the fallback. The
  sandbox lane does not need this item (decision 20), so a lane that needs a
  boot-time unseal is the only one that waits for it.
- A private certificate authority limited by name to the kit's host name is
  honored on each platform, or the result says it is not. A private host name
  works as a relying party ID, and the result records which rule in the
  WebAuthn specification applies to a host that equals the RP ID.
- If a site uses the optional private mesh layer, the names and certificates
  it provides work as an RP ID. Otherwise this item stays closed.
- An interrupted OpenBao rekey on a disposable environment is cancelled or
  resumed, and the result records whether the old keys stay valid until it
  completes. WP6 uses this result.

**Closing evidence.** A comment on #864 with a table: item, device and
software version, result, and the decision it affects. No token or unseal
share appears in it.

**Done when.**

- [ ] Every RFC Appendix B item has a recorded result or an explicit reason it
      is closed.
- [ ] Results that contradict a decision are flagged on #864 for the operator.
- [ ] Each result is mapped to the work it opens, using "What each WP1 result
      opens". An essential property that is unconfirmed or failed has an
      operator decision recorded before its dependent work starts.
- [ ] The Status section below is updated, and the gate is open or stays shut.

### WP2 ADR-0029 amendments

**Goal.** Amend ADR-0029 through the RFC-to-ADR path so that the code in the
later packages matches an accepted decision.

**Needs from the operator.** Review of the draft and acceptance. The RFC
thread has already converged.

**Dependencies.** The approved decisions. No device results are needed.

**Properties that must hold.**

- The amendments are exactly five, and each cites its decision:
  - Single replica allowed in the sandbox lane, with a visible warning
    (decision 1).
  - No per-boot token for Tier 2, which keeps the token for Tier 1
    (decision 4). The amendment states that removing the token weakens the
    original proof of infrastructure access.
  - The Tier 2 row says user verification by any method the platform offers,
    including a device PIN (decision 8).
  - The audit guardrail for the sandbox lane: records go to a local spool
    first and are delivered to the write-once target when reachable, a full
    spool never blocks an unseal, and a lost record is accepted (decision 5).
  - The sandbox-lane posture as a named sub-variant of Tier 3, with
    device-held recovery keys (decisions 12 and 13). The amendment states these
    properties of the variant:
    - the auto-unseal seal;
    - recovery keys separate from the seal key, held on enrolled admin
      devices, where one device meets the threshold alone and at least two
      are enrolled (decision 14);
    - the seal key backed up as decision 15 says;
    - the audit record of the unseal itself as a system action under
      ADR-0028, with each approval carrying the enrolled admin as actor.

    It states that the declared posture equals the actual one, so the lane is
    never described as Tier 2. It
    records the synced-passkey risk and its limits (decision 18). The ADR's
    Enforcement section says what checks the declared tier against the
    configured seal: the boot-time check from WP5, or "discipline only."
- The signed, boot-checked tier and the audited downgrade are unchanged, and
  the ADR still says so.
- The ADR keeps its **Rule:** line and its `## Enforcement` section, and the
  section names the mechanism each later package adds or says "discipline
  only."
- The ADR links the RFC thread. The decision index is current.
- ADR-0050's TPM sealing constraint conflicts with Tier 2 on a kit. This plan
  does not change that ADR while it is Proposed. The amendment waits for its
  promotion, and WP7 records the conflict.

**Closing evidence.** The merged amendment, the index entry, and the
announcement thread that the RFC process requires.

**Done when.**

- [ ] The five amendments are merged and accepted.
- [ ] The announcement thread is posted.
- [ ] The Status section is updated.

### WP3 HA OpenBao with Raft for long-lived sites

**Goal.** Run OpenBao as a Raft cluster on long-lived sites, so a single-node
restart keeps OpenBao serving.

**Needs from the operator.** A disposable environment to rehearse on, and an
approval before any installed environment migrates. The migration is a live
change.

**Dependencies.** [#12](https://github.com/dmfdeploy/dmfdeploy/issues/12). No
device result is needed, so this runs in parallel with WP1 and WP2.

**Properties that must hold.**

- A new install of a long-lived site creates a Raft cluster of OpenBao nodes.
  Until the WP4 seal change lands for a lane, the install starts with the
  Shamir seal. After it lands in the sandbox lane, a new sandbox install
  starts with the auto-unseal seal. A lane with a boot-time unseal keeps the
  Shamir seal.
- HA keeps OpenBao serving while one node restarts. Under a Shamir seal it
  does not remove the unseal. Each restarted node is sealed again and needs
  the threshold of shares, and it is brought back before the next node
  restarts. A rolling upgrade is a sequence of restarts, each followed by an
  unseal. In the sandbox lane after the WP4 seal change, a restarted node
  unseals itself, and the guard waits until the node reports unsealed.
- The upgrade and drain procedures say so, and they refuse to restart the next
  node while a restarted node is still sealed.
- A migration from a single replica keeps the existing data and the ADR-0009
  shares valid where an environment already has them, and a rehearsal on a
  disposable environment passes first. The rehearsal reads the same data
  before and after. Under a Shamir seal it unseals with the recovery shares.
  In the sandbox lane after the WP4 seal change, it shows an unseal on restart
  with no admin action and an approval by an enrolled admin device. No secret
  value is recorded. The move from a one-share sandbox to the auto-unseal seal
  belongs to WP4.
- Single-replica installs stay supported in the sandbox lane, with the visible
  warning that WP2 requires.

**Closing evidence.** A rehearsal on a disposable environment: the cluster
state after a single-node restart, the time to serve, the sealed state of the
restarted node, the rolling-restart refusal, a before and after data read of
the same objects. After the migration, the evidence is a recovery-share
unseal under a Shamir seal. In the sandbox lane after the WP4 seal change, it
is an unseal on restart with no admin action plus an approval by an enrolled
admin device. Records carry no secret values.

**Done when.**

- [ ] A new long-lived install runs the Raft cluster.
- [ ] A restart of one node leaves OpenBao serving, and the rolling-restart
      guard works.
- [ ] The migration from a single replica is rehearsed, with the before and
      after data read and the seal-appropriate evidence: the recovery-share
      unseal under a Shamir seal, or an unseal on restart plus a device
      approval in the sandbox lane after the WP4 seal change. An installed
      environment moves only after a separate approval.
- [ ] #12's HA item is closed or re-scoped, and its other items are untouched.
- [ ] The Status section is updated.

### WP5 unseal page and unseal session

**Goal.** Build the pre-start page and the single-use session that lets an
enrolled admin device approve an operation. In a lane that needs a boot-time
unseal, the operation is the unseal. In the sandbox lane there is no
boot-time unseal job, so the page approves a root token and a restore.

**Needs from the operator.** A disposable environment, and the real devices
from WP1 for the end-to-end check.

**Dependencies.** WP1 recorded. WP2 merged. WP9 in parallel.

**Properties that must hold in every lane.**

- The page starts before every other service and needs nothing from OpenBao,
  the console or External Secrets Operator, so a restore can use it when
  OpenBao is gone. It is reachable only on the private network.
- The enrolled admin device runs its own passkey assertion, unwraps its own
  wrapped copy locally and submits to the session. No other device sees key
  material. The laptop in the QR flow only shows the QR code.
- The session accepts one submission, expires after a short time and cannot
  be replayed. Only a session that completed a passkey assertion for an
  enrolled credential, and that holds the wrapped copy, may submit. The
  session URL alone approves nothing.
- The page never logs the passkey output, the unwrapped material or a session
  URL. Every submission is rate limited.
- The declared tier is bound in git-tracked config, checked cryptographically
  at boot, and lowered only through a signed, audited change, as ADR-0029
  requires. The check compares the declared tier with the configured seal, so
  a mismatch is refused (decision 12).
- The credential is bound to the page's host name as a relying party ID. The
  page asks for user verification and accepts the platform's methods.
- The unseal page itself needs a stable host name, and a site whose name
  changes enrolls again.

**Properties that must hold in the sandbox lane.**

- Each session is bound to one named operation: root token or restore. The
  device screen names that operation before the admin confirms, and an
  approval for one operation cannot authorize another (decision 16).
- Approval of a root token needs the recovery keys, which an enrolled admin
  device holds. One device meets the threshold alone, and material on the node
  cannot mint a root token (decisions 13 and 14).
- A root token has unrestricted authority, so the plan does not rely on a
  revoke after the change. A server-side executor handles every approved root
  token (decision 16):
  - The generated root token goes only to the executor. It never reaches the
    device, the page, a log or any caller.
  - The executor uses the root token for exactly one call: it mints an orphan
    token with the policy for the named change, with a short TTL and a use
    limit. Each approvable change has its own policy, installed beforehand by
    the installer, that allows only the path and capabilities that change
    needs, so the mint needs no policy write.
  - The executor revokes the root token synchronously, before it performs the
    change. The change runs with the scoped token, which the executor also
    revokes when the change is done.
  - On any failure, the executor revokes both tokens before it returns.
  - The device screen names the change, and the executor accepts only the
    change bound to that session.
  - The audit records the enrolled admin as actor for the generate-root, the
    mint, the root revoke, the change and the scoped revoke. No token value
    appears in a log, result or record.
- The page has no job at boot. OpenBao auto-unseals without it (decision 12).

**Properties that must hold in a lane with a boot-time unseal.**

- The session is bound to the cold boot that created it.
- No unseal material rests on the node. Material exists on the node only in
  memory, for the length of one unseal. That covers disks, backups, swap,
  crash dumps and logs.
- On an online site, a sealed node notifies the admin, and the notification
  carries a link that opens the unseal session on the admin's device. This
  covers the online flow with a laptop and QR code and the flow with only a
  phone.

**Closing evidence.** On a disposable environment, these results:

- In the sandbox lane: a change approved from one enrolled admin device and
  run through the executor. After the executor returns, a lookup of the root
  token fails because it is revoked, and the scoped token is revoked as well.
  An approval for restore that fails to mint a root token, and the reverse.
- In the same rehearsal, a negative test on a disposable environment: during
  the run, a second or unrelated mutation with the scoped token is refused by
  OpenBao.
- A crash test: a crash of the executor after the mint leaves the root token
  already revoked and the scoped token expiring within its short TTL.
- Audit entries for the generate-root, the mint, the root revoke, the change
  and the scoped revoke, with no token value.
- In a lane with a boot-time unseal: a cold boot unsealed by one admin with an
  enrolled admin device and without access to the node. It starts from the
  sealed notification and its link, on the online flow with a laptop and QR
  code and on the flow with only a phone. A scan of disks, backups, swap,
  crash dumps and logs finds no unseal material.
- Negative tests that each fail to approve: a replayed session, an expired
  session, a wrong credential, a session from another operation or another
  boot, the session URL alone, a session with no wrapped copy, a session with
  missing or failed user verification.
- A rate-limit test that shows submissions refused after the limit.
- A boot with a tampered or lower declared tier, or a declared tier that
  differs from the configured seal, refused at boot. A downgrade succeeds only
  through the signed change, and the audit records it.

**Done when.**

- [ ] In the sandbox lane, a change is approved from an enrolled admin device
      and run through the executor. The root token lookup fails afterward, and
      the scoped token refuses a second or unrelated mutation. The crash test
      passes, and the audit entries are complete.
- [ ] In a lane with a boot-time unseal, a cold boot is unsealed from an
      enrolled admin device on the disposable environment, and the
      no-material-at-rest scan, crash dumps included, passes.
- [ ] Every negative test and the rate-limit test pass.
- [ ] A tampered or lower tier, or a tier that differs from the seal, is
      refused at boot, and an audited signed downgrade works.
- [ ] In a lane with a boot-time unseal, the online notification and link
      flows unseal end to end.
- [ ] The Status section is updated.

### WP9 audit spool and delivery

**Goal.** Record every unseal-related action locally first, and deliver the
records when the write-once target is reachable.

**Needs from the operator.** Nothing beyond review. The device results from
WP1 are the gate.

**Dependencies.** WP1 recorded, WP2 merged. Built in parallel with WP5, which
writes to it.

**Properties that must hold.** These follow decision 5 and the RFC's audit
section.

- Records go first to a local, bounded spool, before any network service is
  up. They are delivered to the write-once target when it is reachable, and
  the spool is cleared only after delivery.
- An authenticated action records the actor (the enrolled admin that the
  credential belongs to), the role, a request ID and a reason, and an
  automatic reason such as "cold-boot unseal" is enough. An unseal also
  records the verified time of the assertion, the credential identifier and
  the user-verification result. Device details that the device reports about
  itself are labeled as claimed. No record says "biometric."
- A failed attempt by someone who has not authenticated records the source
  address and the time, with the actor marked unknown.
- Each record carries a hash of the previous record and a sequence number.
  The chain shows accidental changes, and it does not prove that no one
  edited the spool on purpose. The sequence shows a gap only while the
  counter survives. Resisting root is out of scope.
- When the spool cannot write, the unseal still proceeds, and the record of it
  can be lost. Some lost records may never be detectable. A refusal would
  turn a full spool into an outage.

**Closing evidence.** Tests for the record contents, the chain and the
sequence, a full-spool unseal that proceeds, and a delivery after the target
comes back.

**Done when.**

- [ ] Records carry the fields above and are delivered after an outage.
- [ ] A full or unavailable spool never blocks an unseal, and the test shows
      the lost record and the visible gap where one is detectable.
- [ ] The Status section is updated.

### WP6 enrollment, device lifecycle, rotation and recovery material

**Goal.** Enroll the admin's first device and a second device at install, let
the admin add, remove and transfer devices later, and keep removed devices
from approving anything.

**Needs from the operator.** A disposable environment and two enrolled admin
devices, with at least one of them a different device type from the other.

**Dependencies.** WP5. WP1's rekey-interruption result.

**Properties that must hold.** These follow decisions 6, 14, 15, 17 and 18.
The key material is the recovery keys and the seal key in the sandbox lane,
and the unseal key material in a lane with a boot-time unseal.

- At install, the admin registers the first enrolled admin device and enrolls
  a second device. The minimum is two, and an install without both is not
  complete. Later enrollment happens only in the running console, behind its
  normal sign-in. The unseal page never enrolls.
- One enrolled admin device meets the recovery threshold alone. Losing any one
  device leaves the other able to approve.
- In the sandbox lane, every enrolled device holds its own independently
  encrypted copy of the recovery keys and of the seal key. The copy of the
  seal key is also stored with the Raft snapshots, and a direct copy is in the
  ADR-0009 recovery package (decision 15). In a lane with a boot-time unseal,
  every enrolled device holds its own independently wrapped copy of the
  unseal key material, and any one of them can unseal.
- An already enrolled device approves, decrypts the key material on that
  device and encrypts a copy for the new one. When no enrolled device is
  available, the ADR-0009 recovery package approves. The current owner is
  notified when a device is added.
- In the sandbox lane, removal and transfer rotate the recovery keys and the
  seal key, and re-encrypt the copies for the retained devices only,
  including the copies stored with the snapshots. Every copy encrypted under
  the old key material stops working. A snapshot taken before the removal
  still opens with the old seal key, and the record of the removal states that
  limit. In a lane with a boot-time unseal, removal and transfer end with a
  Shamir rekey, so every copy wrapped under the old key stops working, and the
  five ADR-0009 shares are reissued from the new key.
- In the sandbox lane after the rotation, a retained device approves with the
  new recovery keys, and the reissued recovery package approves as well. In a
  lane with a boot-time unseal, a retained device unseals with the new key and
  the reissued share quorum unseals as well. Either way both are proven, the
  custody of the reissued material is verified again, and no secret value is
  recorded.
- An interrupted rotation is recoverable, using the behavior that WP1 recorded
  for cancel, resume and key validity. The command to use is checked against
  the OpenBao version, because the documentation marks `rekey` as deprecated
  in favor of `rotate-keys`.
- Synced passkeys are the sandbox-lane default (decision 18). Enrollment
  tells the admin that a takeover of the passkey sync account is a remote risk
  that the accepted local-root risk does not cover, and the ADR-0029
  amendment records it. The limits hold: encrypted copies on access-controlled
  storage, unseal and approval surfaces on the private network only, and an audit record of
  every use. A lane may require a device whose credential does not sync, such
  as a hardware security key.
- Every enrollment, removal and rotation is recorded with actor, role, request
  ID, reason, time and result.

**Closing evidence.** On a disposable environment: a fresh install that enrolls
a first device and a second device, with each approving on its own and the
recovery package approving as well. An enrollment approved by an enrolled
device, and one approved by the recovery package. A removal after which the
removed device's copy no longer approves. After the rotation, an approval by a
retained device and one by the reissued recovery package, with the custody
check. An interrupted rotation recovered. No record holds a secret value.

**Done when.**

- [ ] A fresh install enrolls two devices, and each one approves alone.
- [ ] Both enrollment paths work, and the owner is notified.
- [ ] A removed device cannot approve after the rotation, and a retained device
      and the reissued recovery package both do.
- [ ] The recovery package is reissued and re-verified.
- [ ] An interrupted rotation is recovered by a written procedure.
- [ ] The synced-passkey risk is shown at enrollment and recorded.
- [ ] The Status section is updated.

### WP7 portable-kit variant

**Goal.** Make the unseal page and its approvals work on an offline kit on
its own local network. In the sandbox lane the kit unseals itself at boot, and
the page serves approvals and restore. In a lane with a boot-time unseal, the
page also serves the unseal.

**Needs from the operator.** A kit or a kit-like environment, and the devices
from WP1.

**Dependencies.** WP1, WP5, WP6.

**Properties that must hold.**

- Push notifications are optional for the sandbox lane, including the kit's
  push server (decision 20). The push design below stays for a kit in a lane
  with a boot-time unseal.
- A kit in a lane with a boot-time unseal runs its own self-hosted
  push-notification server, paired with the admin's phone at install. The
  offline alert is required only on a phone platform where WP1 showed that it
  works. There the phone, on the kit's network, receives the alert and opens
  the unseal page on itself. No internet, laptop or Bluetooth is needed.
- The saved-page path is required on every platform, whatever WP1 showed for
  the alert. The unseal page stays the source of truth. The admin is told at
  pairing to save it to the device's home screen, so the saved page is the
  fallback where alerts are late or missing, and the way to reach an approval
  in the sandbox lane.
- The enrolled admin device trusts the kit's certificate in the way decision 2
  allows: a public certificate where the kit can renew one, otherwise a
  private authority limited by name to the kit with its key on the kit.
  Pairing installs the authority in one guided flow. No unrestricted
  authority is used without explicit approval. Removing the kit removes the
  authority from the device.
- A kit that stays off for months handles an expired certificate without
  locking the admin out.
- ADR-0050's constraint that seals secrets to local hardware conflicts with
  Tier 2. While the ADR is Proposed, the plan records the conflict for its
  promotion and changes nothing. If the ADR is accepted with that constraint,
  the Tier 2 kit cannot ship in that posture until the ADR is amended
  through the decision process.

**Closing evidence.** On a kit-like environment with no internet: in the
sandbox lane, a cold boot that unseals with no admin action and a root token
approved through the saved page on every platform. In a lane with a boot-time
unseal, a cold boot unsealed from an enrolled admin device through the saved
page on every platform, and through the local alert on each platform where
WP1 showed that it works. The certificate expiry case. The state of ADR-0050 on the date of the evidence,
and the conflict recorded if the ADR is still Proposed.

**Done when.**

- [ ] With no internet, the sandbox-lane kit unseals itself and approves a
      root token through the saved page. A kit in a lane with a boot-time
      unseal unseals from an enrolled admin device through the saved page,
      and through the alert where WP1 showed that it works.
- [ ] ADR-0050 is Proposed with the conflict recorded, or accepted without
      the conflicting constraint, or amended to remove it before the kit
      ships.
- [ ] The certificate path works and a removed kit is removed from the device.
- [ ] The expired-certificate case recovers.
- [ ] The Status section is updated.

### WP8 periodic check-in

**Goal.** Find a lost device or a departed admin early, before the next
privileged change or cold boot that needs them.

**Needs from the operator.** Nothing beyond review.

**Dependencies.** WP6 for the device list, WP9 for the records.

**Properties that must hold.** These follow decision 10.

- Each approval, unseal or check-in starts a period. The default is 30 days, and the
  length is configurable. The deadline is stored durably, so it survives
  service and node restarts. Time while the node is powered off counts toward
  the period, and a restart alone never extends it.
- A check-in is the same passkey ceremony as an unseal, run while OpenBao is
  unsealed. It proves that at least one enrolled credential and its wrapped
  copy still work. It reseals nothing.
- The console lists each device's last check-in and warns about any device not
  seen within the period, so a departed admin's device is visible and can be
  removed. In a lane with a boot-time unseal, any one device can still unseal.
  In the sandbox lane, OpenBao auto-unseals and a device approves root tokens
  and restores. Recovery keys alone cannot unseal. A lost seal key is
  recovered by a device that decrypts its stored seal key copy (decision 15
  and WP10), or from the recovery package.
- The console and the paired notification channel warn at 14, 7, 3 and 1 days
  by default, and the warning days are configurable. Each warning carries a
  one-tap check-in link.
- After expiry, running workloads keep running and privileged changes are
  refused until an admin checks in. The recovery package path always works
  after expiry: it can check in and enroll a replacement device. In a lane
  with a boot-time unseal, OpenBao seals at the next restart, as it does
  today. In the sandbox lane it auto-unseals at the restart, and on expiry
  privileged changes wait. An immediate seal is rejected.
- Check-ins, warnings and expiries are recorded like an unseal, under the same
  failure policy, and a check-in is never blocked by the spool. Root on the
  node can turn off the timer, and that is accepted in this lane.

**Closing evidence.** Tests that move the clock: warnings at each day,
expiry that keeps workloads running and refuses a privileged change, a
check-in that restarts the period, a restart that does not extend it, and the
recovery package path after expiry.

**Done when.**

- [ ] The period, the warnings and the expiry behave as described.
- [ ] The device list shows last check-ins and warns about an unseen device.
- [ ] The recovery package path works after expiry.
- [ ] The Status section is updated.

### WP10 restore with an enrolled admin device

**Goal.** Restore a sandbox-lane site after the loss of every copy of the seal
key on its nodes, with one confirmation from one enrolled admin device.

**Needs from the operator.** A disposable environment, one enrolled admin
device, and a second authenticator on another device for the QR path.

**Dependencies.** WP5, WP6, the WP4 rehearsal that provides the auto-unseal
seal on a disposable environment, and the portable Kubernetes auth config from
WP3 of the plan for
[#866](https://github.com/dmfdeploy/dmfdeploy/issues/866).

**Properties that must hold.** These follow decisions 15 and 19.

- The restore needs one confirmation from one enrolled admin device, on a
  screen that names the operation "restore" (decision 16). The inputs are the
  latest snapshot and the seal key. The device decrypts the seal key from the
  copy stored with the snapshot. When the authenticator is on another device,
  a QR code carries the confirmation to it.
- When no enrolled device is available, the direct copy of the seal key in the
  ADR-0009 recovery package completes the same restore.
- After the restore, OpenBao unseals with the restored seal key, serves the
  restored data, and the enrolled devices still approve with their recovery
  keys, with no new enrollment.
- The credential reconcilers run again after the restore, so a stored
  credential that expired while the environment was down is reissued. No
  secret value is recorded.
- A restore to a new cluster needs no root token write. Where the main ESO
  store uses Kubernetes auth, its login works from the restored snapshot. That
  holds because the stored config names the API by the in-cluster DNS name
  `https://kubernetes.default.svc`, reads the pod's local CA and token files
  and pins no CA. It holds even when the new cluster assigns the API Service a
  different IP than the source cluster did.

**Closing evidence.** A rehearsal on a disposable environment. Every copy of
the seal key is removed from the nodes. The restore then runs with one
confirmation, and a second run uses the recovery package copy with no enrolled
device. For each run: a before and after read of the same objects, the
auto-unseal on the restored OpenBao, an approval by a retained device, the
reconciler run, and, on a new cluster, a Kubernetes auth login. The
destination cluster's API Service IP differs from the source cluster's, and the
record states both IPs as differing without printing them. No record holds a
secret value.

**Done when.**

- [ ] A restore after the loss of every seal key copy on the nodes succeeds
      with one confirmation from one enrolled admin device, including the QR
      path.
- [ ] The same restore succeeds from the recovery package copy with no
      enrolled device.
- [ ] The data read matches before and after, and the retained devices still
      approve.
- [ ] The credential reconcilers run after the restore and reissue expired
      credentials.
- [ ] A restore to a new cluster whose API Service IP differs from the source
      cluster's logs in over Kubernetes auth without a root token write.
- [ ] The Status section is updated.

### WP4 seal transition and retiring the automation quorum

**Goal.** Move a site to the posture it declares, retire the single-machine
auto-unseal path before the posture is declared, and confirm the recovery
material works. In the sandbox lane, the posture is an auto-unseal seal with
recovery keys held on enrolled admin devices. In a lane that keeps a boot-time
unseal, it is the approved five-share recovery distribution.

**Needs from the operator.** The operator approves the live rollout for each
site and is present with the recovery material. The change is live, and a
mistake can lock the site out.

**Dependencies.** WP1 and WP2 done, and the packages that apply to the site
done with their evidence: WP5, WP6, WP8 and WP9, WP10 for a sandbox-lane
site, WP3 for a long-lived site, and WP7 for a kit. The WP4 rehearsal runs
before WP10, and the live change runs after it. This is the last package for
a site. It does not complete the plan.
[#868](https://github.com/dmfdeploy/dmfdeploy/issues/868): any dmf-init
Manage path that unseals with the automation file hands off to the operator
unseal, and a restored package does not bring the file back.

**Properties that must hold in the sandbox lane.**

- The sandbox's actual seal configuration today is one Shamir share, as
  ADR-0029's Enforcement section records. A rehearsed transition moves a site
  from that seal to an auto-unseal seal with recovery keys (decision 13). The
  rehearsal runs on a disposable environment first. It preserves the data. It
  reads the same objects before and after, and it shows that OpenBao
  unseals on restart with no admin action.
- The seal key is backed up as decision 15 says before the old unseal path is
  retired: a copy encrypted to each enrolled admin device and stored with the
  Raft snapshots, and a direct copy in the recovery package. The backup is
  verified by a decryption on a device and by a read of the package copy.
- The recovery keys are issued fresh as part of the transition. An old Shamir
  share, including every share in the ADR-0011 automation file, is not valid
  recovery material afterward. OpenBao carries the old unseal keys over as
  recovery keys when it migrates a seal, so this property closes a path that
  would otherwise mint a root token from the old file.
- One enrolled admin device meets the recovery threshold alone, and the
  rehearsal proves it with a change approved through the executor from WP5
  (decisions 14 and 16).
- Enrolled devices carry across the transition. Every retained device
  receives encrypted copies of the new recovery keys and the seal key as part
  of the same change, and the recovery path stays usable throughout.
- The ADR-0011 automation file, which holds enough shares to unseal without a
  person, is deleted from the workstation that holds it and from every backup
  of it, before the posture is declared. Declaring a posture while it exists
  would declare one that differs from the real one.
- The declared tier changes to Tier 3 with device-held recovery keys through
  the signed, audited path from WP5.
- Between deleting the automation copies and the first successful approval
  from an enrolled admin device, the site stays recoverable through the
  recovery package. A rehearsal makes the seal key unavailable on the node on
  a disposable environment after the copies are deleted, and recovers the
  site with the package's copy.

**Properties that must hold in a lane that keeps a boot-time unseal.**

- The lane's actual seal configuration moves from its current Shamir
  distribution to the approved five-share distribution before the old path is
  retired. The rehearsal runs on a disposable environment first. It preserves
  the data and verifies custody of every new share, and an unseal with the new
  shares succeeds. A site that already has five shares keeps them, and the
  preservation of those shares is tested instead of the transition.
- Enrolled devices carry across the transition. Every retained device
  receives a copy wrapped for the new key material as part of the same
  change, and the recovery path stays usable throughout. The rehearsal ends
  with a successful device unseal and a successful recovery-quorum unseal
  under the new configuration, before the live change runs.
- The ADR-0011 automation file is deleted from the workstation that holds it
  and from every backup of it, before Tier 2 is declared.
- The ADR-0009 five-share distribution is re-checked: each share is where the
  ADR says, readable, and enough to unseal on a disposable rehearsal.
- The declared tier changes through the signed, audited path from WP5.
- Between deleting the automation copies and the first successful device
  unseal, the site stays recoverable by the five-share recovery package with a
  manual unseal. A rehearsal makes the device unseal fail on a disposable
  environment after the copies are deleted, and recovers the site with the
  recovery shares.

**Closing evidence.** The transition rehearsal with its custody checks and a
before and after data read. The deletion confirmation without the file
contents. The recovery material check results, including the proof that an old
share no longer works as a recovery key in the sandbox lane. The failure
rehearsal and its recovery. The audit entry for the tier change, the
operator's approval for the site, and a successful approval or unseal from an
enrolled admin device on the site after the change. No record holds a secret
value.

**Done when.**

- [ ] The transition is rehearsed and then done on the site, with the data
      preserved. In the sandbox lane, OpenBao unseals on restart with no
      admin action and one enrolled admin device approves a root token. In a
      lane with a boot-time unseal, custody of the five shares is verified and
      both a device unseal and a recovery-quorum unseal succeed.
- [ ] In the sandbox lane, the seal key backup is verified before the old path
      is retired, and an old share no longer works as a recovery key.
- [ ] The automation file and its backups are gone, with a recorded check.
- [ ] The recovery material is re-checked.
- [ ] The failure between deletion and the first approval or unseal from an
      enrolled admin device is rehearsed and recovered without the automation
      quorum.
- [ ] The operator's approval for the site is recorded.
- [ ] The tier is declared through the signed path and the device approval or
      unseal works.

## Status

Update this table as the work moves. Each row links the evidence.

| WP | Status | Links |
|---|---|---|
| WP1 device confirmations | not started | |
| WP2 ADR-0029 amendments | not started | |
| WP3 HA OpenBao | not started | |
| WP4 seal transition and retiring the automation quorum | not started | |
| WP5 unseal page and session | not started | |
| WP6 enrollment and lifecycle | not started | |
| WP7 portable kit | not started | |
| WP8 periodic check-in | not started | |
| WP9 audit spool and delivery | not started | |
| WP10 restore with an enrolled admin device | not started | |

Allowed values: not started, in progress, done. Record the date the gate
opens on the WP1 row.

## Out of scope

- The catch-up after unseal (decision 9). It depends on
  [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866), which moves the
  main ESO store to Kubernetes auth, and on
  [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396). See the plan for
  #866. The later plan keeps three requirements: no secret consumer retries a
  credential that may have expired before it is renewed, consumers stay held
  until the catch-up succeeds, and a failed catch-up leaves a clear operator
  path. This plan designs no mechanism for them.
- Lanes with legal or regulatory obligations: dual control, a specific
  authentication level, strict write-once audit, and Tier 1.
- Stopping a root attacker who stays on a sealed node. That risk is accepted
  in this lane. In the sandbox lane the node also holds the seal key, so a
  person with the disk can read the data. The recovery keys stay off the
  node, so that person still cannot mint a root token.
- The optional private mesh layer. The RFC recommends it for machine-room and
  VPS sites, so it stays optional and unscheduled work that needs its own
  scheduling decision. Its pre-seal property is fixed: its keys live on the
  node and grant network reach only, it starts without OpenBao, and it
  never replaces the passkey. WP1 answers its naming question only if a site
  chooses it.
- Amending ADR-0050. That waits for its promotion.
