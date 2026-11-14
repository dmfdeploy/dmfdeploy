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
decisions of 2026-11-08 on the sandbox lane (decisions 12 to 20 below). Three
later records add decisions 21 to 30: the operator's decision of 2026-11-12 on
where the encrypted copies live, the decision of 2026-11-13 on
[#902](https://github.com/dmfdeploy/dmfdeploy/issues/902), and the
[decision record of 2026-11-14](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6879677199)
on #864. A later operator decision on 2026-11-14 adds decision 31, on saving
the recovery package and a snapshot. The RFC holds the evidence, the threat model and the reasoning. This
plan holds the work. The RFC calls the page that starts the unseal the unlock
page. This plan calls it the unseal page.

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
recovery keys kept off the node in the clear (decisions 13,
14 and 21). The plan never describes that lane as Tier 2, because the
declared posture must equal the actual one. The seal key stays on the node in
this lane. The recovery keys rest there only as copies encrypted for each
enrolled passkey, so material on the node cannot mint a root token. *Lean:*
off the node, the full recovery package of decision 31 also holds them. "Where
the key material lives" below lists every place.

*Changed on 2026-11-08.* Before this date the goal was ADR-0029 Tier 2
("Operator unseal") for the sandbox and open source lane, with a phone
confirming every cold-boot unseal and no unseal material at rest on the node.

*Changed on 2026-11-14.* The sandbox lane runs one OpenBao server (decision
23). The admin enrols at least two independent passkeys (decision 26). The
latest snapshot and the encrypted copy of the seal key are kept off the server
(decision 27). The audit record stays on the server and write-once delivery is
waived (decision 28). A portable sandbox kit is not a deliverable for now
(decision 30). dmf-init saves a full recovery package and a system snapshot,
for example on a USB key, and the admin downloads later snapshots by hand
(decision 31).

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
carries a note that says what changed on 2026-11-08. Decisions 21 to 30 came
later. Decisions 21 and 22 record the decisions of 2026-11-12 and 2026-11-13.
Decisions 23 to 30 record the eight decisions of 2026-11-14, in the order of
the decision record. Decision 31 records a later operator decision of the same
day. Each of them says which earlier decision it amends. The
earlier decision keeps its text, with a note that points forward. This plan
carries all thirty-one. A work package does not widen or narrow them. If a package
needs a different scope, stop and ask for a new decision.

1. HA OpenBao first for long-lived sites. A single replica is allowed in the
   sandbox lane through an ADR-0029 amendment with a visible warning. The
   signed, boot-checked tier and the audited downgrade stay. The ADR-0011
   automation quorum is retired before Tier 2 is declared, and the ADR-0009
   five-share distribution is re-checked. *Changed on 2026-11-08:* in the
   sandbox lane the automation quorum is retired when the auto-unseal seal
   replaces the Shamir seal (decision 13). The lane declares Tier 3
   (decision 12). The five-share re-check applies only to a site that keeps a
   Shamir seal. *Narrowed on 2026-11-14 (decision 23):* the sandbox lane runs
   one server, and the three-server Raft cluster is for long-lived sites.
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
   lane. *Changed on 2026-11-14 (decision 28):* in the sandbox lane the
   write-once delivery is waived, and the chained, numbered record stays on the
   server.
6. The device lifecycle properties, including the rekey and the reissue of
   the recovery shares. *Changed on 2026-11-08:* in the sandbox lane a
   removal or a transfer rotates the recovery keys and the seal key, and
   re-encrypts the retained devices' copies (decision 17).
7. The single unseal session design: the wrapped copy lives on the enrolled
   admin device, the QR code carries a single-use session URL, and the device
   unwraps the key. *Changed on 2026-11-08:* in the sandbox lane the same
   session design carries root token approval and restore, and not a boot
   unseal. The wrapped copy holds the recovery keys and the seal key
   (decisions 14 and 15). *Changed on 2026-11-12 (decision 21):* in the
   sandbox lane the server stores the copy, encrypted for each enrolled
   passkey, and the wrapped copy no longer lives on the device. *Changed on
   2026-11-14 (decision 29):* the unwrap happens on the phone only, and the QR
   flow from a laptop is not used for approvals.
8. The ADR-0029 Tier 2 row is amended to platform user verification,
   including a device PIN.
9. Catch-up after unseal is left to a later plan. It depends on
   [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866) and
   [#396](https://github.com/dmfdeploy/dmfdeploy/issues/396). ADR-0051
   (PR dmfdeploy/dmfdeploy#877, Proposed) removes the main ESO store from that
   catch-up, because Kubernetes auth holds no stored credential that can
   expire. The other AppRole consumers remain in it. *Corrected on
   2026-11-14:* ADR-0051 is Accepted, since 2026-11-08. The line above says
   "Proposed" because it predates that.
10. Periodic admin check-in: a 30-day period, warnings at 14, 7, 3 and 1 days,
    and on expiry privileged changes wait while workloads keep running. The
    recovery package path always works. *Confirmed on 2026-11-14 (decision
    30).*
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
    stays the last resort. *Changed on 2026-11-12 (decision 21):* the device
    does not store the recovery key material. It decrypts the server-stored
    copy for its passkey. *Changed on 2026-11-14 (decision 26):* the minimum
    is two independent passkeys. The earlier minimum counted devices.
15. Dated 2026-11-08. Recovery keys cannot unseal. They only authorize, as the
    OpenBao seal documentation says. The seal key therefore needs its own
    backup: a copy encrypted to each enrolled admin device and stored with
    the Raft snapshots, and a direct copy in the recovery package. In the
    sandbox lane that direct copy has one custodian, the admin, instead of
    ADR-0009's five shares at a threshold of three, which WP2 amends. *Changed
    on 2026-11-12 (decision 21):* the encrypted copies are stored on the
    server, one for each enrolled passkey. *Added on 2026-11-14 (decision
    25):* the plan must record what the recovery package holds for each of its
    jobs.
16. Dated 2026-11-08. The device screen names the operation: unseal, root
    token or restore. A generated root token is used only by a server-side
    executor, to mint a token scoped to the one named change, after it checks
    the change's pinned policy and the exact approved request. The root token
    is revoked at once. The generate-root, the mint, both revokes and the
    change are audited. *Added on 2026-11-14 (decision 24):* the executor logs
    in with its own narrow identity.
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
    [#866](https://github.com/dmfdeploy/dmfdeploy/issues/866). *Added on
    2026-11-14 (decision 27):* the latest snapshot and the encrypted copy of
    the seal key are kept off the server, and a full restore is rehearsed with
    the real pieces.
20. Dated 2026-11-08. With no boot-time unseal, every remaining device
    ceremony starts with the admin at a screen. Push notifications are
    therefore optional for the sandbox lane, including the portable kit's push
    server. The push design stays for lanes that need a boot-time unseal.
21. Dated 2026-11-12
    ([comment](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6825320344)).
    *Amends decision 7 for the sandbox lane.* The server stores one encrypted
    copy of the recovery keys and the seal key for each enrolled passkey. To
    use a copy, the admin's device asserts the passkey with user verification,
    derives a key from the PRF output and decrypts the copy on the device. The
    server never stores the key material in the clear. The copy of the seal
    key stored with the Raft snapshots covers a rebuild. A lane with a
    boot-time unseal needs its own decision, because the copy must be
    reachable while OpenBao is sealed.
22. Dated 2026-11-13
    ([#902 comment](https://github.com/dmfdeploy/dmfdeploy/issues/902#issuecomment-6847936906)).
    From OpenBao 2.6, generate-root uses only the authenticated
    `sys/generate-root-token/*` endpoints. Each platform caller logs in as
    `ops-admin` first. A narrow policy grants `ops-admin` those endpoints and
    nothing more. A quorum of unseal shares, or of recovery keys under an
    auto-unseal seal, is still required. The login token is revoked when the
    procedure ends. The legacy unauthenticated endpoints stay
    disabled. The case with no token moves to OpenBao's recovery mode, as a
    separate follow-up. ADR-0051 needs a clarification through an RFC. The
    playbooks and `dmf-env` follow this rule since dmf-infra#147 and
    dmf-env#40 merged on 2026-11-14. *Amended by decision 24 for the approval
    executor.*
23. Dated 2026-11-14 (record item 1). *Narrows decision 1.* The sandbox lane
    runs one OpenBao server. Three-server Raft clusters are for long-lived
    sites. The operator's test sandbox, grown to three servers for the HA
    rehearsal on 2026-11-08, is rebuilt at one server later. There is no
    in-place shrink. The three-server risks in
    [#874](https://github.com/dmfdeploy/dmfdeploy/issues/874) and
    [#875](https://github.com/dmfdeploy/dmfdeploy/issues/875) stay with
    long-lived sites.
24. Dated 2026-11-14 (record item 2). *Amends decision 22 and adds to decision
    16.* The approval executor gets its own narrow identity. It does not log
    in as `ops-admin`. The only policy of that identity allows the
    authenticated root token generation endpoints. The identity can start a
    root token request. It cannot finish one, because the recovery keys still
    come from the enrolled device. The `ops-admin` password is not copied into
    the per-passkey encrypted copies. Every login token is revoked on every
    exit path. ADR-0051 gets an RFC and an amendment for this and for
    decision 22.
25. Dated 2026-11-14 (record item 3). *Adds a requirement to decisions 14 and
    15.* The plan expects the recovery package to restore, approve, check in
    and enrol a device. For each of these jobs, the plan records what the
    package must hold. If any job needs the recovery keys, they go in the
    package. *Added on 2026-11-14 (decision 31):* the operator asked for a
    full recovery package. What "full" holds is still open.
26. Dated 2026-11-14 (record item 4). *Amends decision 14 and the 2026-11-08
    wording, which counted devices.* The admin enrols at least two independent
    passkeys. A passkey that syncs to several devices counts once.
27. Dated 2026-11-14 (record item 5). *Adds to decision 19.* The latest
    snapshot and the encrypted copy of the seal key are kept off the server. A
    full restore is rehearsed with the real pieces before restore is claimed
    to work. Restore from the recovery package stays as the alternative.
    *Added on 2026-11-14 (decision 31):* a snapshot saved with the recovery
    package, for example on a USB key, and later snapshots downloaded by
    hand. How that keeps the latest snapshot off the server is still open.
28. Dated 2026-11-14 (record item 6). *Amends decision 5 for the sandbox
    lane.* The chained, numbered audit record stays on the server, where it
    detects accidental corruption and gaps. Write-once delivery is waived for
    the sandbox lane, so losing the server loses the trail. New rule: no root
    token is created unless its audit record is written.
29. Dated 2026-11-14 (record item 7). *Relaxes the WP1 gate and amends decision
    7.* The device tests so far are enough to start building. A full test on
    the real approval page comes before rollout. The unwrap happens on the
    phone only. The QR cross-device flow from a laptop is not used for
    approvals, because the test showed that the laptop receives the passkey's
    PRF output.
30. Dated 2026-11-14 (record item 8). *Confirms decision 10.* The 30-day
    check-in stays as approved. A portable sandbox kit is not a deliverable for
    now. The boot-time auto-unseal method is decided separately.
31. Dated 2026-11-14, after the decision record, given by the operator in the
    orchestrator session. *Adds to decisions 25 and 27.* The operator's words:
    "create a snapshot during dmf-init procedure save a full recovery package
    and system snapshot on a usb key for example. later snapshots can be
    downloaded manually." The USB key is an example of the medium, so any
    removable medium meets the decision. The decision does not say which dmf-init procedure takes the
    snapshot, what "full" contains, or how later downloads keep decision 27's
    latest snapshot off the server. "Open items" carries a lean on each.

## Where the key material lives

This section lists, for the sandbox lane, every place that each piece of key
material rests. A cell marked *lean* follows a recommendation under "Open
items" and is not yet an operator decision. Every other cell follows the
decision it names.

"Off the server" means the snapshot downloads and the recovery package,
wherever the admin keeps them: a computer, a USB key or other media. "Passkey
device" means the phone or other device that holds the passkey and does the
unwrap. The columns name roles. One computer can be the passkey device and
also keep downloads. A row about the passkey device describes what
the plan puts there itself.

| Material | On the server | Off the server | On the passkey device |
|---|---|---|---|
| Seal key | In the clear, for the auto-unseal (decision 13) | One copy encrypted for each enrolled passkey, with the snapshots (decisions 15, 21 and 27). A direct copy in the recovery package (decision 15) | Decrypted in memory for a restore (decision 21). *Lean:* never stored |
| Recovery keys | Only as one copy encrypted for each enrolled passkey (decision 21) | *Lean:* the same encrypted copies in each snapshot download, and the keys themselves in the recovery package, which decision 31 asks to be full | Decrypted in memory for an approval (decision 21). *Lean:* never stored |
| Passkey, with its PRF secret | Never. *Lean:* a public key derived from it | Not in any download or package. A synced passkey is also held by its sync provider | In the authenticator |
| OpenBao data | The live data, from which snapshots are taken | The latest snapshot (decision 27) and the snapshot saved with the recovery package (decision 31) | Nothing from the plan. A download kept there is encrypted (*lean*) |
| Audit record | The chained, numbered record (decision 28) | *Lean:* a copy inside the encrypted snapshot download | Nothing from the plan. A download kept there is encrypted (*lean*) |
| Executor credentials | *Lean:* a projected ServiceAccount token and a short-lived OpenBao token, neither copied off the server | Never | Never |

*Lean:* only the recovery package holds the recovery keys without passkey
encryption, and every snapshot download is encrypted. Today's dmf-init
recovery package carries its backup encrypted with a passphrase that the admin
keeps apart from the package. *Lean:* the full package keeps that protection,
so whoever holds both the package and the passphrase holds everything. That is
the accepted single-admin risk of this lane.

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
  are encrypted to enrolled admin devices may rest there or in backups. Since
  2026-11-12 the copies are encrypted for each enrolled passkey (decision 21).
- The `ops-admin` password is not copied into the per-passkey encrypted copies
  (decision 24).
- In the sandbox lane, no root token is created unless its audit record is
  written (decision 28).
- Run cluster writes only through the sanctioned playbook path.
- Name no product as a design source. Cite standards and upstream
  documentation.
- Do not design for regulated lanes, and do not design the catch-up after
  unseal.

## Order and gate

WP1 is the gate. No code in WP5 to WP10 starts until the results of WP1 are
recorded on [#864](https://github.com/dmfdeploy/dmfdeploy/issues/864). Work
that needs no device result can run before that.

*Changed on 2026-11-14 (decision 29).* The operator accepted the device
results recorded so far as enough to start building. Those results cover the
iPhone, the Android phone and the iPad. The hardware security key with a PIN
has no result, and the Mac stability repeat has not run. Code in WP5 to WP10
may start. A full test on the real approval page comes before any rollout.
The rule in "What each WP1 result opens" still applies to each device type or
platform whose result is not recorded.

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
recovery package for storage. *Changed on 2026-11-12 (decision 21):* in the
sandbox lane the server stores the encrypted copy, so the device-storage
fallback does not apply there. It stays for a lane with a boot-time unseal.

### Site rollout and plan completion

These are two different events.

- **A site is ready to declare its posture** when WP1 and WP2 are done and the
  packages that apply to that site are done with their evidence. These are
  WP5, WP6, WP8 and WP9 for every site, WP3 for a long-lived site, WP7 for a
  kit, and WP10 for a sandbox-lane site. The posture is Tier 3 with recovery
  keys kept off the node in the clear in the sandbox lane
  (decision 21), and Tier 2 in a lane with a boot-time
  unseal. WP4 then runs for the site, with the operator's approval.
- **The plan is complete** when every package is closed. The completing PR
  archives the plan as WORKING-MODEL section 5 requires: it sets the
  frontmatter to `status: executed` with an `executed:` date, moves the plan
  to `docs/archive/plans/`, fixes the links to it, regenerates the plans
  index, and closes [#864](https://github.com/dmfdeploy/dmfdeploy/issues/864)
  with a qualified `Closes` reference. One site's rollout never closes the
  plan. *Changed on 2026-11-14 (decision 30):* only the portable sandbox kit
  is dropped for now, so WP7 serves no sandbox-lane site. WP7 stays for a kit
  in a lane with a boot-time unseal. What happens to WP7 is open (see "Open
  items"). Until the operator decides, plan completion still needs every
  package closed.

Each work package fits in one session. The "Needs from the operator" line
says when the operator must be present.

*Reading note, 2026-11-14.* Decisions 21 to 30 amend the packages below. Where
a package says that the wrapped copy lives on the enrolled admin device,
decision 21 replaces that for the sandbox lane: the server stores the copy,
encrypted for each enrolled passkey, and the device decrypts it after the
passkey assertion. Where a package says "two enrolled devices", decision
26 replaces that with two independent passkeys. A package that a decision
changes carries a "Changed on 2026-11-14" note, and the superseded wording
stays next to it.

## Work packages

### WP1 real-device confirmations

**Goal.** Replace the RFC's unconfirmed items with recorded results from real
devices and a disposable environment.

**Needs from the operator.** One device of each type that the operator will
enroll, with its software version: a phone of each platform the operator
uses, a laptop or tablet with a platform authenticator, and a hardware
security key. Also a disposable environment or kit to test against.

**Dependencies.** None. The RFC's Appendix B lists the items.

**Changed on 2026-11-14 (decision 29).** The results recorded in part 1 on
[#864](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6825130858)
are enough to start building WP5. The full session test below now runs on the
real approval page, and it comes before rollout. The QR item is settled for
approvals, as the property after it says.

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
- *Changed on 2026-11-14 (decision 29).* Approvals do not use the QR
  cross-device flow from a laptop. In part 1 the Mac received the same PRF
  output as the Android phone and decrypted the test text that the phone had
  encrypted. The test used no recovery key or seal key. The same flow would
  give a laptop the PRF output that decrypts the real copy. The unwrap
  happens on the phone only. The design for the approval page says how it
  keeps the cross-device flow out of approvals. The decision does not say.
- The wrapped copy survives the device's storage rules over the check-in
  period, or the result records the eviction behavior and what covers it.
  This applies to a lane that keeps the copy on the device, for now the
  boot-time lane. The sandbox lane keeps its copies on the server (decision
  21), so its durability is covered by the server-copy and restore tests in
  WP6 and WP10.
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
- [ ] The full session test has a recorded result on the real approval page
      (decision 29). It gates rollout. WP5 can start without it.
- [ ] The Status section below is updated, and the gate is open or stays shut.

### WP2 ADR-0029 amendments

**Goal.** Amend ADR-0029, and ADR-0009 for the sandbox lane, through the
RFC-to-ADR path so that the code in the later packages matches an accepted
decision.

**Needs from the operator.** Review of the draft and acceptance. The RFC
thread has already converged.

**Dependencies.** The approved decisions. No device results are needed.

**Properties that must hold.**

- The ADR-0029 amendments are exactly five, and each cites its decision:
  - Single replica allowed in the sandbox lane, with a visible warning
    (decision 1). *Changed on 2026-11-14 (decision 23):* the amendment says
    the sandbox lane runs one server and the three-server Raft cluster is for
    long-lived sites.
  - No per-boot token for Tier 2, which keeps the token for Tier 1
    (decision 4). The amendment states that removing the token weakens the
    original proof of infrastructure access.
  - The Tier 2 row says user verification by any method the platform offers,
    including a device PIN (decision 8).
  - The audit guardrail for the sandbox lane: records go to a local spool
    first and are delivered to the write-once target when reachable, a full
    spool never blocks an unseal, and a lost record is accepted (decision 5).
    *Changed on 2026-11-14 (decision 28):* in the sandbox lane the chained,
    numbered record stays on the server, write-once delivery is waived (losing
    the server loses the trail), and no root token is created unless its audit
    record is written.
  - The sandbox-lane posture as a named sub-variant of Tier 3, with
    recovery keys kept off the node in the clear (decisions 12, 13
    and 21). The amendment states these
    properties of the variant:
    - the auto-unseal seal;
    - recovery keys separate from the seal key, held on enrolled admin
      devices, where one device meets the threshold alone and at least two
      are enrolled (decision 14). *Changed on 2026-11-12 and 2026-11-14
      (decisions 21 and 26):* the copies are encrypted for each enrolled
      passkey and stored on the server, and the minimum is two independent
      passkeys;
    - the seal key backed up as decision 15 says;
    - the audit record of the unseal itself as a system action under
      ADR-0028, with each approval carrying the enrolled admin as actor;
    - what the recovery package holds for each of its jobs (decision 25).

    It states that the declared posture equals the actual one, so the lane is
    never described as Tier 2. It
    records the synced-passkey risk and its limits (decision 18). The ADR's
    Enforcement section says what checks the declared tier against the
    configured seal: the boot-time check from WP5, or "discipline only."
- One ADR-0009 amendment, for the sandbox lane only: the recovery package
  holds the seal key as one copy in the admin's custody, instead of five
  shares at a threshold of three. It cites decisions 14 and 15 and the
  accepted local-root risk. A lane with a boot-time unseal keeps ADR-0009 as
  it is. *Changed on 2026-11-14 (decision 25):* the package holds the
  recovery keys as well as the seal key if any of its jobs needs them. The
  package specification below decides, and this amendment follows it.
- The signed, boot-checked tier and the audited downgrade are unchanged, and
  the ADR still says so.
- The ADR keeps its **Rule:** line and its `## Enforcement` section, and the
  section names the mechanism each later package adds or says "discipline
  only."
- The ADR links the RFC thread. The decision index is current.
- ADR-0050's TPM sealing constraint conflicts with Tier 2 on a kit. This plan
  does not change that ADR while it is Proposed. The amendment waits for its
  promotion, and WP7 records the conflict.
- ADR-0051 is not part of this package. Its clarification goes through its own
  RFC and amendment: root token generation needs an authenticated caller, and
  the approval executor uses its own narrow identity (decisions 22 and 24).

**Recovery package specification (decision 25).** Before the ADR-0009
amendment is written, this plan records what the package must hold for each
job that the plan expects of it. If a job needs the recovery keys, they go in
the package. The table lists what the plan says today. The last column is the
requirement to fill in.

| Job | What the plan says today | What the package must hold |
|---|---|---|
| Restore | A direct copy of the seal key completes the restore with no enrolled device (decisions 15 and 19, WP10). | To specify. The seal key copy is the known item. |
| Approve | The package stays the last resort when no enrolled device is available (decision 14). A root token needs a quorum of recovery keys (decision 13). | To specify. |
| Check in | The package path always works, also after expiry, and can check in (decision 10, WP8). | To specify. |
| Enrol | When no enrolled device is available, the package approves an enrolment (WP6). | To specify. |

The plan does not say whether enrolment and check-in need a root token quorum
or only the decryption of the stored copies. The specification states the
material and the steps for each job. WP6, WP8 and WP10 follow it.

**Closing evidence.** The merged amendment, the index entry, and the
announcement thread that the RFC process requires.

**Done when.**

- [ ] The five ADR-0029 amendments and the ADR-0009 amendment are merged and
      accepted.
- [ ] The recovery package specification names the contents for restore,
      approve, check in and enrol, and the ADR-0009 amendment matches it.
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

**Changed on 2026-11-14 (decision 23).** Long-lived sites run the three-server
Raft cluster, and they set `openbao_replicas` in the site inventory. The
sandbox lane runs one server. The sandbox-lane variants below therefore apply
to a three-server rehearsal environment, such as the operator's test sandbox,
and not to a shipped sandbox. The risks in
[#874](https://github.com/dmfdeploy/dmfdeploy/issues/874) (consumers that
exec into a pinned pod, which can be sealed) and
[#875](https://github.com/dmfdeploy/dmfdeploy/issues/875) (scheduled reboots
that skip the rolling-restart guard) stay with long-lived sites. The operator's
test sandbox is rebuilt at one server later, because there is no in-place
shrink.

**Landed on 2026-11-08.** The Raft install, the rolling-restart guard and the
grow procedure from one server to three merged in
[dmf-infra#130](https://github.com/dmfdeploy/dmf-infra/pull/130). The
pull request records a rehearsal of the grow and restart paths on the test
sandbox, under a Shamir seal. The Status table says what remains open.

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
  warning that WP2 requires. On 2026-11-14 the role's defaults file still
  records that this warning is not built.

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
  *Superseded in the sandbox lane, only for where the copy lives (decision
  21):* the copy is not held on the device. The server stores it, encrypted
  for each passkey, and the phone decrypts it after the passkey assertion.
  *Strengthened on 2026-11-14 (decision 29):* the unwrap happens on the phone
  only, and the QR cross-device flow from a laptop is not used for approvals,
  because in that flow the laptop receives the PRF output. The rule that no
  other device sees key material stays. A tablet or a laptop would need an
  operator amendment to approve on itself, because the decision names the
  phone. The decision does not mention the session-URL QR code, in which the
  phone opens the session and the laptop only shows the code.
- The session accepts one submission, expires after a short time and cannot
  be replayed. Only a session that completed a passkey assertion for an
  enrolled credential, and that holds the wrapped copy, may submit. *In the
  sandbox lane (decision 21):* "holds the wrapped copy" means that the
  session received the server-stored ciphertext for that passkey. The plan
  does not yet say which session obtains the ciphertext or how the assertion
  gates its release. The design review of this package records both. The
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
  cannot mint a root token (decisions 13 and 14). *Changed on 2026-11-12
  (decision 21):* in the sandbox lane the device does not store the recovery
  keys. It decrypts the server-stored copy for its passkey, in memory, for
  each approval.
- A root token has unrestricted authority, so the plan does not rely on a
  revoke after the change. A server-side executor handles every approved root
  token (decision 16):
  - The executor logs in with its own narrow identity (decision 24). The only
    policy of that identity allows the authenticated root token generation
    endpoints. The identity can start a root token request. It cannot finish
    one, because the recovery keys come from the enrolled device. The executor
    does not log in as `ops-admin`, and the `ops-admin` password is not copied
    into the per-passkey encrypted copies. The executor revokes every login
    token on every exit path. This replaces the rule in decision 22 that every
    caller logs in as `ops-admin`. The plan does not yet say how the
    identity's credential is issued, held, rotated and revoked. The design
    review of this package records that before the executor is built.
  - The generated root token goes only to the executor. It never reaches the
    device, the page, a log or any caller.
  - The executor uses the root token for exactly one call: it mints an orphan
    token with the policy for the named change, with a short TTL and a use
    limit. Each approvable change has its own policy, installed beforehand by
    the installer, that allows only the path and capabilities that change
    needs, so the mint needs no policy write.
  - The policies are pinned. The repo holds each policy's text, and the
    executor holds the digest of each. Before it mints, the executor reads the
    live policy and refuses when its digest differs from the pinned one, so a
    policy changed after install cannot widen the scoped token.
  - The executor revokes the root token synchronously, before it performs the
    change. The change runs with the scoped token, which the executor also
    revokes when the change is done.
  - The interval before that revoke is abort-safe. Before the mint, the
    executor looks up the root token's accessor, which is not secret, and
    records it durably. On every start, and on a short timer, a standing
    revoker identity revokes every recorded accessor and then clears the
    record. That identity can only revoke tokens by accessor: it cannot
    create, read or use one. A crash after the record therefore leaves the
    root token revoked at the next start or timer tick.
  - One window stays open, and the plan accepts it for the sandbox lane: a
    crash after generate-root completes and before the accessor is recorded.
    The root token is then valid, but nobody holds it. OpenBao returns it
    encoded with a one-time pad that exists only in the executor's memory,
    so no one can decode it. WP5's design review decides whether to close
    this window, for example with a periodic scan that revokes unrecorded
    root tokens.
  - On any failure, the executor revokes both tokens before it returns.
  - The approval binds the exact request. The session carries the change's
    name, its pinned policy digest and a digest of the exact request the
    change sends, and the device screen shows the name and a short form of
    the request digest. The executor refuses any request whose digest or
    policy digest differs from what the device approved, before it mints.
  - The audit records the enrolled admin as actor for the generate-root, the
    mint, the root revoke, the change and the scoped revoke. No token value
    appears in a log, result or record.
  - The executor creates no root token unless its audit record is written
    (decision 28). When the record cannot be written, the approval fails and
    no root token exists.
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
- Drift tests: a pinned policy changed on the disposable environment, and a
  request changed after approval. Each is refused before the mint, and no
  root token is generated or used for it.
- Injected-failure tests: a crash after the accessor is recorded and before
  the mint, and a crash after the mint and before the root revoke. In each,
  the revoker revokes the root token by its recorded accessor at the next
  start, a later lookup of it fails, and the scoped token expires within its
  short TTL.
- Audit entries for the generate-root, the mint, the root revoke, the change
  and the scoped revoke, with no token value.
- A test in which the audit record cannot be written: the approval fails and no
  root token is created (decision 28).
- Tests of the executor's own identity (decision 24): used alone, it starts a
  root token request and cannot finish one. After a success, a refusal and a
  crash, none of its login tokens is still valid.
- Before rollout, a full test of the approval session on the real approval
  page, with the unwrap on the phone (decision 29).
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
      the scoped token refuses a second or unrelated mutation. A changed
      policy and a changed request are each refused before the mint. Both
      injected-failure tests pass, and the audit entries are complete.
- [ ] In a lane with a boot-time unseal, a cold boot is unsealed from an
      enrolled admin device on the disposable environment, and the
      no-material-at-rest scan, crash dumps included, passes.
- [ ] The executor uses its own narrow identity. Tests show that it cannot finish
      a root token request alone, that every login token is revoked on every
      exit path, and that an unwritable audit record creates no root token.
- [ ] Every negative test and the rate-limit test pass.
- [ ] A tampered or lower tier, or a tier that differs from the seal, is
      refused at boot, and an audited signed downgrade works.
- [ ] In a lane with a boot-time unseal, the online notification and link
      flows unseal end to end.
- [ ] Before rollout, the approval session passes a full test on the real
      approval page, with the unwrap on the phone.
- [ ] The Status section is updated.

### WP9 audit spool and delivery

**Goal.** Record every unseal-related action locally first, and deliver the
records when the write-once target is reachable.

**Needs from the operator.** Nothing beyond review. The device results from
WP1 are the gate.

**Dependencies.** WP1 recorded, WP2 merged. Built in parallel with WP5, which
writes to it.

**Changed on 2026-11-14 (decision 28).** In the sandbox lane the chained,
numbered record stays on the server, where it detects accidental corruption
and gaps. Write-once delivery is waived for that lane, so losing the server
loses the trail. Where a property below says "delivered", it applies to a
lane that keeps delivery. The sandbox lane keeps every other property,
including the required record contents and the failed-attempt record. It also
keeps the qualifications below. The chain does not prove that no one edited
the record on purpose. The sequence shows a gap only while the counter
survives. Some lost records may never be detectable. Only a lane that keeps delivery is
subject to the delivery and clearing properties and tests. The sandbox lane
does not roll out until the design of this package records a bounded local
retention and overflow strategy. That strategy keeps the rule that no root
token is created without its audit record, and it states what a gap or a
truncation loses.

**Properties that must hold.** These follow decision 5 and the RFC's audit
section. Decision 5 amends the ADR-0029 audit guardrail for the sandbox lane
only. Every other lane keeps the ADR-0029 rule that each submission reaches a
write-once target, unless a separately scoped decision changes it. The spool
and unseal rules below apply to the sandbox lane; a lane that keeps the
guardrail applies them only where they do not weaken it.

- Records go first to a local, bounded spool, before any network service is
  up. In a lane that keeps delivery, they are delivered to the write-once
  target when it is reachable, and the spool is cleared only after delivery.
  The sandbox lane waives delivery (decision 28), so the clearing rule has no
  trigger there and the retention strategy above replaces it.
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
- In the sandbox lane, when the spool cannot write, the unseal still
  proceeds, and the record of it can be lost (decision 5). Some lost records
  may never be detectable. A refusal would turn a full spool into an outage.
  Another lane follows this rule only after a decision scoped to that lane.
- In the sandbox lane, no root token is created unless its audit record is
  written (decision 28). This is a new rule, and it differs from the unseal
  rule above. A full or unavailable spool never blocks an unseal, but in the
  sandbox lane it stops the creation of a root token.
- The plan does not yet say how the on-server record stays bounded in the
  sandbox lane, because nothing there delivers records or clears them. The
  design of this package records it, and the sandbox lane waits for it.

**Closing evidence.** Tests for the record contents, the chain and the
sequence; in the sandbox lane, a full-spool unseal that proceeds; and, for a
lane that keeps delivery, a delivery after the target comes back. For the sandbox lane, which
waives delivery: tests that detect a
changed record and a gap on the server, and a test in which an unwritable
record creates no root token.

**Done when.**

- [ ] Records carry the fields above. In a lane that keeps delivery, they are
      delivered after an outage.
- [ ] In the sandbox lane, a full or unavailable spool never blocks an
      unseal, and the test shows the lost record and the visible gap where
      one is detectable.
- [ ] In the sandbox lane, the on-server chain and sequence detect a changed
      record and a gap, and an unwritable record creates no root token.
- [ ] In the sandbox lane, the design records a bounded local retention and
      overflow strategy, with what a gap or a truncation loses.
- [ ] The Status section is updated.

### WP6 enrollment, device lifecycle, rotation and recovery material

**Goal.** Enroll the admin's first device and a second device at install, let
the admin add, remove and transfer devices later, and keep removed devices
from approving anything.

**Needs from the operator.** A disposable environment and two enrolled admin
devices, with at least one of them a different device type from the other.
Since decision 26 the two must also hold independent passkeys.

**Dependencies.** WP5. WP1's rekey-interruption result.

**Properties that must hold.** These follow decisions 6, 14, 15, 17 and 18.
The key material is the recovery keys and the seal key in the sandbox lane,
and the unseal key material in a lane with a boot-time unseal.

- At install, the admin registers the first enrolled admin device and enrolls
  a second device. The minimum is two, and an install without both is not
  complete. Later enrollment happens only in the running console, behind its
  normal sign-in. The unseal page never enrolls. *Changed on 2026-11-14
  (decision 26):* the minimum is two independent passkeys. The earlier minimum
  counted devices. A passkey that syncs to several devices counts once, and an
  install with fewer than two is not complete. The design of this package says
  how enrollment applies the rule. The decision does not say whether two
  passkeys in one passkey sync account count as independent.
- One enrolled admin device meets the recovery threshold alone. Losing any one
  device leaves the other able to approve. Since decision 26, read "device" as
  "independent passkey" here.
- In the sandbox lane, every enrolled device holds its own independently
  encrypted copy of the recovery keys and of the seal key. The copy of the
  seal key is also stored with the Raft snapshots, and a direct copy is in the
  ADR-0009 recovery package (decision 15). In a lane with a boot-time unseal,
  every enrolled device holds its own independently wrapped copy of the
  unseal key material, and any one of them can unseal. *Superseded for the
  sandbox lane on 2026-11-12 (decision 21):* the server stores one encrypted
  copy for each enrolled passkey, and the device decrypts it after the
  passkey assertion. Two devices that share one synced passkey share one
  copy. The boot-time lane needs its own decision.
- An already enrolled device approves, decrypts the key material on that
  device and encrypts a copy for the new one. *Open since 2026-11-14:* with a
  key derived from the PRF output alone, only the new passkey can produce its
  own key, so the enrolled device cannot encrypt for it. "Open items" carries
  the question and a lean. When no enrolled device is
  available, the ADR-0009 recovery package approves. The current owner is
  notified when a device is added. *Added on 2026-11-14 (decision 25):* the
  recovery package's part in this job is in the package specification under
  WP2.
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
a first and a second independent passkey (decision 26), with each approving on
its own and the recovery package approving as well. An enrollment approved by
an enrolled device, and one approved by the recovery package. A removal after
which the removed device's copy no longer approves. After the rotation, an
approval by a retained device and one by the reissued recovery package, with the custody
check. An interrupted rotation recovered. No record holds a secret value.

**Done when.**

- [ ] A fresh install enrolls two independent passkeys (decision 26, which
      replaces "two devices"), and each one approves alone.
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

**Changed on 2026-11-14 (decision 30).** A portable sandbox kit is not a
deliverable for now, so this package has no site in the sandbox lane. Only
that kit is dropped. The package stays in the plan for a kit in a lane with a
boot-time unseal, and what happens to it is open (see "Open items").

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

**Confirmed on 2026-11-14 (decision 30).** The 30-day check-in stays as
approved. The recovery package's part in a check-in is in the package
specification under WP2 (decision 25).

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
device. If the QR path stays (see "Open items"), a second authenticator on
another device for it.

**Dependencies.** WP5, WP6, the WP4 rehearsal that provides the auto-unseal
seal on a disposable environment, and the portable Kubernetes auth config from
WP3 of the plan for
[#866](https://github.com/dmfdeploy/dmfdeploy/issues/866).

**Properties that must hold.** These follow decisions 15 and 19.

- The restore needs one confirmation from one enrolled admin device, on a
  screen that names the operation "restore" (decision 16). The inputs are the
  latest snapshot and the seal key. The device decrypts the seal key from the
  copy stored with the snapshot. When the authenticator is on another device,
  a QR code carries the confirmation to it. *Conditional (decision 29):* this
  QR path is not a requirement and is not authorized until the operator
  decides. Decision 29 excludes the QR cross-device flow from a laptop for
  approvals and does not name restore, and the laptop would receive the PRF
  output in this flow too (see "Open items").
- *Added on 2026-11-14 (decision 27).* The latest snapshot and the encrypted
  copy of the seal key are kept off the server, so the loss of the server
  does not take them. The decision says "off the server" and does not name the
  place or how the pieces get there. The design of this package records both.
  A full restore is rehearsed with the real pieces, taken from that place, before
  restore is claimed to work. Restore from the recovery package stays as the
  alternative, and its contents follow the package specification under WP2.
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
the seal key is removed from the nodes. The snapshot and the encrypted copy of
the seal key come from the off-server place, and the rehearsal reads nothing
from the lost nodes (decision 27). The restore then runs with one
confirmation, and a second run uses the recovery package copy with no enrolled
device. For each run: a before and after read of the same objects, the
auto-unseal on the restored OpenBao, an approval by a retained device, the
reconciler run, and, on a new cluster, a Kubernetes auth login. The
destination cluster's API Service IP differs from the source cluster's, and the
record states both IPs as differing without printing them. No record holds a
secret value.

**Done when.**

- [ ] A restore after the loss of every seal key copy on the nodes succeeds
      with one confirmation from one enrolled admin device. The QR path is
      conditional on an operator decision and is not required until then.
- [ ] The same restore succeeds from the recovery package copy with no
      enrolled device.
- [ ] The snapshot and the encrypted copy of the seal key are kept off the
      server, and the full restore ran with those real pieces.
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
recovery keys kept off the node in the clear. In a lane that keeps a boot-time
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

*Changed on 2026-11-14 (decision 25).* The recovery package checks in this
package use the contents that the package specification under WP2 records.

**Properties that must hold in the sandbox lane.**

*Changed on 2026-11-14 (decisions 21 and 31).* Before this date these
properties put an encrypted copy of the key material on each enrolled admin
device. The server now holds one encrypted copy for each enrolled passkey,
and no admin device stores a per-passkey copy. "Where the key material lives" lists
every place.

- The sandbox's actual seal configuration today is one Shamir share, as
  ADR-0029's Enforcement section records. A rehearsed transition moves a site
  from that seal to an auto-unseal seal with recovery keys (decision 13). The
  rehearsal runs on a disposable environment first. It preserves the data. It
  reads the same objects before and after, and it shows that OpenBao
  unseals on restart with no admin action.
- The seal key is backed up before the old unseal path is retired: one copy
  encrypted for each enrolled passkey, stored on the server and with the
  off-server snapshots, and a direct copy in the recovery package (decisions
  15, 21 and 27). Decision 31 says where the package and a snapshot are saved,
  with a USB key as the example; the medium stays open. The backup is verified by
  a decryption on an enrolled admin device and by a read of the package copy.
- The recovery keys are issued fresh as part of the transition. An old Shamir
  share, including every share in the ADR-0011 automation file, is not valid
  recovery material afterward. OpenBao carries the old unseal keys over as
  recovery keys when it migrates a seal, so this property closes a path that
  would otherwise mint a root token from the old file.
- One enrolled admin device meets the recovery threshold alone, and the
  rehearsal proves it with a change approved through the executor from WP5
  (decisions 14 and 16).
- Enrolled passkeys carry across the transition. As part of the same change,
  the server stores new encrypted copies of the new recovery keys and the seal
  key for every retained passkey, and replaces the copies made under the old
  key material. The recovery package is written again with the new keys. The
  recovery path stays usable throughout.
- The ADR-0011 automation file, which holds enough shares to unseal without a
  person, is deleted from the workstation that holds it and from every backup
  of it, before the posture is declared. Declaring a posture while it exists
  would declare one that differs from the real one.
- The declared tier changes to Tier 3 with recovery keys kept off the node in
  the clear, through the signed, audited path from WP5.
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
| WP1 device confirmations | in progress | [Part 1 results, recorded 2026-11-12](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6825130858). The gate opened for building on 2026-11-14 (decision 29). Rollout needs the full test on the real approval page. |
| WP2 ADR-0029 amendments | not started | |
| WP3 HA OpenBao | in progress | Raft install, guard and grow procedure merged in [dmf-infra#130](https://github.com/dmfdeploy/dmf-infra/pull/130) on 2026-11-08. Open: the single-server warning is not built, and [#12](https://github.com/dmfdeploy/dmfdeploy/issues/12) is open. |
| WP4 seal transition and retiring the automation quorum | not started | |
| WP5 unseal page and session | not started | |
| WP6 enrollment and lifecycle | not started | |
| WP7 portable kit | not started | The portable sandbox kit is dropped for now (decision 30). The package stays for a kit in a lane with a boot-time unseal. |
| WP8 periodic check-in | not started | |
| WP9 audit spool and delivery | not started | |
| WP10 restore with an enrolled admin device | not started | |

Allowed values: not started, in progress, done. Record the date the gate
opens on the WP1 row.

## Open items

These items are open after 2026-11-14. The decisions say nothing on each of
them, so each needs a decision or a design step before the package that
depends on it is built. Each item carries a lean: the orchestrator's
recommendation of 2026-11-14. A lean is not a decision. It becomes one only
when the operator accepts it, and then it moves to "Decisions".

- What the recovery package holds for restore, approve, check in and enrol
  (decision 25). Decision 31 asks for a full package. *Lean:* "full" means
  the recovery keys, the seal key, the OpenBao snapshot saved with it, and the
  environment backup that dmf-init already packages, and the private key that
  opens every snapshot download, all encrypted with the dmf-init passphrase. No root token and no passkey material. The snapshot is
  taken at the end of the install, after the seal transition, and dmf-init
  writes the package again whenever it changes the keys. WP2 records the
  list.
- What a snapshot download holds, and how manual downloads meet decision
  27, which keeps the latest snapshot off the server. *Lean:* the console
  builds one versioned bundle at a time. It holds a fresh OpenBao snapshot
  and the per-passkey encrypted copies of the seal key and the recovery keys
  that match it. It also holds a copy of the audit record, the identifier of
  the seal key that the snapshot needs, and a manifest with digests. The audit record is not
  encrypted on the server, so the whole bundle is encrypted and authenticated
  with public-key encryption, which needs no passkey assertion. The
  recipients are the enrolled passkeys, taken from the signed bindings in the
  item on encrypting for an absent passkey, and a recovery key pair whose private key is in the recovery package.
  The recovery package can then open every later bundle when no passkey is
  left, and a restore from the package with a real later bundle is rehearsed.
  The download needs the operator role and writes an audit line. The console shows the time of the last download and
  warns once the server holds changes that no download carries: a newer
  snapshot, an enrollment or a rotation. A warning cannot prove that the off-
  server copy is current, so decision 27 holds only as well as the admin
  keeps up. If that is not enough, decision 27 needs an amendment or an
  automatic off-server copy. A restore is rehearsed with a real downloaded
  bundle. The design of WP10 records it.
- What happens to the recovery package after a rotation. WP4 and WP6
  already require the package to be reissued and its custody checked as part
  of a rotation. *Lean:* keep that requirement. A removal or transfer is not
  complete until the new package is written and read back, and until then
  the console shows the rotation as unfinished. If the admin has no media at
  hand, the rotation waits at that step, and the old package still works
  until the new keys replace the old ones. Each package and bundle names the
  key version it holds, so an older one is recognized as such.
- Whether "system snapshot" in decision 31 covers more than OpenBao. *Lean:*
  this plan covers the OpenBao snapshot. Snapshots of the other platform
  state, such as the inventory and automation databases, belong to a separate
  issue.
- Where on the server the per-passkey copies live (decision 21). *Lean:*
  outside OpenBao, in storage that the unseal page's own service owns, and
  copied into every snapshot download. A restore must read the seal key copy
  before OpenBao runs, and the executor then needs no read access in OpenBao.
  The copies are encrypted, so this storage needs integrity and availability
  more than secrecy.
- How a copy is encrypted for a passkey that is not present, at enrollment
  (WP6) and after a rotation (decision 17). A key derived from the PRF output
  alone works only when that passkey is present. *Lean, a design to
  verify:* at enrollment, the device derives a key pair from the PRF output
  (RFC 9180 key derivation) and gives the server only the public key. The
  server or another device then encrypts to an enrolled passkey with hybrid
  public key encryption (RFC 9180). A WebAuthn signature does not cover a key
  derived from the PRF output, so the design must bind the two: at
  enrollment the passkey signs an assertion over a challenge that carries the
  public key's digest, and every encryption checks the recipient list against
  those signed bindings. Without that, a server could hand out its own public
  key for an absent passkey. The binding alone is not a complete defense.
  Unresolved design checks remain: the device must confirm that the challenge
  carries the digest of the key it derived itself, and the recipient list must
  be versioned and tied to the enrolled credentials, so that a removed
  passkey or an older list is refused. The design also names the PRF salt and its
  version, the key derivation labels, the cipher suite and the associated
  data, and tests each. At a server-side rotation the server sees the new
  recovery keys anyway, because OpenBao returns them there, so the binding
  matters most when a device encrypts.
- How the executor identity's credential is issued, held, rotated and revoked
  (decision 24). *Lean:* Kubernetes auth bound to the executor's
  ServiceAccount, as ADR-0051 does for the main secret store. The executor
  holds a projected ServiceAccount token that Kubernetes rotates, and each
  login gets a short-lived OpenBao token that is revoked on every exit path.
  No long-lived secret is stored. This path depends on OpenBao's Kubernetes
  auth working. When it does not, the executor cannot log in, and the
  recovery-mode follow-up of decision 22 stays the way back. The design review
  of WP5 records it.
- How the sandbox lane keeps its on-server audit record bounded when nothing
  delivers or clears it (decision 28). *Lean:* keep the record for a fixed
  period, trim whole segments, and keep the hash of the last trimmed entry so
  the chain stays checkable. Each snapshot download carries a copy, which
  gives the admin an off-server copy without a delivery service. The design
  of WP9 records it.
- Whether two passkeys in one passkey sync account count as independent, and
  how enrollment applies the rule (decision 26). *Lean:* they don't. One
  account takeover or one lost account takes both. The second passkey lives
  in a different sync account or on a hardware security key with a PIN.
  Enrollment asks where each passkey lives and records the admin's answer.
  The authenticator's reported model is a hint only: it does not prove which
  sync account holds a passkey, so independence rests on the admin's
  statement.
- Decision 29 names the phone. Approval on a tablet or a laptop that holds its
  own passkey would need an operator amendment, and the plan does not assume
  one. Whether the QR path in WP10 stays is open, because decision 29 names
  approvals and not restore. Whether the session-URL QR code stays for
  approvals is also open, because the decision does not mention it. *Lean:*
  the risk that decision 29 found is the cross-device flow, which hands the
  PRF output to the laptop. So the unwrap happens on the device that holds
  the passkey, and that device may be a tablet or a laptop with its own
  passkey. The cross-device QR flow is dropped for restore too. The
  session-URL QR code stays, because it only opens the page on the phone and
  carries no key material.
- Which session obtains the server-stored ciphertext in the sandbox lane, and
  how the passkey assertion gates its release (decision 21). *Lean:* the
  server returns the copy for one credential only after it verifies that
  credential's assertion, with user verification, over a challenge bound to
  the named operation and the session. The copy is useless without the PRF
  output, so this check is a second layer. The design review of WP5 records
  it.
- The seal type of the auto-unseal seal (decision 13), the method that decision
  30 leaves to a separate decision, and where the boot-time lane keeps its
  copies (decision 21). The plan does not say whether these are one decision.
  *Lean:* the Static Key seal. OpenBao's 2.7.x seal configuration lists it,
  reads the key from a file, and rotates from one key to the next with
  `previous_key`. OpenBao's seal concepts page says that generate-root takes
  recovery keys under an auto-unseal seal. That would answer both the seal
  type and the boot-time method for the sandbox lane. It stays a candidate
  until the WP4 rehearsal on the pinned 2.7.2 passes. That rehearsal tests key
  creation and file permissions, the migration from Shamir, the recovery-key
  rekey and a restart. It also tests a rotation interrupted at each step with
  the previous key kept, a snapshot restored with the matching key version,
  the limit of an old snapshot after a rotation, and a full restore. Where a boot-time lane keeps
  its copies waits until such a lane is scheduled.
- Which of the remaining WP1 results must pass before rollout, beyond the full
  test on the real approval page: that PRF output is refused without user
  verification, the hardware security key with a PIN, the Mac stability repeat,
  and the interrupted rekey under the chosen seal. *Lean:* the refusal
  without user verification and the interrupted rotation under the chosen
  seal must pass. The hardware key with a PIN must pass before a site uses
  one as its second passkey. The Mac stability repeat matters only if a Mac
  approves, so it waits for the item on decision 29.
- Who approves the removal of a device. The sources are silent. *Lean:* any
  other enrolled passkey, or the recovery package when no other passkey is
  available. A passkey cannot approve its own removal. The removal counts as
  done only after the rotation of decision 17. If one passkey remains, the
  console asks for a replacement, because one is below the minimum of
  decision 26.
- What happens to WP7. The decision drops only the portable sandbox kit for
  now. WP7 stays for a kit in a lane with a boot-time unseal, and the plan is
  complete only when every package is closed, unless the operator decides
  otherwise. *Lean:* move WP7 to its own issue with `platform-debt`, so the
  plan can complete without it.
- Whether the sandbox-lane acceptance tests must run on a one-server
  environment, which is the shape that decision 23 gives the sandbox lane.
  *Lean:* yes. Three-server tests belong to WP3 and long-lived sites.
- A step that moves the credentials other than the unseal shares out of the
  ADR-0011 automation file before WP4 deletes it. The
  [plan gap found on 2026-11-07](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6709653882)
  is not yet in WP4. *Lean:* add the step to WP4. It lists every other
  credential in the file and moves each to the environment bundle or the
  recovery package before the deletion.

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
  person with the disk can read the data. The node holds the recovery keys
  only as copies encrypted for the enrolled passkeys, so that person still
  cannot mint a root token.
- The optional private mesh layer. The RFC recommends it for machine-room and
  VPS sites, so it stays optional and unscheduled work that needs its own
  scheduling decision. Its pre-seal property is fixed: its keys live on the
  node and grant network reach only, it starts without OpenBao, and it
  never replaces the passkey. WP1 answers its naming question only if a site
  chooses it.
- Amending ADR-0050. That waits for its promotion.
- A portable sandbox kit (decision 30). WP7 stays in the plan for a kit in a
  lane with a boot-time unseal.
- Amending ADR-0051. That has its own RFC and amendment (decisions 22 and 24).
