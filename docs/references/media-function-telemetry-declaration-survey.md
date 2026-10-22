---
date: 2026-10-22
---

# Media function telemetry declaration: a survey of open specifications

**What this is:** a survey of how open specifications and open-source
projects let a media function declare what it exposes for monitoring, with
types and units, and how a collector finds and reads it. The scope is
telemetry only. A companion note covers
[configuration control](media-function-configuration-control-survey.md).

**Status in dmfdeploy:** reference input only. This is a **Record** doc. It
decides nothing and schedules nothing. The RFC tracked in
[dmfdeploy/dmfdeploy#685](https://github.com/dmfdeploy/dmfdeploy/issues/685)
builds on it, together with the descriptor work in
[#634](https://github.com/dmfdeploy/dmfdeploy/issues/634).

**How to read it:** the project accessed every web source on 2026-10-22. Five
slices of research ran in parallel (JT-DMF and EBU, AMWA, broadcast transport,
cloud native, open industry initiatives). The project then spot-checked the
load-bearing AMWA claims directly: the BCP-008-01 release date, IN-003 fields,
units in MS-05-02, and the IN-004 protocol list.

Conventions:

- **Fact** means a source was read, and the text cites it.
- **(J)** marks the project's judgment.
- **(U)** marks something the project could not verify. Section 11 collects
  them.
- **(vendor)** marks a vendor product or a vendor-controlled project.

For each item, four questions apply: (1) does it declare what is monitorable,
with types and units; (2) how does a collector discover it; (3) what is the
collection mode (pull, push, subscribe); (4) how does it map to alerts or to
deltas between intended and observed state.

## 0. Summary

1. No standard, broadcast or cloud native, lets a package declare the metrics
   it exposes with names, types and units in a machine-checkable manifest. A
   `telemetry` block in `dmf-function.yaml` fills a real gap and duplicates
   nothing.
2. JT-DMF has published nothing on monitoring. The EBU DMF white paper v2.0
   states the need ("Media Functions support real-time monitoring through open
   APIs") and names no mechanism. EBU Tech 3371 v3 is the most concrete EBU
   text: alarms by SNMPv3, telemetry by OpenTelemetry, OpenConfig or MQTT, and
   logs by RFC 5424 syslog.
3. AMWA has one released monitoring model: BCP-008-01 and BCP-008-02 (v1.0.0,
   2025-08-26) on IS-12 and MS-05-02. It is a typed traffic-light model for
   NMOS senders and receivers. It is subscribe-first, and it has no unit
   field. The AMWA DMF increments (IN-001, IN-003, IN-004) leave monitoring as
   TBD. IN-004 names IS-12, OpenTelemetry and SMPTE ST 2138 (Catena) as
   candidate protocols.
4. The best precedents for the shape of the declaration come from outside
   broadcast. ETSI NFV `monitoringParameter` and VNF indicators, and the ONAP
   VES event registration YAML, both pair "declare in the package" with
   "collector reads the declaration". The best tool for the vocabulary and the
   check is the OpenTelemetry Weaver registry (metric name, instrument, unit,
   stability; `registry check` and `registry live-check`).
5. (J) Recommendation: a `telemetry` block that references existing standards
   and defines few fields of its own. It should declare health probes, metric
   endpoints and a Weaver-format metric registry, NMOS monitors (BCP-008
   class IDs), IS-07 event types where used, log format, and alert rules as
   plain Prometheus rule files. It becomes the source from which the ADR-0038
   `monitoring:` lanes are derived. The conformance tool checks the static
   parts on every package, and checks the declared metrics against a real
   scrape of a rendered fixture at certification tier. Three delta classes
   feed the closed loop: contract deltas, presence deltas and media-health
   deltas.

## 1. JT-DMF (Joint Task Force on Dynamic Media Facilities)

### Facts

- JT-DMF is a joint initiative of the EBU and AMWA, announced on 2025-09-13.
  Home: <https://www.amwa.tv/jtdmf>. EBU side: <https://tech.ebu.ch/groups/dmf>.
  Announcements:
  <https://www.amwa.tv/post/amwa-ebu-jt-dmf-dynamic-media-facility-task-force>
  and
  <https://tech.ebu.ch/news/2025/09/ebu-and-amwa-form-joint-task-force-on-dynamic-media-facilities-for-transition-to-software-based-media-production>.
  No SMPTE or VSF ownership role appears in any source read.
- The EBU group page lists two co-chairs, one from each of two public
  broadcasters, and named contacts at EBU and AMWA.
- Four tracks were set at the Geneva kick-off on 2025-11-27 and 2025-11-28:
  end-to-end synchronisation, compute resource management ("multi-vendor
  hosting of media functions on shared compute nodes"), MXL flow discovery and
  connection, and business-level activity
  (<https://tech.ebu.ch/news/2025/12/not-just-about-technology-jt-dmf-kicks-off-work-to-drive-dynamic-media-facilities-from-concept-to-production>).
- Later events: a New York meeting on 2026-03-10 and 2026-03-11, where the
  next step was "finalizing the activity group charters"
  (<https://tech.ebu.ch/news/2026/dynamic-media-facilities-project-heads-for-next-milestone-with-jt-dmf-meeting-in-new-york>);
  a Geneva meeting on 2026-06-08 (the agenda is an image that could not be
  read); and a planned DMF-MXL demonstration at IBC 2026.
- The compute resource management track produces the AMWA increments IN-001
  to IN-006 (see section 2.6). The earlier IN-003 material lives in
  `AMWA-TV/jt-dmf-crm`.
- Published outputs: the DMF Reference Architecture white paper (v1 2024,
  v2.0 2026-04-15) and the MXL SDK (Apache-2.0,
  <https://github.com/dmf-mxl/mxl>).

### Not found

- No JT-DMF charter, requirement, draft or presentation on monitoring,
  telemetry or observability. The member workspace needs a login.
- No IBC, NAB, NTS or SMPTE talk on DMF monitoring. The search tool is
  US-only and covers video and LinkedIn titles poorly.
- No roadmap that says IN-003 will gain monitoring fields.

### Judgment

(J) Monitoring would most plausibly land in the compute resource management
track (IN-004 already has a TBD monitoring section). Today dmfdeploy has no
JT-DMF telemetry requirement to conform to. That makes this a good moment to
bring an implementation-backed proposal to the track. The project reviews any
external text before it sends it.

## 2. AMWA

All facts in this section come from the AMWA-TV repositories at their default
branches, read on 2026-10-22. In October 2026 AMWA moved its rendered docs,
and some `specs.amwa.tv` pages now return a redirect stub. Pin to GitHub tags
in any ADR.

### 2.1 BCP-008-01 and BCP-008-02 (receiver and sender status monitoring)

- **What:** "NMOS Receiver Status Monitoring" and "NMOS Sender Status
  Monitoring". Open (CC BY-ND 4.0). Owner AMWA. Status "AMWA Specification",
  v1.0.0 released 2025-08-26 (checked with `gh api`). Neither repository has
  open issues, open PRs or work-in-progress branches.
  <https://github.com/AMWA-TV/bcp-008-01>,
  <https://github.com/AMWA-TV/bcp-008-02>, suite overview
  <https://github.com/AMWA-TV/bcp-008>.
- **Classes** (registered in
  <https://github.com/AMWA-TV/nmos-control-feature-sets/tree/main/monitoring>):
  `NcStatusMonitor` 1.2.2 (derived from `NcWorker` 1.2), `NcReceiverMonitor`
  1.2.2.1, `NcSenderMonitor` 1.2.2.2.
- **Receiver properties:** `overallStatus`, `overallStatusMessage`,
  `statusReportingDelay` (NcUint32 seconds, default 3, read-write),
  `linkStatus`, `connectionStatus`, `externalSynchronizationStatus` and
  `streamStatus`, each with a nullable `*StatusMessage` string and an
  `NcUint64` `*StatusTransitionCounter`. Also `synchronizationSourceId` and
  `autoResetCountersAndMessages` (default true). Methods:
  `GetLostPacketCounters`, `GetLatePacketCounters` and
  `ResetCountersAndMessages`.
- **Sender properties:** `transmissionStatus` and `essenceStatus` take the
  place of connection and stream status, and the method is
  `GetTransmissionErrorCounters`.
- **Enums:**
  - `NcOverallStatus` and most domain statuses: 0 Inactive, 1 Healthy,
    2 PartiallyHealthy, 3 Unhealthy.
  - `NcLinkStatus`: 1 AllUp, 2 SomeDown, 3 AllDown.
  - `NcSynchronizationStatus`: 0 NotUsed, then 1 to 3 as above.
- **Counters:** each counter is an `NcCounter {name, value: NcUint64,
  description}`. Counters come from methods and are not properties, so a
  controller cannot subscribe to them.
- **Semantics:**
  - `overallStatus` is the worst of the domain statuses.
  - Transitions to a less healthy state are immediate. Transitions to a
    healthier state must hold for `statusReportingDelay`, which is built-in
    flap damping.
  - Deactivation goes straight to Inactive.
  - Controllers "MUST NOT" interpret the message strings.
  - Vendors may subclass the monitors with authority-key class IDs.
- **Discovery:** the IS-04 Device `controls` entry has type
  `urn:x-nmos:control:ncp/v1.0` and a `ws://` or `wss://` href. The collector
  calls `FindMembersByClassId` (with `includeDerived`) from the root block,
  then reads each monitor's `NcTouchpointNmos`, which maps one-to-one to the
  IS-04 sender or receiver UUID.
- **Collection:** controllers "MUST always use subscriptions and notifications
  ... and not revert to a polling behaviour". Collection is subscribe, plus an
  occasional call to the counter methods.
- **Alerts:** the spec defines no alarms. `overallStatus` "can be used
  directly as a simple pre-defined non-configurable operator alarm
  condition".
- **Adoption:** ten vendors announced BCP-008 interoperability demonstrations
  at IBC 2026
  (<https://www.tvtechnology.com/infrastructure/amwa-and-ebu-to-host-demos-at-ibc-2026>).
  AMWA ran a developer workshop from 2025-11-24 to 2025-11-26
  (<https://go.amwa.tv/nmos-workshop>). (U) No shipping product with BCP-008
  support was confirmed.
- **Four questions:**
  - (1) Typed and fixed, with no units.
  - (2) Strong discovery through IS-04, then IS-12, then class search, then
    the touchpoint.
  - (3) Subscribe.
  - (4) Built-in severity, rollup, damping and transition counters.

### 2.2 IS-12, MS-05-01, MS-05-02 (control protocol and framework)

- **What:** IS-12 v1.0.0 (2023-09-12) and v1.0.1 (2025-07-25). MS-05-01 and
  MS-05-02 v1.0.0 (2023-09-12). Open, owner AMWA. Repositories:
  <https://github.com/AMWA-TV/is-12>,
  <https://github.com/AMWA-TV/ms-05-02>.
- **Self-description:**
  - `NcClassManager` lists every control class and datatype, and
    `GetControlClass` and `GetDatatype` fetch them.
  - `NcPropertyDescriptor` carries `id`, `name`, `typeName`, `isReadOnly`,
    `isNullable`, `isSequence`, `isDeprecated` and `constraints`.
  - Number constraints carry `minimum`, `maximum` and `step`. String
    constraints carry `maxCharacters` and `pattern`.
  - Constraints sit on three levels: datatype, property and runtime.
  - Role paths persist across reboots.
- **No unit field.** A grep for "unit" or "units" over the MS-05-02 docs and
  models returns zero hits, and the project confirmed this directly. The only
  standard quantity with an implied unit is `NcTimeInterval`, an NcInt64 in
  nanoseconds.
- **Notifications:** the controller sends the full list of OIDs it wants
  (`messageType` 3). The device sends `PropertyChanged` notifications with
  `{propertyId, changeType, value, sequenceItemIndex}`. If the WebSocket
  drops, all subscriptions are lost.
- **Documentation defect (fact):** the IS-12 class-discovery example and the
  MS-05-03 blockspec example use class ID `[1,2,3]` for `NcReceiverMonitor`,
  but the register says 1.2.2.1. Implement from the register.
- **Work in progress:** MS-05-03 Blockspecs is a static JSON format that
  declares a block's members. It describes structure and carries no units,
  and it is the nearest AMWA equivalent of an offline declaration file.
- **Four questions:**
  - (1) Rich types and constraints, discovered at runtime, with no units.
  - (2) IS-04 `controls`.
  - (3) Subscribe, plus `Get`.
  - (4) Push of each change as a delta, with no thresholds.

### 2.3 NMOS control feature sets and parameter registers

- **Feature sets:** `nmos-control-feature-sets` has status "Continuing" and no
  releases. It holds three feature sets: Identification (`NcIdentBeacon`
  1.2.1), Monitoring (the BCP-008 classes and datatypes) and Device
  configuration (`NcBulkPropertiesManager` 1.3.3). There is no feature set for
  generic metrics, resource use or function health, and no open issue or PR
  proposes one.
- **Registers:** `nmos-parameter-registers` has no event-type, unit or
  monitoring register. On `main`, `device-control-types` does not yet list
  IS-12 (`urn:x-nmos:control:ncp/v1.0`) or IS-14
  (`urn:x-nmos:control:configuration/v1.0`). Open PR #74 adds them
  (<https://github.com/AMWA-TV/nmos-parameter-registers/pull/74>).

### 2.4 IS-07 (event and tally)

- **What:** IS-07 v1.0.1 (2019-09-06), stable, open, owner AMWA.
  <https://github.com/AMWA-TV/is-07>.
- **Event types:** `boolean`, `string`, `number` and `enum`, written as
  `number/{name}/{unit}`, for example `number/temperature/C`. A number event
  carries `min`, `max`, `step`, `scale` and `unit`.
- **Units:** the spec recommends SI symbols in a guideline. There is no
  registry of event types or units.
- **Transport:** WebSocket or MQTT, connected with IS-05. Messages are
  `state`, `reboot`, `shutdown` and `health`, where `health` is a WebSocket
  keepalive and has no link to a registry heartbeat.
- **Four questions:**
  - (1) This is the only AMWA spec with units, and it carries one scalar per
    IS-04 Source.
  - (2) IS-04 Source and Flow `event_type`.
  - (3) Push.
  - (4) None.
- (J) Good for a handful of discrete points and tally. Too heavy for many
  counters, because each datum needs a Source, a Flow, a Sender and an IS-05
  connection.

### 2.5 IS-04 health and IS-14

- **IS-04:** Nodes heartbeat with `POST /health/nodes/{nodeId}`, every 5 s by
  default. Registries garbage-collect at 12 s by default. Health means that
  the Node's registration is alive, and no other resource has a health state
  (<https://github.com/AMWA-TV/is-04/blob/v1.3.x/docs/Behaviour%20-%20Registration.md>).
- **IS-14:** v1.0.0 (2025-08-26). It exposes the same MS-05-02 model over HTTP
  (`GET .../bulkProperties`), with no subscriptions.
- (J) IS-14 is the only AMWA path that fits a Prometheus-style pull. BCP-008
  does not name it as a collection path, and (U) the project could not confirm
  that real devices expose monitors through it.

### 2.6 AMWA work on software and cloud media functions

- **IN-003** "Compute Resource Management Manifest"
  (<https://github.com/AMWA-TV/in-003>):
  - Status: WIP Increment, `apiVersion: mxl.media.fn/v1alpha1`, kind
    `MxlMediaFunctionParameters`.
  - Schema fields: `metadata` (name, label, namespace); `spec.role`;
    `flow.label`; `inputs[]` and `outputs[]` with video and audio formats;
    `args[]`; and `requirements` (cpu, memory, host_capabilities).
  - **No telemetry or monitoring field.** The project confirmed this with a
    grep. The overview prose mentions "Media Function Metrics" only as an
    architecture box.
  - IN-003 issue #4, opened 2026-10-21, had no replies on 2026-10-22.
- **IN-004** "Flow Connection Phase 2" (WIP) has the only concrete AMWA
  monitoring text for DMF
  (<https://github.com/AMWA-TV/in-004/blob/main/docs/Overview.md>):
  - Error notifications for MXL readers and writers: grain too early
    (`MXL_ERR_OUT_OF_RANGE_TOO_EARLY`), too late, unreadable, wrong format,
    nothing written in time, cannot write.
  - Counters for errors and for correct operation.
  - Latency and jitter measurements.
  - Candidate protocols "NMOS IS-12, OpenTelemetry, ST 2138", with the method
    and the mandatory items both marked "TBD".
- **IN-001** (Control of MXL), section 7.4: "Operational monitoring
  requirements will be defined in a future revision." Issue #6 asks where
  "started but no media flowing" is reported, and suggests a per-flow "last
  grain / last updated" timestamp
  (<https://github.com/AMWA-TV/in-001/issues/6>).
- **IN-006** (business user stories), item 8: metrics for hosting resources
  and for functional applications, and "Exposing metrics may be a licensable
  feature".
- **BCP-007-03** (NMOS with MXL) has no monitoring section.
- The AMWA reading could not identify the "ST 2138" name in IN-004. The
  project resolved it: it is SMPTE ST 2138 Catena (section 4.3).

### 2.7 Implementations and testing

- **nmos-cpp** (<https://github.com/sony/nmos-cpp>, open source): implements
  IS-12, BCP-008-01 and -02, and IS-14. The demo node creates
  `NcReceiverMonitor` objects with simulated status. The repository has no
  tags or GitHub releases, so pin a commit or a Conan recipe.
- **AMWA nmos-device-control-mock** (TypeScript): implements MS-05-02, IS-12,
  BCP-008-01 and -02, and IS-14.
- **AMWA NMOS testing tool:** has `BCP-008-01-01` and `BCP-008-02-01` Node
  suites, merged 2025-07-31 (<https://github.com/AMWA-TV/nmos-testing>). It
  has no controller-side BCP-008 suite.
- **Not found:** any open-source Prometheus, SNMP or OpenTelemetry bridge for
  IS-12 or BCP-008.

### 2.8 What the survey could not find at AMWA

- Any AMWA model for metrics with units for media functions.
- Any AMWA guidance on Kubernetes, Prometheus or OpenTelemetry.
- A plan to add monitoring to IN-003.
- Shipping BCP-008 products.
- The conformance status behind the nmos-cpp badges.

## 3. EBU

### 3.1 DMF Reference Architecture white paper v2.0 (2026-04-15)

Read from a copy of the PDF. Page numbers are PDF pages. Open, owner EBU,
guidance and not a spec.

- p.9, lifecycle "Monitor & Update": "looking for changes from expected values
  and alert". Also "does a Media Function have the correct parameters set".
  This is the intended-versus-observed idea, without a mechanism.
- p.15, Host Platform: names Prometheus, Grafana and InfluxDB.
- p.18, Container Platform: "Telemetry data is collected from Containers.
  Data includes metrics on resource consumption (CPU, GPU, memory, I/O),
  detailed logs ... and traces". The data can "trigger alerts based on
  defined thresholds, and provide feedback to the Container Orchestration to
  maintain the application's defined desired state."
- p.19: "Control & Monitoring with multiple Clusters is subject to further
  study."
- p.23, Media Exchange: "real-time information about the status of Flows,
  such as presence/absence of payloads, throughput, latency".
- p.26, Media Function layer: "Media Functions support real-time monitoring
  through open APIs." Monitoring traffic uses at least TLS 1.3, and clients
  are authorised at least as securely as OAuth2 or JWT. Application layer:
  "AMWA IS-12 ... for live operation and status monitoring."
- **Absent:** metric names, units, endpoints, descriptor fields, collector
  discovery and any mention of OpenTelemetry.
- **Four questions:**
  - (1) Categories only.
  - (2) Loosely, through the IS-04 model.
  - (3) Unspecified.
  - (4) Thresholds and desired state as intent.

### 3.2 EBU Tech 3371 v3.0 (2023-04-13)

"Minimum User Requirements to Build and Manage an IP-Based Media Facility",
<https://tech.ebu.ch/files/live/sites/tech/files/shared/tech/tech3371.pdf>.
Open. This is the strongest EBU text on the subject.

- IV.3.1: Media Nodes "shall provide sufficient Alarming with ability to set a
  threshold for key fault indicators ... such as SNMPv3".
- IV.3.2: Media Nodes "shall provide real-time Telemetry ... on timing, media
  streams and control ... using Open methods e.g., OpenTelemetry, OpenConfig,
  ... MQTT".
- IV.3.3: logging "should" use RFC 5424 syslog, with adjustable levels.
- II.1.3: PTP state "preferably using the IETF RFC 8575 YANG Data Model ...
  or at least RFC 8173 PTP MIB".
- (J) The text targets Media Nodes. Applying it to containerised functions is
  the project's inference. A Prometheus or OpenMetrics endpoint does not
  appear in the examples, but the list says "e.g.", so it is not excluded.
  Offering OTLP or OpenMetrics, plus syslog-compatible structured logs,
  satisfies both documents.

### 3.3 EBU LIST

- **What:** <https://github.com/ebu/pi-list>, GPL-3.0, owner EBU.
- **Status:** the README says "No Longer Actively Maintained".
- **Function:** pcap analysis for ST 2110-20, -21, -22, -30 and -40, ST 2059
  PTP and RP 2110-25. It has a REST API with bearer tokens and a
  `captureAndIngest` workflow, and it has no metrics endpoint.
- (J) Use it as a reference list of what to measure, and avoid building on it.

### 3.4 EBU MCMA

- Media Cloud and Microservice Architecture. The group is closed
  (<https://tech.ebu.ch/groups/mcma>).
- Its only monitoring convention is a job-status model plus the Launch Control
  app.
- The job model went to SMPTE ST 2126 (section 4.4).
- It is no model for telemetry declaration.

### 3.5 Not verified

- EBU R 160 and Tech 3380 content.
- Any EBU monitoring working group.

## 4. Open industry initiatives (IAMT and others)

### 4.1 IAMT Dynamic Software Licensing (DSL) v1.0.0

Published best practice, 2026-09-07. The repository holds a
[summary](iamt-dsl-v1.0.0-summary-and-relevance.md) and a copy of the
[PDF](iamt-dynamic-software-licensing-best-practices-v1.0.0.pdf). Page
numbers below are printed pages.

- **Usage events, yes.** The usage event object (section 11.04, pp. 208 to
  210) has these fields: `leaseId`, `tenantId`, `productId`, `dimension`,
  `quantity`, `granularity`, `timestamp`, `workId` and `submittedAt`. The
  example uses `"dimension": "HOURS"`, `"granularity": "minutes"` and
  `"workId": "deploy-i-0abc123def456"`.
- **Delivery:** push to `POST /v1/usage-records` (section 10.06, pp. 185 to
  188): periodically ("per-minute heartbeats"), at session boundaries, and
  after reconnect with buffered events. The control plane deduplicates on
  (timestamp, lease, dimension).
- **Metering rules** MTR-1 to MTR-7 (pp. 155 to 156): structured dimensions,
  correlated attribution (tenant, product, lease, time, and SHOULD a work or
  deployment context), bounded buffering and idempotent reconciliation.
- **Heartbeat:** `heartbeatSeconds` is a Policy field. It sets a licensing
  reporting cadence and makes no liveness promise. The Policy also holds
  `alertThresholds`. OPS-4 and OFG-7 require operator alerts on renewal
  failure, impending expiry, grace countdown and usage-submission failure.
- **Control-plane observability:** the control plane "MUST propagate
  `traceparent`" with "OpenTelemetry-compatible tooling" (p. 167).
- **No function health telemetry:** no metric names, no unit registry and no
  collector discovery for the licensed application.
- (J) Alignment points:
  - Carry a `workId`-compatible correlation label on function telemetry.
  - Mark a subset of declared metrics as metered so they map to DSL
    `dimension` and `quantity`.
  - Expose the DSL alert inputs (grace countdown, renewal failures) as
    declared metrics of the license agent.
  - Keep licensing usage separate from health metrics, as DSL itself does
    ("Separation from enforcement").

### 4.2 IAMT itself

- **Working groups** (<https://theiamt.org/groups/>): Tariff Strategy, DSL,
  Control Plane, Catena, Security and Vulnerability, and SIM Farm.
- **Telemetry work:** none found. (U) The member area was not accessible.
- (J) If IAMT takes up the topic, the Catena or Control Plane groups are the
  likely homes.

### 4.3 SMPTE ST 2138 Catena

- **What:** open control model, owner SMPTE 34CS, originating in the Open
  Services Alliance (OSA) under SMPTE Rapid Industry Solutions. Parts -10,
  -11, -12, -19 and -50 are Public Committee Drafts
  (<https://www.smpte.org/standards/st2138>). The schema repository
  `SMPTE/st2138-a` is at `v1.1.1-pre-fcd` (last commit 2026-10-19). The
  reference SDK is vendor-led (BSD-3-Clause).
- **Declaration:**
  - A typed parameter tree: INT32, FLOAT32, STRING, STRUCT, arrays and others.
  - Each parameter has `read_only`, `constraint`, and a `stateless` flag for
    meters and clocks.
  - An `ALARM_TABLE` constraint holds up to 32 alarms, each with a severity
    (INFO, WARNING, SEVERE, UNKNOWN, REFUSED).
  - **No unit field** (grep of the interface tree).
- **Collection:** gRPC or REST reads, plus `UpdateSubscriptions` streaming
  with OID wildcards.
- (J) A control surface with alarms. Weak for unit-bearing time series. Named
  in AMWA IN-004 as a candidate.

### 4.4 SMPTE ST 2126 (microservice status reporting and logging)

- **Status:** SMPTE lists ST 2126:2025. The project saw this only in a
  snippet; (U) it could not get the published text. It read the 2020 public
  committee draft (<https://github.com/SMPTE/st2126>).
- **Contents:** a Job object with `status` (New, Queued, Scheduled, Running,
  Completed, Failed, Canceled). JSON log entries with `type`, `level`,
  `source`, `requestId`, `timestamp`, `trackerId` and `trackerLabel`. Levels
  run FATAL 100 to DEBUG 500, plus job and function start and end types.
- (J) Relevant to log shape and correlation (`trackerId`, compare with DSL
  `workId`). It has no bearing on metrics.

### 4.5 Others

- **Linux Foundation MXL:** no metrics, health or logging interface in the
  repository. See section 5.4.
- **Open Services Alliance:** outputs are ST 2126 and Catena. No separate
  telemetry spec found.
- **MovieLabs** (Ontology for Media Creation, 2030 Vision): no telemetry
  content found. (U) The papers were not read.
- **VSF:** no monitoring recommendation and no monitoring activity group. See
  section 5.3.
- **NABA, Academy Software Foundation, CNCF media groups:** nothing found.
- **OpenTelemetry:** CNCF graduated 2026-05-21
  (<https://www.cncf.io/announcements/2026/05/21/cloud-native-computing-foundation-announces-opentelemetrys-graduation/>).
- **SRT** (vendor-led open source): statistics with units in the field names
  (`msRTT`, `pktSndLossTotal`, `byteSentTotal`), pulled by API call
  (<https://raw.githubusercontent.com/Haivision/srt/master/docs/API/statistics.md>).
  The same vendor ships an SRT Prometheus exporter (vendor).
- **RIST:** libRIST stats arrive by callback at an interval, as JSON plus
  structs. (U) Read from an unofficial mirror.
- **IETF Media over QUIC:** `draft-jennings-moq-metrics` is an expired
  individual draft. Too early to depend on.
- **ETSI NFV**, read from <https://forge.etsi.org/rep/nfv/SOL006>: the
  strongest precedent for a declaration in a descriptor.
  - `monitoring-parameter` has `name`, `performance-metric` (a measurement
    name from the IFA 027 registry) and `collection-period` (uint64,
    "ms"), declared per VDU and per VNF.
  - VNF `indicator` has `id`, `name`, `indicator-value` (allowed values) and
    `source` (vnf, em or both).
  - `auto-scale` rules reference indicators and monitoring parameters.
- **ONAP VES:** the vendor MUST ship a VES Event Registration YAML that lists
  event names and fields (R-520802), plus threshold conditions and
  recommended actions (R-120182). Delivery is a push over HTTPS. A
  `thresholdCrossingAlert` domain exists
  (<https://docs.onap.org/projects/onap-vnfrqts-requirements/en/istanbul/Chapter8/ves7_1spec.html>).
  (J) "Vendor ships defaults, operator overrides" is the pattern worth
  following.
- **TM Forum TMF628 and TMF642:** performance and alarm management APIs.
  (U) Details were not fetched (403). Too heavy for this use.

## 5. Broadcast transport, timing and devices

The SMPTE documents below were downloaded free from `pub.smpte.org` on
2026-10-22.

### 5.1 ST 2110 and ST 2022-7

- **ST 2110-10:2022, section 6:** RTCP "may be used"; "Receivers shall
  tolerate the presence of RTCP". RTCP is optional
  (<https://pub.smpte.org/latest/st2110-10/st2110-10-2022.pdf>).
  (J) Avoid depending on RTCP.
- **ST 2110-21:2022:** senders signal `TP`, `TROFF` and `CMAX` in SDP. This
  is the intended timing
  (<https://pub.smpte.org/latest/st2110-21/st2110-21-2022.pdf>).
- **RP 2110-25:2023** "Measurement Practices": names and formulae for
  measurements, including C_INST, VRX, FPT, RTPOFFSET, Video Latency, Margin
  and GAP for video; ADV, PIT, AL and AVDL for audio; and ANC latency. It is
  scoped to test equipment and defines no wire format
  (<https://pub.smpte.org/latest/rp2110-25/rp2110-25-2023.pdf>). (U) The
  project read the table of contents only, so the units are not extracted
  yet.
- **ST 2022-7:2019:**
  - Receiver classes A to D are set by path differential.
  - Annex B is informative only. A receiver "could" track received and lost
    datagrams per stream and expose the buffer setting, and "might" notify on
    protected and unprotected transitions
    (<https://pub.smpte.org/latest/st2022-7/st2022-7-2019.pdf>).
- (J) Use RP 2110-25 terms as metric names, so function output and analyzer
  output compare. Take the intended side (SDP, two legs configured) from the
  control plane.

### 5.2 ST 2059 and PTP

- **ST 2059-2:2021:** uses IEEE 1588 management messages (section 6.3). It
  defines the Synchronization Metadata TLV, which carries the default frame
  rate, time offset, DST and jam information (sections 6.12 and 6.13)
  (<https://pub.smpte.org/latest/st2059-2/st2059-2-2021.pdf>).
  (J) This is a source of intended frame rate and time labelling.
- **IEEE 1588 management:** GET, SET and COMMAND on CURRENT_DATA_SET,
  PARENT_DATA_SET, PORT_DATA_SET, TIME_PROPERTIES_DATA_SET and others, read
  with the linuxptp `pmc` tool
  (<https://sources.debian.org/src/linuxptp/4.4-1/pmc.8>). The IEEE text is
  paywalled and was not read (U).
- **RFC 8173 (PTP MIB) and RFC 8575 (PTP YANG):** standards track, read-only,
  no notifications in RFC 8575
  (<https://www.rfc-editor.org/rfc/rfc8173.html>,
  <https://www.rfc-editor.org/rfc/rfc8575.html>).
- **SMPTE RP 2059-15:2023**, "YANG Data Model for ST 2059-2 PTP Device
  Monitoring": the best broadcast find for a declaration model
  (<https://pub.smpte.org/doc/rp2059-15/20221110-pub/rp2059-15-2023.pdf>).
  - It adapts RFC 8575 under NMDA and adds IEEE 1588-2019, ST 2059-2, RFC 8173
    and GNSS data sets.
  - It is read-only and has no notifications.
  - It "does not define a communication model or transport mechanism".
  - An unsupported parameter is returned empty.
  - Performance records follow IEEE 1588-2019 Annex J, at 15-minute and
    24-hour intervals.
  - (U) Adoption unverified.
- **Open exporters:** thin. A telecom-oriented, vendor-led open-source
  linuxptp daemon exports the clock offset in nanoseconds and a clock-state
  gauge (0 FREERUN, 1 LOCKED, 2 HOLDOVER) and similar metrics. The other
  exporters found are lab projects.
- (J) A `ptp-monitor` sidecar built on `pmc` or libptpmgmt should name its
  metrics after RP 2059-15 leaves.

### 5.3 VSF

- **Recommendations:** none has monitoring or telemetry as its scope.
  TR-10-x (IPMX) is mostly draft, and (U) TR-10-9 was not read. TR-11 (GCCG)
  is a draft whose PDF could not be fetched. TR-02 (RTCP status, 2015) was
  not fetched. Source: <https://vsf.tv/technical-recommendations/>.
- **Activity groups:** none for monitoring (<https://vsf.tv/activity-groups/>).
- **`vsf-tv/gccg-api`:** a transport API with no health or status endpoint.
- **VidTrans 2025 decks:**
  - A presentation on BCP-008 "Minimal Status Reporting":
    <https://static.vsf.tv/vidtrans/presentations/2025/LedergerberNMOSIPMonitoring.pdf>.
  - A PTP best-practices deck: enable the SM TLV, monitor grandmaster ID and
    lock state. It is opinion and no standard:
    <https://static.vsf.tv/vidtrans/presentations/2025/WhitcombPTPMadeEasy.pdf>.

### 5.4 MXL

- **Telemetry:** no metrics, health, telemetry or logging in the README or
  `docs/Architecture.md` (<https://github.com/dmf-mxl/mxl>).
- **Per-flow runtime data:** each flow's shared-memory header holds
  `mxlFlowRuntimeInfo` (`headIndex`, `lastWriteTime`, `lastReadTime`).
- **Flow definition:** `flow_def.json` is an NMOS IS-04 Flow.
- **Tools:** `mxl-info` prints per-flow latency in grains and an "Active"
  flag. `docs/Timing.md` tells implementers to monitor latency with
  `mxl-info`. `mxl-data-probe` exits non-zero on timeout or overrun.
- (J) Monitoring MXL needs a sidecar that reads the domain and exports
  `last_write_age_seconds`, head index, latency and an active flag. That is
  also the "media flowing" signal IN-001 issue #6 asks for. dmfdeploy could
  propose it upstream.

### 5.5 Ember+

- **What:** open protocol, originated by a broadcast vendor, BSL-1.0
  (<https://github.com/Lawo/ember-plus>). Specification v2.50.
- **Parameters** carry `minimum`, `maximum`, `access`, `format`,
  `enumeration`, `factor`, `formula` and `streamIdentifier`.
  - The unit lives inside the format string, after a `°` marker, for example
    `%.2f°dB`.
  - `factor` is an integer divisor.
- **Collection:** normal parameters push changes. Stream parameters (meters)
  need an explicit Subscribe.
- **Not found:** an Ember+ to Prometheus bridge.
- (J) Its parameter attributes are a good checklist for a declaration: range,
  access, enum, unit, scale.

### 5.6 SNMP

- No SMPTE MIB was found. Vendor MIBs are not public in any consistent way.
- The Prometheus `snmp_exporter` generator (open,
  <https://github.com/prometheus/snmp_exporter>) builds modules from MIBs.
  dmfdeploy already runs an SNMP lane (ADR-0038).

### 5.7 Vendor fabric telemetry (vendor, marketing sources only)

- One network-switch vendor's IP fabric for media, with its controller
  (vendor), offers per-flow RTP loss and PTP drift.
- A second switch vendor's media control service, with its cloud management
  (vendor), offers streaming telemetry.
- (J) Fabric telemetry joins function telemetry through a shared flow
  identifier: the NMOS flow ID, or the multicast group and source.

## 6. Cloud-native standards

### 6.1 OpenTelemetry

- **Signal status** (<https://opentelemetry.io/docs/specs/status/>): traces
  are stable. The metrics API is stable and the OTLP protocol is stable. The
  logs bridge API and SDK are stable. Profiles are in development, with a
  public alpha blog post in 2026.
- **Semantic conventions:** version 1.44.0 at the time of reading
  (<https://opentelemetry.io/docs/specs/semconv/>). Group types are span,
  metric, event, entity and attribute_group. Stability levels run from
  development to stable.
- **`k8s.*` attributes:** the resource page says Stable for the core ones, but
  a 2026 blog says release candidate. (U) Unresolved, so pin a semconv
  version.
- **Schema URLs and schema files:** they identify a version and describe
  renames between versions. They do not list what a component emits
  (<https://opentelemetry.io/docs/specs/otel/schemas/>).
- **Collector:** the Prometheus receiver is Beta and embeds standard
  `scrape_configs`. The `k8s_cluster` receiver is Beta.
- **OpAMP:** Beta. It manages agent fleets (configuration, status, packages,
  `ComponentHealth`). It does not declare function telemetry
  (<https://opentelemetry.io/docs/specs/opamp/>).
- **Weaver** (<https://github.com/open-telemetry/weaver>, Apache-2.0):
  - A custom registry is a `manifest.yaml` (`name`, `schema_url`,
    `dependencies`) plus YAML groups.
  - A metric group needs `metric_name`, `instrument` (counter, histogram,
    gauge or updowncounter), `unit` (OTel and UCUM style, such as `s`, `By`
    or `{packet}`) and `stability`. It can add `attributes` by `ref`.
  - Commands: `registry check`, `resolve`, `diff`, `generate`,
    `live-check`, `emit`.
  - `live-check` compares OTLP or sample-file input against the registry. It
    reports violations and registry coverage, and it exits non-zero on a
    violation.
  - (U) No version or stability label for live-check. (U) The sample-file
    JSON schema was not verified.
- **Four questions:**
  - (1) Yes, Weaver is the best declaration format found.
  - (2) None, it is a file.
  - (3) Not applicable.
  - (4) live-check is an "intended versus observed" check for the telemetry
    contract itself.

### 6.2 Prometheus and OpenMetrics

- **Formats** (<https://prometheus.io/docs/instrumenting/exposition_formats/>):
  - Text 0.0.4 has `# HELP` and `# TYPE`, and no UNIT line.
  - OpenMetrics 1.0 adds `# UNIT`, exemplars, Info and StateSet.
  - The protobuf format carries the unit.
  - Since Prometheus 3.0, a scrape fails on a missing or unsupported
    Content-Type.
- **OpenMetrics 2.0:** rc0, experimental (March 2026). The unit suffix becomes
  SHOULD, and `_total` is no longer required on counters
  (<https://prometheus.io/docs/specs/om/open_metrics_spec_2_0/>).
- **Metadata APIs**
  (<https://prometheus.io/docs/prometheus/latest/querying/api/>):
  `/api/v1/metadata` and `/api/v1/targets/metadata` return
  `{type, help, unit}` per metric and per target. Both are experimental.
- **Naming** (<https://prometheus.io/docs/practices/naming/>): base-unit
  plural suffixes, `_total` for counters, ratios from 0 to 1.
- **promtool:** `check metrics`, `check rules` and `test rules`.
- **Prometheus 3.x:** UTF-8 names by default. Native histograms are stable
  from v3.8. The `type-and-unit-labels` feature flag exists. Remote-Write 2.0
  carries metadata and is experimental.
- **Four questions:**
  - (1) Runtime metadata only.
  - (2) Service discovery plus annotations.
  - (3) Pull.
  - (4) Rules and Alertmanager. The metadata API makes a declared-versus-observed
    diff possible.

### 6.3 Prometheus Operator CRDs

- **Kinds:** `monitoring.coreos.com/v1` defines ServiceMonitor, PodMonitor,
  PrometheusRule and Probe. ScrapeConfig is alpha
  (<https://prometheus-operator.dev/docs/api-reference/api/>).
- **Chart pattern:** `serviceMonitor.enabled: false` and
  `prometheusRule.enabled: false` by default (prometheus-community charts;
  charts from other vendors follow the same default).
- **Helm:** does not upgrade CRDs. Rendering a ServiceMonitor without the CRD
  fails with "no matches for kind"
  (<https://helm.sh/docs/chart_best_practices/custom_resource_definitions/>).
- **Fact, local:** dmfdeploy runs the plain `prometheus` community chart at
  25.8.0 and runs no kube-prometheus-stack. Alert rules are platform-owned
  files in the dmf-infra Prometheus role.
- (J) ADR-0047 forbids shipping CRDs, operators and controllers through the
  generic path. ServiceMonitor instances are no CRDs, but on this platform
  they would be inert or fail to install. A ServiceMonitor should therefore
  stay out of the declaration. The descriptor carries the same intent and
  the platform renders it.

### 6.4 Kubernetes health

- Startup, liveness and readiness probes (httpGet, tcpSocket, exec, grpc),
  plus pod `readinessGates`.
- The condition convention: `type`, `status`, `reason`, `message`,
  `observedGeneration` and `lastTransitionTime`
  (<https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md>).
- Events are best-effort.
- (J) The probes already form an intended-versus-observed model. A descriptor
  can name custom readiness gates, for example "media flowing", that a sidecar
  sets.

### 6.5 CloudEvents and xRegistry

- **CloudEvents:** CNCF graduated 2024-01-25. Spec 1.0, with attributes `id`,
  `source`, `type`, `dataschema` and others
  (<https://github.com/cloudevents/spec/blob/main/cloudevents/spec.md>).
- **xRegistry:** CNCF sandbox. The message spec is at 1.0-rc4, and it
  declares the event types and schemas a producer emits
  (<https://github.com/xregistry/spec/blob/main/message/spec.md>).
- **CloudEvents Discovery:** the old spec path returns 404. (U) It seems to be
  superseded by xRegistry.
- (J) Use these for discrete events only, such as flow state changes or
  licence events, and make them optional.

### 6.6 gNMI and OpenConfig

- gNMI 0.10.0. `Capabilities` returns `supported_models`. `Subscribe` offers
  ONCE, POLL and STREAM (ON_CHANGE, SAMPLE, TARGET_DEFINED)
  (<https://github.com/openconfig/reference/blob/master/rpc/gnmi/gnmi-specification.md>).
- gnmic (open source) exports to Prometheus.
- (J) This is the network-world pattern: a typed YANG model, capability
  discovery and subscription. It fits switches, and an RP 2059-15 PTP
  collector. A containerised function has little need for it. (U) Broadcast
  switch adoption rests on one unverified forum mention naming two switch
  vendors.

### 6.7 SLO standards

- **OpenSLO** (<https://openslo.com/>): YAML kinds SLO, SLI, AlertPolicy and
  DataSource. Community-owned. (U) Version not verified.
- **Sloth** (open, <https://github.com/slok/sloth>): generates plain
  Prometheus rule files from its own spec or from OpenSLO.
- **Pyrra** (open): CRD-based.
- **Metrics catalogs:** no standard found.
- (J) Sloth in generator mode fits a platform without CRDs.

### 6.8 Packaging precedents

- **Artifact Hub annotations**
  (<https://artifacthub.io/docs/topics/annotations/helm/>): no monitoring
  annotation. The closest is `category: monitoring-logging`.
- **OLM capability level 4, "Deep Insights":** a label for metrics, alerts and
  dashboards. It cannot be machine-checked, and the CSV has no metrics list
  (<https://sdk.operatorframework.io/docs/overview/operator-capabilities/>).
- **Monitoring mixins** (<https://monitoring.mixins.dev/>): jsonnet bundles
  that render to plain alert, rule and dashboard files. This is the best
  precedent for "an app ships its alerts" without CRDs.
- **ETSI NFV and ONAP VES:** see section 4.5. These are the closest precedents
  for a descriptor that lists monitorables.

## 7. Comparison table

| Item | Open or vendor; owner | Maturity | (1) Declare, types, units | (2) Discovery | (3) Mode | (4) Alerts or deltas |
|---|---|---|---|---|---|---|
| JT-DMF | Open; EBU and AMWA | Charters pending | Nothing published | n/a | n/a | n/a |
| EBU DMF RA v2.0 | Open; EBU | Guidance | Categories only | IS-04, loosely | Unspecified | Thresholds, desired state (intent) |
| EBU Tech 3371 v3 | Open; EBU | Published 2023 | Protocol list, no schema | No | SNMP, OTel, MQTT, syslog | Thresholds on fault indicators |
| BCP-008-01/02 | Open; AMWA | v1.0.0, 2025-08 | Fixed typed status set, no units | IS-04, then IS-12 class search | Subscribe | Traffic light, damping, counters |
| IS-12 / MS-05-02 | Open; AMWA | v1.0.x | Runtime types and constraints, no units | IS-04 `controls` | Subscribe, Get | Push on change |
| IS-07 | Open; AMWA | v1.0.1 | Number with unit, range, scale | IS-04 Source and Flow | Push (WS, MQTT) | None |
| IS-04 heartbeat | Open; AMWA | Stable | None | Registry | 5 s heartbeat | Node presence |
| IS-14 | Open; AMWA | v1.0.0 | Same model as IS-12 | IS-04 (register pending) | HTTP pull | None |
| IN-003 | Open; AMWA, JT-DMF | WIP v1alpha1 | No telemetry fields | n/a | n/a | n/a |
| IN-004 | Open; AMWA, JT-DMF | WIP, TBD | Names errors and counters | n/a | IS-12, OTel, ST 2138 named | n/a |
| ST 2110-10 RTCP | SMPTE | Published, optional | No | SDP | In-band push | None |
| RP 2110-25 | SMPTE | Published 2023 | Vocabulary only | SDP | Not defined | SDP intent vs measured |
| ST 2022-7 Annex B | SMPTE | Informative | Hints | SDP | Not defined | Legs configured vs protected |
| RP 2059-15 | SMPTE | Published 2023 | Typed YANG with units | Not defined | Not defined | None |
| IEEE 1588 mgmt / pmc | IEEE; linuxptp open | Stable | Fixed data sets | Port identity | Pull | Profile vs data sets |
| MXL | Open; LF, EBU, NABA | Alpha onward | None (runtime header only) | Domain listing | Local pull | Liveness only |
| Ember+ | Open; vendor-originated | v2.50 | Range, enum, unit in format | Tree walk | Push, subscribe | None |
| Catena ST 2138 | Open; SMPTE | Public CD, pre-FCD | Typed params, alarm table, no units | Device model | Read, subscribe stream | Alarm severity |
| ST 2126 | SMPTE | 2025 (U) | Job status, log schema | No | Logs | Level, status |
| IAMT DSL 1.0.0 | Open; IAMT | Published 2026-09 | Licence dimensions only | No | Push, buffered | Grace and renewal alerts |
| ETSI NFV VNFD | Open; ETSI | Mature (telecom) | monitoringParameter, indicators | Package descriptor | PM jobs, subscribe | Auto-scale rules |
| ONAP VES | Open; LF Networking | Mature (telecom) | Event registration YAML | Package file | Push | Threshold alerts, operator override |
| OTel Weaver registry | Open; CNCF | Active (U version) | Name, instrument, unit, stability | File | n/a | live-check coverage |
| OTel semconv and schema URL | Open; CNCF | 1.44.0 | Vocabulary, renames | URL | n/a | None |
| OTel Collector, OpAMP | Open; CNCF | Beta | Pass-through; agent mgmt | k8s SD; server | Pull in, push out | Agent health |
| Prometheus text / OpenMetrics | Open; CNCF | Stable; OM 2.0 rc | HELP, TYPE, UNIT at runtime | SD, annotations | Pull | Rules; metadata diff |
| Prometheus Operator CRDs | Open; Prometheus org | v1 | No | Selectors | Pull | PrometheusRule |
| K8s probes and conditions | Open; Kubernetes | GA | Health only | API | Kubelet | Native desired vs observed |
| CloudEvents, xRegistry | Open; CNCF | Graduated; rc4 | Event types and schemas | Registry API | Push | None |
| gNMI / OpenConfig | Open; OpenConfig | 0.10.0 | YANG models | Capabilities | Subscribe | None |
| OpenSLO, Sloth | Open; community | U | SLO on metric names | No | Rules | SLO to burn-rate alerts |
| Monitoring mixins | Open; community | Common | Rule and alert definitions | File | n/a | Yes |
| Artifact Hub, OLM | Open; CNCF, Operator Framework | Current | Category or label only | Catalog | n/a | None |

## 8. Where dmfdeploy stands today (facts, local)

- ADR-0038 fixes a catalog `monitoring:` block with three lanes:
  `scrape` (`enabled`, `metrics_port`, `metrics_path`, `scheme`), `probe`
  (`probe_module`) and `snmp` (`snmp_module`). The launcher stamps
  `prometheus.io/*` annotations for pods. NetBox tags and custom fields drive
  `http_sd` for everything else.
- ADR-0047 makes the Media Function Package "catalog metadata + Helm chart +
  image closure + probes + declared resources.requests + licence: block +
  provenance + signatures". It forbids CRDs, operators, controllers and
  webhooks in the generic path.
- Issue #634 defines `dmf-function.yaml` with "lifecycle, health, and
  dependency declarations". It also defines a conformance tool that renders
  named fixtures and compares the descriptor with the render.
- The [closed-loop assurance plan](../plans/DMF%20Closed-Loop%20Assurance%20Pattern%20Plan%202026-10-21.md)
  (§1, §2, §5) maps observed state to the monitoring vertical, extract-intent
  to dmf-promsd, and deltas to `operate-catalog-drift.yml` and alerts. Gap 1
  is a Problems view. Gap 5 is an NMOS flow comparison. Media observed state
  (PTP lock, flow health) waits on the `ptp-monitor` and `flow-exporters`
  roles, which are on hold.
- Prometheus is the plain community chart (25.8.0) with platform-owned rule
  files. There is no Prometheus Operator.

## 9. Recommendation: a `telemetry` block in `dmf-function.yaml`

All of section 9 is judgment (J). It is a starting hypothesis for the RFC in
[#685](https://github.com/dmfdeploy/dmfdeploy/issues/685).

### 9.1 Design rules

1. **Reference existing standards.** Use Weaver registry YAML for metric
   definitions, OTel and UCUM unit strings, and Prometheus naming for the
   exposed names. Use BCP-008 class IDs for NMOS monitors, IS-07 event type
   strings for events, Kubernetes probe semantics for health, and Prometheus
   rule-file format plus `promtool test` for alerts. The descriptor adds only
   the glue: which port, which fixture, which intent each signal is checked
   against.
2. **One source.** The ADR-0038 `monitoring:` lanes become derived output of
   `telemetry` (this needs an ADR-0038 amendment), in the same way #634
   generates Artifact Hub annotations from the descriptor.
3. **Declare pointers for self-describing protocols, and declare lists for
   the rest.** IS-12 describes itself at runtime, so declare only that the
   endpoint and the monitors exist. Prometheus describes itself weakly, so
   declare the metric list.
4. **No CRDs.** Alerts and SLOs travel as plain files that the platform loads.
5. **Keep it small at v1.** Required: health, the metrics endpoint and a
   minimal metric list. Everything else is optional.

### 9.2 Sketch

```yaml
telemetry:
  schemaVersion: dmf.telemetry/v1alpha1
  correlation:                       # labels the platform stamps on all signals
    labels: [dmf_function, dmf_instance, dmf_workload, work_id]   # work_id aligns with IAMT DSL workId
  health:                            # must equal the rendered chart probes
    startup:   { httpGet: { port: http, path: /healthz/startup } }
    liveness:  { httpGet: { port: http, path: /healthz/live } }
    readiness: { httpGet: { port: http, path: /healthz/ready }, meaning: media-flowing }  # or: process-up
    readinessGates: []               # optional custom conditions a sidecar sets
  metrics:
    endpoints:
      - port: metrics                # a named port from the typed ports block
        path: /metrics
        scheme: http
        format: openmetrics-text/1.0.0   # or prometheus-text/0.0.4
    registry: telemetry/registry/    # Weaver registry: manifest.yaml + groups (name, instrument, unit, stability)
    semconv: https://opentelemetry.io/schemas/1.44.0   # pinned dependency
    required:                        # subset that must appear in every named fixture scrape
      - dmf.mxl.flow.write.age       # exposed as dmf_mxl_flow_write_age_seconds
      - dmf.function.frames.dropped  # exposed as dmf_function_frames_dropped_total
    metered: [dmf.function.output.channels]   # optional, maps to DSL dimension/quantity
  nmos:
    controlProtocol: { type: "urn:x-nmos:control:ncp/v1.0", port: ncp }
    monitors:                        # one per declared NMOS receiver or sender
      receivers: { classId: "1.2.2.1", coverage: all }
      senders:   { classId: "1.2.2.2", coverage: all }
    events: []                       # optional IS-07 event types, e.g. number/temperature/C
  sidecars:                          # protocol adapters the chart ships, each with its own registry
    - name: mxl-flow-exporter        # reads mxlFlowRuntimeInfo, exports declared metrics
    - name: ptp-exporter             # pmc-based, metric names after RP 2059-15 leaves
  logs:
    stream: stdout
    format: json                     # fields aligned with ST 2126 log entry (level, timestamp, trackerId)
  events:
    cloudevents: []                  # optional: types + dataschema, xRegistry message-group shape
  alerts:
    rules: telemetry/alerts.rules.yaml        # plain Prometheus rule file, loaded by the platform
    tests: telemetry/alerts.rules.test.yaml   # promtool test rules
    overridable: [for, severity, thresholds]  # operator override, VES-style
  slos: telemetry/slo.openslo.yaml   # optional, rendered to rules with Sloth generator mode
```

### 9.3 Conformance tool checks

**Tier S (static, every package, cheap):**

1. The JSON Schema accepts the block.
2. `weaver registry check -r telemetry/registry` passes, and every `required`
   and `metered` name exists in the registry.
3. The exposed Prometheus names derived from the registry follow the naming
   rules (unit suffix, `_total`). Validate with Prometheus' own parser and
   skip regular expressions.
4. `promtool check rules` and `promtool test rules` pass. Every alert
   references only declared metrics and carries the platform's required
   labels and severities.
5. The rendered fixture (`helm template` with each named fixture) has probes
   that equal `health`, and has the declared ports with the declared names.
   It ships no Prometheus Operator kinds.
6. NMOS: every declared receiver and sender in the descriptor's NMOS block
   has a monitor entry, and the class IDs are registered ones or have a
   standard prefix.
7. Mutation fixtures fail: a metric dropped from the registry, a unit
   changed, a probe path changed, an alert that references an undeclared
   metric. These prove that each check can detect a fault.

**Tier D (dynamic, certification tier or nightly, needs the image to run):**

1. Run the rendered fixture in a throwaway cluster (kind or k3d), or run the
   container with the fixture values.
2. Scrape every declared endpoint. Pipe the output to
   `promtool check metrics`. Assert that the Content-Type matches `format`.
3. Diff the scrape against the registry by set, and compare names rather than
   counts. Every `required` name must be present, with the declared type and
   unit (`# TYPE` and `# UNIT`). Undeclared names are a warning at v1 and an
   error at a later tier. Optionally convert the scrape to Weaver live-check
   sample input for coverage reporting, or put an OTel Collector in front and
   use OTLP live-check.
4. Probe the health endpoints and check the readiness transition.
5. If `nmos` is declared, run the NMOS testing tool suites `IS-12-01`,
   `BCP-008-01-01` and `BCP-008-02-01` against the running node.
6. Record the result as an attestation next to the package signature. That
   way, promotion (ADR-0047) can require "telemetry conformance: tier D" for
   certified packages.

### 9.4 Feeding the closed loop

The assurance plan reports each difference between intended and observed
state as a delta. Declared telemetry gives three delta classes. Each one is an
Alertmanager alert with a stable `delta_class` label, so the Problems view
(gap 1) can group the deltas and show their durations.

1. **Contract delta.** Intended: the descriptor's `required` metrics and
   types. Observed: `/api/v1/targets/metadata` for the instance's target.
   Delta: a required metric is missing or has the wrong type or unit, or the
   target is down (`up == 0`). This catches a function that deployed but
   does not expose what it promised. The metadata API is experimental, so pin
   the Prometheus version or use a dmf-promsd-side check instead.
2. **Presence delta.** Intended: the NetBox instance and tags (ADR-0037,
   ADR-0039). Observed: a scrape target exists, IS-04 registry presence
   (heartbeat, 12 s GC), and pod readiness. Delta: an instance exists in
   NetBox but is absent from the registry or not ready. Suppress during
   born-inventory rebuilds with an environment build ID label, as §4 of the
   plan requires.
3. **Media-health delta.** Intended: the workload design and the IS-05 active
   connections (§3 of the plan records NMOS as the source of media intent).
   Observed:
   - BCP-008 `overallStatus` and domain statuses, through an IS-12 collector
     that subscribes and exposes gauges.
   - MXL write age.
   - PTP lock state.

   Deltas:
   - Connected but `Unhealthy` for longer than N seconds.
   - Configured with two 2022-7 legs but `linkStatus` SomeDown.
   - SM TLV frame rate differs from the SDP frame rate.

   This is gap 5 of the plan, and it needs one new platform component: an
   IS-12 to Prometheus bridge. The survey found no existing implementation.

Function-shipped alert rules carry defaults. The platform owns the rule
loading and may override `for`, `severity` and thresholds per environment.
This follows the VES "vendor ships, operator overrides" pattern, and it keeps
the ADR-0047 rule that publishers ship apps and the platform owns cluster machinery.

### 9.5 Suggested issues (not yet filed; the work starts at an issue)

- A `telemetry` block schema plus Tier S checks, as part of or following #634
  (component dmf-media).
- An ADR-0038 amendment: derive `monitoring:` from `telemetry` (umbrella).
- An IS-12 and BCP-008 to Prometheus bridge (dmf-media or dmf-infra). Pilot it
  against nmos-cpp's simulated monitors.
- An MXL flow exporter sidecar, plus an upstream note to MXL and AMWA IN-001
  issue #6 (the project reviews external text first).
- A platform loader for function-shipped rule files (dmf-infra Prometheus
  role).

## 10. Open questions

1. Is telemetry conformance a promotion gate (ADR-0047 ladder), or advisory at
   v1?
2. Should Tier D run in dmf-media CI (needs a cluster and image pulls) or in a
   separate certification lane?
3. Weaver registry as separate files, or an inline list in the descriptor? A
   registry folder reuses the tooling. An inline list keeps one file.
4. What should `readiness` mean for a media function: "process up" or "media
   flowing"? A wrong choice can make Kubernetes restart a function that is
   only waiting for input.
5. Who owns the IS-12 collector: the platform (one central bridge) or each
   function (a sidecar)? Central fits the BCP-008 rule against excess
   connections.
6. Should OTLP push be a second accepted mode alongside the Prometheus pull?
   It would need a Collector in the monitoring vertical, and it would match
   the EBU Tech 3371 OpenTelemetry example.
7. How do function-shipped rules get trusted? Rules can be expensive or noisy.
   Should they fall under `generic-chart-policy/v1` limits?
8. Should dmfdeploy propose a "media function monitor" feature set (MXL
   reader and writer counters, latency) to AMWA and the JT-DMF CRM track,
   building on IN-004? This is external contact, so the project decides
   first.
9. Does the IN-003 mapping (#634) need a telemetry extension point, or should
   it stay out until AMWA defines one?
10. Is the metered subset (the DSL alignment) in scope before ADR-0045
    licence enforcement is decided?

## 11. What the survey could not find or verify

- JT-DMF charters, minutes or any monitoring requirement. The June 2026
  agenda was an image. Member areas need a login.
- Shipping products with BCP-008. The conformance sheets behind the nmos-cpp
  badges. An IS-12 to Prometheus bridge.
- Any AMWA plan to add monitoring fields to IN-003.
- EBU R 160 and Tech 3380 content. Whether Tech 3371 is meant to apply to
  containerised functions.
- The VSF TR-10-9, TR-11 and TR-02 texts. Any VSF monitoring work.
- IEEE 1588-2019 text (paywalled), and any published IEEE PTP MIB or YANG
  after the 2020 PAR. Adoption of RP 2059-15.
- The units of each RP 2110-25 measurement (table of contents only).
- The published ST 2126:2025 text (the 2020 draft was read). The final status
  of Catena parts.
- IAMT member-area work. MovieLabs, ASWF, NABA or CNCF media telemetry work.
  DSL chapter 15 (future work) was not read for telemetry plans.
- Weaver release version and the live-check stability label and sample JSON
  schema. OTel `k8s.*` stability (the pages conflict). OpenSLO, Sloth and
  Pyrra versions. The OpenMetrics 1.0 formal status. The CloudEvents
  Discovery spec location.
- Broadcast switch gNMI adoption (only one forum mention). Vendor MIB details.
  sFlow or IPFIX for ST 2110.
- Some fetched pages were truncated by the fetch tool (OpAMP, OM 2.0, the pod
  lifecycle page, VES).

## 12. Key sources (all accessed 2026-10-22)

- JT-DMF and EBU: <https://www.amwa.tv/jtdmf> ; <https://tech.ebu.ch/groups/dmf> ;
  <https://tech.ebu.ch/files/live/sites/tech/files/shared/tech/tech3371.pdf> ;
  <https://github.com/ebu/pi-list> ; <https://tech.ebu.ch/groups/mcma> ; the
  DMF Reference Architecture white paper (section 3.1).
- AMWA: <https://github.com/AMWA-TV/bcp-008-01> ;
  <https://github.com/AMWA-TV/bcp-008-02> ;
  <https://github.com/AMWA-TV/nmos-control-feature-sets> ;
  <https://github.com/AMWA-TV/is-12> ; <https://github.com/AMWA-TV/ms-05-02> ;
  <https://github.com/AMWA-TV/ms-05-03> ; <https://github.com/AMWA-TV/is-07> ;
  <https://github.com/AMWA-TV/is-04> ; <https://github.com/AMWA-TV/is-14> ;
  <https://github.com/AMWA-TV/nmos-parameter-registers> ;
  <https://github.com/AMWA-TV/in-001> ; <https://github.com/AMWA-TV/in-003> ;
  <https://github.com/AMWA-TV/in-004> ; <https://github.com/AMWA-TV/in-006> ;
  <https://github.com/AMWA-TV/nmos-testing> ; <https://github.com/sony/nmos-cpp> ;
  <https://github.com/AMWA-TV/nmos-device-control-mock> ;
  <https://www.tvtechnology.com/infrastructure/amwa-and-ebu-to-host-demos-at-ibc-2026>.
- SMPTE, VSF, MXL, Ember+: <https://pub.smpte.org/latest/st2110-10/st2110-10-2022.pdf> ;
  <https://pub.smpte.org/latest/st2110-21/st2110-21-2022.pdf> ;
  <https://pub.smpte.org/latest/rp2110-25/rp2110-25-2023.pdf> ;
  <https://pub.smpte.org/latest/st2022-7/st2022-7-2019.pdf> ;
  <https://pub.smpte.org/latest/st2059-2/st2059-2-2021.pdf> ;
  <https://pub.smpte.org/doc/rp2059-15/20221110-pub/rp2059-15-2023.pdf> ;
  <https://www.rfc-editor.org/rfc/rfc8173.html> ;
  <https://www.rfc-editor.org/rfc/rfc8575.html> ;
  <https://vsf.tv/technical-recommendations/> ; <https://github.com/dmf-mxl/mxl> ;
  <https://github.com/Lawo/ember-plus> ; <https://github.com/prometheus/snmp_exporter>.
- Industry: the IAMT DSL PDF and summary in this folder ;
  <https://theiamt.org/groups/> ; <https://www.smpte.org/standards/st2138> ;
  <https://github.com/SMPTE/st2138-a> ; <https://github.com/SMPTE/st2126> ;
  <https://forge.etsi.org/rep/nfv/SOL006> ;
  <https://docs.onap.org/projects/onap-vnfrqts-requirements/en/istanbul/Chapter8/ves7_1spec.html>.
- Cloud native: <https://opentelemetry.io/docs/specs/status/> ;
  <https://opentelemetry.io/docs/specs/semconv/> ;
  <https://opentelemetry.io/docs/specs/otel/schemas/> ;
  <https://opentelemetry.io/docs/specs/opamp/> ;
  <https://github.com/open-telemetry/weaver> ;
  <https://prometheus.io/docs/instrumenting/exposition_formats/> ;
  <https://prometheus.io/docs/specs/om/open_metrics_spec_2_0/> ;
  <https://prometheus.io/docs/prometheus/latest/querying/api/> ;
  <https://prometheus.io/docs/practices/naming/> ;
  <https://prometheus-operator.dev/docs/api-reference/api/> ;
  <https://helm.sh/docs/chart_best_practices/custom_resource_definitions/> ;
  <https://github.com/cloudevents/spec> ; <https://github.com/xregistry/spec> ;
  <https://github.com/openconfig/reference> ; <https://openslo.com/> ;
  <https://github.com/slok/sloth> ; <https://artifacthub.io/docs/topics/annotations/helm/> ;
  <https://sdk.operatorframework.io/docs/overview/operator-capabilities/> ;
  <https://monitoring.mixins.dev/>.
