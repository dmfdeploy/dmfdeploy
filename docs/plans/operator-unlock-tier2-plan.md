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
operator's decisions comment on it, dated 2026-11-07. The RFC holds the
evidence, the threat model and the reasoning. This plan holds the work. The
RFC calls the page that starts the unseal the unlock page. This plan calls
it the unseal page.

## Goal

One admin, who may not be technical, unseals OpenBao after any cold boot
without physical access to the node. The admin opens the unseal page and
confirms on a phone with the phone's own sign-in check. No unseal material
rests on the node. This implements ADR-0029 Tier 2 ("Operator unseal") for
the sandbox and open source lane.

The goal is the most security achievable without adding friction for admins.
Physical and local root access to the node is a known, accepted risk in this
lane. Lanes with legal or regulatory obligations, such as dual control, a
specific authentication level and strict write-once audit, are out of scope
and need their own changes later.

## Decisions

The operator approved all eleven decisions on Discussion #865 as recommended.
This plan carries them as written. A work package does not widen or narrow
them. If a package needs a different scope, stop and ask for a new decision.

1. HA OpenBao first for long-lived sites. A single replica is allowed in the
   sandbox lane through an ADR-0029 amendment with a visible warning. The
   signed, boot-checked tier and the audited downgrade stay. The ADR-0011
   automation quorum is retired before Tier 2 is declared, and the ADR-0009
   five-share distribution is re-checked.
2. A name-limited private certificate authority with its key on the kit, or a
   public certificate where the kit can renew one. No unrestricted private
   authority without explicit approval.
3. The unseal page is the source of truth. Offline alerts are tested on a
   real iPhone and a real Android phone before the plan commits to them.
4. Option (b): no per-boot token for Tier 2, through an ADR-0029 amendment.
5. Spool first, then delivery. A full spool never blocks an unseal, and a lost
   record is accepted. ADR-0029's audit guardrail is amended for the sandbox
   lane.
6. The device lifecycle properties, including the rekey and the reissue of
   the recovery shares.
7. The single unseal session design: the wrapped copy lives on the phone, the
   QR code carries a single-use session URL, and the phone unwraps the key.
8. The ADR-0029 Tier 2 row is amended to platform user verification,
   including a device PIN.
9. Catch-up after unseal is left to a later plan. It depends on
   [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866) and
   [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396).
10. Periodic admin check-in: a 30-day period, warnings at 14, 7, 3 and 1 days,
    and on expiry privileged changes wait while workloads keep running. The
    recovery package path always works.
11. Next step: a plan in `docs/plans/` with `tracking_issue: 864`. Its first
    work package runs the real-device confirmations from Appendix B of the
    RFC.

## Binding constraints

- Follow ADR-0029's guardrails as amended by WP2, ADR-0009 for the recovery
  package, and ADR-0028 for audit attribution.
- Do not print a root token, an unseal share, a passkey output, a session URL
  or a ServiceAccount token in a task result, log, test fixture, or issue or
  PR body. Record metadata only.
- No unseal material rests on the node: not the plaintext, and not the wrapped
  form. That covers disks, backups, swap, crash dumps and logs.
- Run cluster writes only through the sanctioned playbook path.
- Name no product as a design source. Cite standards and upstream
  documentation.
- Do not design for regulated lanes, and do not design the catch-up after
  unseal.

## Order and gate

WP1 is the gate. No code in WP5 to WP9 starts until the results of WP1 are
recorded on [#864](https://github.com/dmfdeploy/dmfdeploy/issues/864). Work
that needs no phone result can run before that.

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
| WP4 seal transition and retiring the automation quorum | WP1, WP2, and the site's applicable packages | nothing: it is the last package for a site |

WP5 and WP9 ship to an environment together, because the page writes its
records to the spool. WP4 comes last in time even though it is numbered
fourth: the quorum is retired only when the replacement works, and Tier 2 is
declared only after that.

### What each WP1 result opens

A result of confirmed, or confirmed with a limit, opens the work that depends
on it, and the limit goes into that work's properties. An essential property
that is unconfirmed or fails keeps the dependent work blocked until the
operator decides; only a confirmed result, or an explicitly accepted limit,
opens it. These are the essential properties: PRF output with user
verification on a platform, the end-to-end unseal session on a platform, and
the certificate path for a kit. A platform where one is unconfirmed or fails
stays out of WP5 to WP9 until the operator decides what happens to it. A failure of the
offline alert, or limited wrapped-copy storage, opens the work with its
fallback: the saved page for the alert, and the second device and the
recovery package for storage.

### Site rollout and plan completion

These are two different events.

- **A site is ready to declare Tier 2** when WP1 and WP2 are done and the
  packages that apply to that site are done with their evidence: WP5, WP6,
  WP8 and WP9 for every site, WP3 for a long-lived site, and WP7 for a kit.
  WP4 then runs for the site, with the operator's approval.
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

**Needs from the operator.** An iPhone and an Android phone, with their
operating system versions, and a disposable environment or kit to test
against.

**Dependencies.** None. The RFC's Appendix B lists the items.

**Properties that must hold.** Each item gets one recorded result: confirmed,
unconfirmed, or confirmed with a limit, with the device and software
version. No result is inferred from a vendor page.

- PRF output is available on each phone platform for a passkey enrolled at the
  unseal page's host name, and it is stable across two authentications.
- The PRF output is returned only after user verification, and a device PIN
  works where the platform offers one.
- The single unseal session works end to end on each platform: QR code scan, the
  session page opening on the phone, the passkey assertion, local unwrap, and
  the submission.
- The wrapped copy survives the phone's storage rules over the check-in
  period, or the result records the eviction behavior and what covers it.
- An offline alert from a notification server on a local network reaches each
  phone platform in a time the admin can live with, or the result says it
  does not. The saved page on the home screen is tested as the fallback.
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

- The amendments are exactly four, and each cites its decision:
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

- [ ] The four amendments are merged and accepted.
- [ ] The announcement thread is posted.
- [ ] The Status section is updated.

### WP3 HA OpenBao with Raft for long-lived sites

**Goal.** Run OpenBao as a Raft cluster on long-lived sites, so a single-node
restart keeps OpenBao serving.

**Needs from the operator.** A disposable environment to rehearse on, and an
approval before any installed environment migrates. The migration is a live
change.

**Dependencies.** [#12](https://github.com/dmfdeploy/dmfdeploy/issues/12). No
phone result is needed, so this runs in parallel with WP1 and WP2.

**Properties that must hold.**

- A new install of a long-lived site creates a Raft cluster of OpenBao nodes
  with Shamir seal.
- HA keeps OpenBao serving while one node restarts. It does not remove the
  unseal. Each restarted node is sealed again and needs the threshold of
  shares, and it is brought back before the next node restarts. A rolling
  upgrade is a sequence of restarts, each followed by an unseal.
- The upgrade and drain procedures say so, and they refuse to restart the next
  node while a restarted node is still sealed.
- A migration from a single replica keeps the existing data and the ADR-0009
  shares valid where an environment already has them, and a rehearsal on a
  disposable environment passes first. The rehearsal reads the same data
  before and after, and unseals with the recovery shares. No secret value is
  recorded. The move from a one-share sandbox to five shares belongs to WP4.
- Single-replica installs stay supported in the sandbox lane, with the visible
  warning that WP2 requires.

**Closing evidence.** A rehearsal on a disposable environment: the cluster
state after a single-node restart, the time to serve, the sealed state of the
restarted node, the rolling-restart refusal, a before and after data read of
the same objects, and a recovery-share unseal after the migration. Records
carry no secret values.

**Done when.**

- [ ] A new long-lived install runs the Raft cluster.
- [ ] A restart of one node leaves OpenBao serving, and the rolling-restart
      guard works.
- [ ] The migration from a single replica is rehearsed, with the before and
      after data read and the recovery-share unseal. An installed environment
      moves only after a separate approval.
- [ ] #12's HA item is closed or re-scoped, and its other items are untouched.
- [ ] The Status section is updated.

### WP5 unseal page and unseal session

**Goal.** Build the pre-start page and the single-use session that lets a
phone unseal OpenBao.

**Needs from the operator.** A disposable environment, and the real devices
from WP1 for the end-to-end check.

**Dependencies.** WP1 recorded. WP2 merged. WP9 in parallel.

**Properties that must hold.**

- The page starts before every other service and needs nothing from OpenBao,
  the console or External Secrets Operator. It is reachable only on the
  private network.
- The phone runs its own passkey assertion, unwraps its own wrapped copy
  locally and submits to the session. No other device sees key material. The
  laptop in the QR flow only shows the QR code.
- The session is bound to the cold boot that created it, expires after a short
  time, accepts one submission and cannot be replayed. Only a session that
  completed a passkey assertion for an enrolled credential, and that holds the
  wrapped copy, may submit. The session URL alone unseals nothing.
- No unseal material rests on the node. Material exists on the node only in
  memory, for the length of one unseal. That covers disks, backups, swap,
  crash dumps and logs.
- The page never logs the passkey output, the unwrapped material or a session
  URL. Every submission is rate limited.
- The declared tier is bound in git-tracked config, checked cryptographically
  at boot, and lowered only through a signed, audited change, as ADR-0029
  requires.
- The credential is bound to the page's host name as a relying party ID. The
  page asks for user verification and accepts the platform's methods.
- The unseal page itself needs a stable host name, and a site whose name
  changes enrolls again.
- On an online site, a sealed node notifies the admin, and the notification
  carries a link that opens the unseal session on the phone. This covers the
  online flow with a laptop and QR code and the flow with only the phone.

**Closing evidence.** On a disposable environment, these results:

- A cold boot unsealed by one admin with a phone and without access to the
  node, started from the sealed notification and its link, on the online flow
  with a laptop and QR code and on the flow with only the phone.
- A scan of disks, backups, swap, crash dumps and logs that finds no unseal
  material.
- Negative tests that each fail to unseal: a replayed session, an expired
  session, a wrong credential, a session from another boot, the session URL
  alone, a session with no wrapped copy, a session with missing or failed user
  verification.
- A rate-limit test that shows submissions refused after the limit.
- A boot with a tampered or lower declared tier, refused at boot. A downgrade
  succeeds only through the signed change, and the audit records it.

**Done when.**

- [ ] A cold boot is unsealed from a phone on the disposable environment.
- [ ] The no-material-at-rest scan, crash dumps included, passes.
- [ ] Every negative test and the rate-limit test pass.
- [ ] A tampered or lower tier is refused at boot, and an audited signed
      downgrade works.
- [ ] The online notification and phone-link flows unseal end to end.
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
  the user-verification result. Device details that the phone reports about
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

### WP6 enrollment, device lifecycle, rekey and recovery-share reissue

**Goal.** Enroll the admin's first phone and a backup device at install, let
the admin add, remove and transfer devices later, and keep removed devices
from unsealing.

**Needs from the operator.** A disposable environment and two phones.

**Dependencies.** WP5. WP1's rekey-interruption result.

**Properties that must hold.** These follow decision 6.

- At install, the admin registers the first phone and enrolls a second device
  as the backup. An install without both is not complete. Later enrollment
  happens only in the running console, behind its normal sign-in. The unseal
  page never enrolls.
- An already enrolled device approves, unwraps the key material on that device
  and wraps a copy for the new one. When no enrolled device is available, the
  ADR-0009 recovery package approves.
- Every enrolled device holds its own independently wrapped copy, and any one
  of them can unseal. The current owner is notified when a device is added.
- Removal and transfer end with a rekey, so every copy wrapped under the old
  key stops working. The new key is wrapped only for the retained devices.
- After a rekey, the five ADR-0009 disaster-recovery shares are reissued from
  the new key and their custody is verified again.
- After a rekey, a retained device unseals with the new key, and the newly
  issued recovery quorum unseals as well. Both are proven, and no secret
  value is recorded.
- An interrupted rekey is recoverable, using the behavior that WP1 recorded
  for cancel, resume and key validity. The rekey command to use is checked
  against the OpenBao version, because the documentation marks `rekey` as
  deprecated in favor of `rotate-keys`.
- Every enrollment, removal and rekey is recorded with actor, role, request
  ID, reason, time and result.

**Closing evidence.** On a disposable environment: a fresh install that enrolls
a first phone and a backup device, with each unsealing on its own and the
recovery package unsealing as well. An enrollment approved by an enrolled
device, and one approved by the recovery package. A removal after which the
removed device's copy no longer unseals. After the rekey, an unseal by a
retained device and an unseal by the new recovery quorum, with the custody
check of the reissued shares. An interrupted rekey recovered. No record holds a
secret value.

**Done when.**

- [ ] A fresh install enrolls a first phone and a backup device, and each
      one unseals.
- [ ] Both enrollment paths work, and the owner is notified.
- [ ] A removed device cannot unseal after the rekey, and a retained device
      and the new recovery quorum both do.
- [ ] The recovery shares are reissued and re-verified.
- [ ] An interrupted rekey is recovered by a written procedure.
- [ ] The Status section is updated.

### WP7 portable-kit variant

**Goal.** Make the unseal work on an offline kit on its own local network.

**Needs from the operator.** A kit or a kit-like environment, and the phones
from WP1.

**Dependencies.** WP1, WP5, WP6.

**Properties that must hold.**

- The kit runs its own self-hosted push-notification server, paired with the
  admin's phone at install. The offline alert is required only on a phone
  platform where WP1 showed that it works. There the phone, on the kit's
  network, receives the alert and opens the unseal page on itself. No
  internet, laptop or Bluetooth is needed.
- The saved-page path is required on every platform, whatever WP1 showed for
  the alert. The unseal page stays the source of truth. The admin is told at
  pairing to save it to the phone's home screen, so the saved page is the
  fallback where alerts are late or missing.
- The phone trusts the kit's certificate in the way decision 2 allows: a
  public certificate where the kit can renew one, otherwise a private
  authority limited by name to the kit with its key on the kit. Pairing
  installs the authority in one guided flow. No unrestricted authority is
  used without explicit approval. Removing the kit removes the authority from
  the phone.
- A kit that stays off for months handles an expired certificate without
  locking the admin out.
- ADR-0050's constraint that seals secrets to local hardware conflicts with
  Tier 2. While the ADR is Proposed, the plan records the conflict for its
  promotion and changes nothing. If the ADR is accepted with that constraint,
  the Tier 2 kit cannot ship in that posture until the ADR is amended
  through the decision process.

**Closing evidence.** On a kit-like environment with no internet: a cold boot
unsealed from a phone through the saved page on every platform, and through
the local alert on each platform where WP1 showed that it works. The
certificate expiry case. The state of ADR-0050 on the date of the evidence,
and the conflict recorded if the ADR is still Proposed.

**Done when.**

- [ ] The kit unseals from a phone with no internet through the saved page,
      and through the alert where WP1 showed that it works.
- [ ] ADR-0050 is Proposed with the conflict recorded, or accepted without
      the conflicting constraint, or amended to remove it before the kit
      ships.
- [ ] The certificate path works and a removed kit is removed from the phone.
- [ ] The expired-certificate case recovers.
- [ ] The Status section is updated.

### WP8 periodic check-in

**Goal.** Find a lost phone or a departed admin early, before the next cold
boot.

**Needs from the operator.** Nothing beyond review.

**Dependencies.** WP6 for the device list, WP9 for the records.

**Properties that must hold.** These follow decision 10.

- Each unseal or check-in starts a period. The default is 30 days, and the
  length is configurable. The deadline is stored durably, so it survives
  service and node restarts. Time while the node is powered off counts toward
  the period, and a restart alone never extends it.
- A check-in is the same passkey ceremony as an unseal, run while OpenBao is
  unsealed. It proves that at least one enrolled credential and its wrapped
  copy still work. It reseals nothing.
- The console lists each device's last check-in and warns about any device not
  seen within the period, so a departed admin's device is visible and can be
  removed. Any one device can still unseal.
- The console and the paired notification channel warn at 14, 7, 3 and 1 days
  by default, and the warning days are configurable. Each warning carries a
  one-tap check-in link.
- After expiry, running workloads keep running and privileged changes are
  refused until an admin checks in. The recovery package path always works
  after expiry: it can check in and enroll a replacement device. OpenBao
  seals at the next restart, as it does today. An immediate seal is rejected.
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

### WP4 seal transition and retiring the automation quorum

**Goal.** Move a site to the approved five-share recovery distribution,
retire the single-machine auto-unseal path before Tier 2 is declared, and
confirm the recovery shares work.

**Needs from the operator.** The operator approves the live rollout for each
site and is present with the unseal shares. The change is live, and a mistake
can lock the site out.

**Dependencies.** WP1 and WP2 done, and the packages that apply to the site
done with their evidence: WP5, WP6, WP8 and WP9, WP3 for a long-lived site,
and WP7 for a kit. This is the last package for a site. It does not complete
the plan.

**Properties that must hold.**

- The sandbox's actual seal configuration is one Shamir share, as ADR-0029's
  Enforcement section records. A rehearsed transition moves a site from that
  configuration to the approved five-share distribution before the old path
  is retired. The rehearsal runs on a disposable environment first. It
  preserves the data and verifies custody of every new share, and an unseal
  with the new shares succeeds. A site that already has five shares keeps
  them, and the preservation of those shares is tested instead of the
  transition.
- Enrolled devices carry across the transition. Every retained device
  receives a copy wrapped for the new key material as part of the same
  change, and the recovery path stays usable throughout. The rehearsal ends
  with a successful phone unseal and a successful recovery-quorum unseal under
  the new configuration, before the live change runs.
- The ADR-0011 automation file, which holds enough shares to unseal without a
  person, is deleted from the workstation that holds it and from every backup
  of it, before Tier 2 is declared. Declaring Tier 2 while it exists would
  declare a posture that differs from the real one.
- The ADR-0009 five-share distribution is re-checked: each share is where the
  ADR says, readable, and enough to unseal on a disposable rehearsal.
- The declared tier changes through the signed, audited path from WP5.
- Between deleting the automation copies and the first successful phone
  unseal, the site stays recoverable by the five-share recovery package with a
  manual unseal. No automation quorum is kept for that interval. A rehearsal
  makes the phone unseal fail on a disposable environment after the copies
  are deleted, and recovers the site with the recovery shares.

**Closing evidence.** The transition rehearsal with its custody checks and a
before and after data read. The deletion confirmation without the file
contents. The share check results. The failure rehearsal and its recovery.
The audit entry for the tier change, the operator's approval for the site,
and a successful phone unseal on the site after the change. No record holds a
secret value.

**Done when.**

- [ ] The transition to five shares, or the preservation of existing five
      shares, is rehearsed and then done on the site, with custody verified
      and the data preserved. Retained devices hold valid copies, and a phone
      unseal and a recovery-quorum unseal both succeed in the rehearsal.
- [ ] The automation file and its backups are gone, with a recorded check.
- [ ] The five shares are re-checked.
- [ ] The failure between deletion and the first phone unseal is rehearsed
      and recovered without the automation quorum.
- [ ] The operator's approval for the site is recorded.
- [ ] The tier is declared through the signed path and the phone unseal
      works.

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
  in this lane.
- The optional private mesh layer. The RFC recommends it for machine-room and
  VPS sites, so it stays optional and unscheduled work that needs its own
  scheduling decision. Its pre-seal property is fixed: its keys live on the
  node and grant network reach only, it starts without OpenBao, and it
  never replaces the passkey. WP1 answers its naming question only if a site
  chooses it.
- Amending ADR-0050. That waits for its promotion.
