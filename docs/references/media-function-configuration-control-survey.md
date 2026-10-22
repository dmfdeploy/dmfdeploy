---
date: 2026-10-22
---

# Media function configuration control: a survey of open specifications

**What this is:** a survey of open specifications and open-source projects
that a software media function could use to declare its configuration
parameters, validate them before applying, confirm the applied state, and
announce changes. It covers the AMWA/EBU Joint Task Force on Dynamic Media
Facilities (JT-DMF), the AMWA NMOS family, other open industry work, broadcast
and cross-industry protocols, and cloud-native patterns.

**Status in dmfdeploy:** reference input only. This is a **Record** doc. It
decides nothing and schedules nothing. The RFC tracked in
[dmfdeploy/dmfdeploy#685](https://github.com/dmfdeploy/dmfdeploy/issues/685)
builds on it, together with the descriptor work in
[#634](https://github.com/dmfdeploy/dmfdeploy/issues/634). A companion note
covers [telemetry declaration](media-function-telemetry-declaration-survey.md).

**How to read it:** the survey is web research and reading. It made no code
changes. The project accessed every web source on 2026-10-22 unless a line
says otherwise. Each section separates **Facts** (with a source) from
**Judgment** (the project's reading). Where a claim comes from a secondary
read rather than the primary page, the text says "secondary". Where the
project could not verify something, the text says so, and section 11 collects
those items. Status strings for AMWA specifications come from each
repository's `spec.yml` on the default branch, which drives the rendered
specification site.

The method read AMWA and JT-DMF material directly from the AMWA-TV GitHub
repositories (`spec.yml`, docs, schemas, releases), from `specs.amwa.tv`,
`amwa.tv` and `tech.ebu.ch`. Wider-landscape claims were gathered separately
and are marked "secondary" where nobody read the primary page.

## Summary

- **NMOS already has a full configuration-control stack.** MS-05-02 declares
  typed parameters with three levels of constraints. IS-12 carries get, set
  and change notifications over WebSocket. IS-14 adds bulk backup, a dry-run
  validate (PATCH) and a restore (PUT) that returns a per-object result. All
  three are released as "AMWA Specification", with open implementations and
  test suites.
- **JT-DMF works on the deployment side.** Its public outputs are AMWA
  "Increments" (IN-001 to IN-006). IN-003 is a compute-resource manifest for a
  media function. It is Kubernetes-oriented, and its model has an operator
  with spec and status reconciliation. It does not declare configuration
  parameters: `spec.args` is an untyped array.
- **No open standard covers the whole chain** from a package descriptor to
  validated, read-back, monitored configuration of a containerised media
  function. dmfdeploy has to compose one.
- **Recommendation (judgment):** use MS-05-02 as the parameter model, IS-14
  for validate, apply and read-back, IS-12 for notifications, and BCP-008 for
  status. Carry a static copy of the function's MS-05 class and constraint
  declarations in `dmf-function.yaml`. Mirror the desired state in a
  Kubernetes custom resource whose controller is itself an NMOS controller,
  packaged as a platform function.

## 1. JT-DMF (Joint Task Force on Dynamic Media Facilities)

### Facts

- **What and who.** A joint task force run by AMWA and the EBU, announced on
  2025-09-13. It is open to vendors, end users and systems integrators. It has
  workgroups of EBU and AMWA members and a governance committee from both
  organisations.
  Sources: <https://www.amwa.tv/post/amwa-ebu-jt-dmf-dynamic-media-facility-task-force>,
  <https://tech.ebu.ch/news/2025/09/ebu-and-amwa-form-joint-task-force-on-dynamic-media-facilities-for-transition-to-software-based-media-production>.
- **Home pages.** AMWA: <https://www.amwa.tv/jtdmf>. EBU group page:
  <https://tech.ebu.ch/groups/dynamic-media-facility>, which lists two
  co-chairs, one from each of two public broadcasters (BBC and CBC). The
  working groups use Basecamp projects that are not public, and meet roughly
  weekly on Zoom.
- **Meetings.** Kick-off in Geneva, November 27 to 28, 2025 (about 110 people).
  North American kick-off in New York, March 10 to 11, 2026. Face-to-face in
  Geneva, June 8, 2026. Meet-up and "Ask Me Anything" sessions at IBC 2026.
  Sources: <https://tech.ebu.ch/news/2025/12/not-just-about-technology-jt-dmf-kicks-off-work-to-drive-dynamic-media-facilities-from-concept-to-production>,
  <https://tech.ebu.ch/news/2026/jt-dmf-north-american-kickoff-marks-progress-on-dynamic-media-facilities-dmf>,
  <https://www.amwa.tv/jtdmf/jt-dmf-meeting-jun2026>.
- **Four work tracks** (<https://www.amwa.tv/jtdmf>):
  1. End-to-End Synchronisation WG: one timing and synchronisation model.
  2. Compute Resources Management WG: how compute, storage, networking and
     media functions are provisioned, orchestrated, scaled and released.
  3. Flow Connection WG: how media flows are discovered, described,
     negotiated and connected. The EBU kick-off report names NMOS as an
     example control protocol here.
  4. Business Activity.

  The EBU group page marks all four tracks "partially done" for Q1 2026.
- **Published outputs are AMWA Increments.** The IN index says Increments
  "record incremental outputs of AMWA activity phases". The IN repositories
  say they are Draft Specifications under the AMWA IPR Policy and not a
  finalised specification. Their text is CC BY-ND 4.0, with no Apache licence
  file. Source: <https://specs.amwa.tv/in-index/>, repositories
  `AMWA-TV/in-001` to `AMWA-TV/in-006` (last commits 2026-10-20).

| ID | Title | Status (spec.yml) | Relevance to config control |
|---|---|---|---|
| IN-001 | API Requirements: Control of MXL v1.0 | AMWA Increment | High: requirements for a control API on MXL readers and writers |
| IN-002 | Time and Identity in the DMF | AMWA Increment | Low: identity of Sources and Flows |
| IN-003 | Compute Resource Management Manifest and Examples | Work In Progress | High: the closest thing to a media function descriptor |
| IN-004 | Flow Connection Phase 2 Requirements and Gaps | Work In Progress | High: static config file, notifications, monitoring |
| IN-005 | Principles of External Signal Ingress for DMF Media Workloads | Work In Progress | Low |
| IN-006 | DMF Business User Stories | Work In Progress | Low: licensing, scaling and portability stories |

**IN-001** (<https://specs.amwa.tv/in-001>, repository `AMWA-TV/in-001`):

- Scope: set and get `MXLFlowID` and `MXLDomainID` on readers and writers,
  start and stop them, list accessible domains, and expose state
  (`started`/`stopped`) and current transport parameters.
- "Invalid or inaccessible `MXLDomainID`s shall result in a validation error."
- Structured errors carry a code, a message and an optional remediation hint.
  "Partial updates shall not leave readers or writers in undefined states."
- Out of scope: "Control of processing parameters", and the domain-to-path
  mapping, which "must be configured when deploying the media function".
- Monitoring "will be defined in a future revision".
- It names no protocol. BCP-007-03 (below) is the NMOS answer for connection.

**IN-003** (<https://specs.amwa.tv/in-003>, repository `AMWA-TV/in-003`; the
same content also sits in `AMWA-TV/jt-dmf-crm`, Apache-2.0):

- Purpose: "a platform-agnostic way to declare the resources required by a
  Media Function": compute, memory, storage, network and accelerators.
- Architecture: a Media Functions tier defines "the overall Media Function
  Descriptor and the primary Manifests Schema". A Container Platform tier has
  "Operator(s)" that consume manifests and instantiate the workload, which
  emits "Media Function Metrics".
- It has a section "Level Trigger Pattern and Desired State Reconciliation"
  that describes a Kubernetes custom resource with Spec and Status and an
  operator control loop.
- Domain model: Media Function (a configured instance or session), Media
  Function Context (separates productions), and Media Function Config
  (cluster-wide shared components such as a licence server). The function
  specification names its "Control type (NMOS, etc.)" and "Transport (MXL,
  etc.)".
- Schema: `manifest/schema/resource_manifest_schema.yaml`, JSON Schema
  draft-07, `apiVersion` pattern `mxl.media.fn/v…`,
  `kind: MxlMediaFunctionParameters`. Fields: `role`, `inputs`/`outputs` with
  typed video and audio formats, and `requirements` (CPU in Kubernetes
  millicores, memory type and throughput, host capabilities, GPU, NIC,
  storage). The repository has a `validate_manifest.py`.
- **Configuration parameters are not declared.** `spec.args` is
  `type: array, items: {type: object}` with no further schema.
- Example: the repository holds an example manifest and a presentation
  (`JT-DMF-CRM-Riedel-Example.pdf`) for an MXL sink demonstration contributed
  by Riedel. It runs on kind with Kubernetes Dynamic Resource Allocation
  (`resource.k8s.io/v1` ResourceSlice for memory throughput) and needs
  Kubernetes v1.35 or later.

**IN-004** (<https://specs.amwa.tv/in-004>):

- For DMFs with only static connections, "media functions should provide a
  method to load a configuration file" in a given YAML shape "when the
  container is deployed". The shape has senders and receivers keyed by UUID,
  `master_enable`, and `transport_params` with `mxl_domain_id` and
  `mxl_flow_id` (`auto` allowed). It mirrors IS-05 staged and active
  parameters.
- When a writer changes a flow's technical parameters, it creates a new flow
  ID, and "the Media Function should notify the orchestration/control
  system".
- Media functions "must be able to run in non-privileged containers".
- Monitoring: a list of reader, writer and replication errors and counters.
  Candidate protocols: "NMOS IS-12, OpenTelemetry, ST 2138". Which items are
  mandatory is "TBD".

**EBU DMF Reference Architecture v2.0** (white paper, 2026-04-15, read from a
copy of the PDF; <https://tech.ebu.ch/dmf/ra>). Page numbers are PDF pages.

- Lifecycle "Configure: Configure and connect Media Functions. Change
  configuration as needed". "Monitor & Update: … Monitor whether configuration
  changes have the required effect on resources, for example does a Media
  Function have the correct parameters set" (p. 4). This is a read-back
  requirement in all but name.
- Container Platform: "Workload-specific configuration required for the
  Container is performed (for example using k8s control API)" (p. 13).
- Media Functions: "the configuration for the function packages is in a widely
  adopted format, for example Kubernetes typically uses Helm Charts" (p. 20).
- Media Functions Control: "Media Functions can be discovered, configured,
  connected and controlled using open APIs. Where appropriate this will build
  on work from the AMWA … NMOS" (p. 21). Monitoring runs "through open APIs".
- Application and UI: "AMWA IS-12 NMOS Control Protocol is an example of open
  specification based on WebSockets for live operation and status monitoring"
  (p. 21).
- Security: control and monitoring encrypted at least as well as TLS 1.3,
  clients authorised at least as well as OAuth2/JWT. "The approach used in
  NMOS and Catena (TLS 1.3 and OAuth 2.0) is suggested" for Media Exchange
  APIs.
- Open topics for JT-DMF: synchronisation, multi-vendor resource management in
  a cluster, dynamic connections during operation, and multi-cluster control
  and monitoring (p. 23).

### Could not find

- No JT-DMF requirements document on configuration of processing parameters.
  IN-001 explicitly excludes them.
- No public draft from the member workgroups beyond the IN repositories. The
  June 2026 agenda is published only as an image.
- No JT-DMF text on how a media function declares configuration, on package
  signing, or on a controller packaged as a function.
- No standalone "jt-dmf" repository (404). The only JT-DMF-named repository is
  `AMWA-TV/jt-dmf-crm`.

### Judgment

- IN-003 is close to dmfdeploy's `dmf-function.yaml` in purpose and shape
  (Kubernetes-style `apiVersion`/`kind`/`metadata`/`spec`). It is the natural
  upstream to align the resource part of the descriptor with, and the gap in
  `spec.args` is where a parameter declaration could be proposed.
- IN-004's deploy-time configuration file is a real requirement for static
  wiring. It shows that JT-DMF expects both a deploy-time file and a live
  protocol.
- IN-003 already assumes an operator with spec and status. That supports the
  idea of a controller packaged as a platform function.

## 2. AMWA NMOS beyond IS-04 and IS-05

AMWA spec repositories are Apache-2.0 for code and schemas. IS-14 prose also
carries a CC BY-ND 4.0 header. The survey did not confirm the dual licence for
every repository. Recent commits across all repositories (2026-10-14 to
2026-10-21) are a documentation-site migration with no content changes.

| Spec | Status | Latest release | Covers |
|---|---|---|---|
| MS-05-01 Control Architecture | AMWA Specification | v1.0.0, 2023-09-12 | Architecture for device models built from published classes; many controllers, no polling |
| MS-05-02 Control Framework | AMWA Specification | v1.0.0, 2023-09-12 | Class model: NcObject, blocks, workers, managers, descriptors, constraints |
| MS-05-03 Control Block Specs | Work In Progress | none (branch v1.0-dev) | "Blockspec" files that specify a block's members and constraints |
| IS-12 Control Protocol | AMWA Specification | v1.0.1, 2025-07-25 | WebSocket JSON transport for MS-05-02: commands, subscriptions, notifications |
| IS-14 Device Configuration | AMWA Specification | v1.0.0, 2025-08-26 | HTTP API: bulk get (backup), validate (PATCH), restore (PUT) |
| BCP-008-01/02 Receiver and Sender Status Monitoring | AMWA Specification | v1.0.0 each, 2025-08-26 | Standard monitor classes over MS-05-02 and IS-12 |
| INFO-006 Device Control and Monitoring guide | AMWA Specification | none | Implementation guide |
| NMOS Control Feature Sets | Continuing (register) | none | Opt-in MS-05-02 models: Identification, Monitoring, Device configuration |
| NMOS Parameter Registers | Continuing (register) | none | Capabilities, device control types, formats, tags, transports and more |
| IS-07 Event and Tally | AMWA Specification | v1.0.1, 2019-09-06 | Typed state and event messages over WebSocket or MQTT |
| IS-08 Audio Channel Mapping | AMWA Specification (Stable) | v1.0.1, 2020-07-22 | Map audio channels from inputs to outputs; branch v1.1-dev |
| IS-11 Stream Compatibility Management | AMWA Specification | v1.0.0, 2023-09-12 | Configure senders from receiver capabilities |
| IS-13 Annotation | Work In Progress | none | Write labels, descriptions and tags on IS-04 resources |
| BCP-002-01 Natural Grouping | AMWA Specification | v1.0.0, 2021-02-01 | Group hints in tags |
| BCP-002-02 Asset Distinguishing Information | AMWA Specification | v1.0.0, 2023-05-22 | Manufacturer, product, instance identification in tags |
| BCP-004-01 Receiver Capabilities | AMWA Specification | v1.0.0, 2021-04-09 | Constraint sets on receivers |
| BCP-004-02 Sender Capabilities | AMWA Specification | v1.0.0, 2026-03-02 | Constraint sets on senders |
| BCP-007-03 NMOS Support for MXL | AMWA Specification | v1.0.0, 2026-08-18 | IS-05 transport `urn:x-nmos:transport:mxl` |

Sources: <https://specs.amwa.tv/ms-05-02>, <https://specs.amwa.tv/is-12>,
<https://specs.amwa.tv/is-14>, <https://specs.amwa.tv/bcp-008>,
<https://specs.amwa.tv/nmos-control-feature-sets>,
<https://specs.amwa.tv/nmos-parameter-registers>,
<https://specs.amwa.tv/bcp-007-03>, and the matching `github.com/AMWA-TV/*`
repositories (releases and `spec.yml`). No `is-15` repository exists.

### How the control stack maps to the four capabilities (facts)

1. **Declare.** MS-05-02 `Constraints.md` defines three levels: datatype
   constraints (NcDatatypeDescriptor), property constraints
   (NcPropertyDescriptor in an NcClassDescriptor), and runtime constraints
   (NcPropertyConstraints on the object). A lower level overrides the one
   above but must not widen it. Method parameters have NcParameterConstraints.
   Controllers discover class and datatype definitions at run time over IS-12.
   MS-05-03 Blockspecs (work in progress) would let a function type publish
   its block layout and constraints ahead of time.
2. **Validate before apply.** IS-14 PATCH on
   `/rolePaths/{rolePath}/bulkProperties` validates a data set. "Devices MUST
   NOT make any changes to the device model when validating bulk properties"
   (`docs/API requests.md`), and devices "MUST perform the same checks" as a
   real restore (`docs/Backup & restore.md`). Modes: Modify (writeable
   properties only) and Rebuild (structural changes on rebuildable objects).
3. **Confirm applied state.** IS-14 PUT returns
   NcMethodResultObjectPropertiesSetValidation: one entry per object in scope,
   with status Ok or Failed and warning or error notices. GET bulkProperties
   returns the full state plus a vendor-defined `validationFingerprint`. The
   IS-12 generic Get reads single properties.
4. **Notify.** IS-12 Subscription messages list object IDs. The device sends
   Notification messages with NcPropertyChangedEventData. IS-14 has no
   notifications and points to IS-12.

**IS-04 advertisement.** IS-12 is advertised in the IS-04 Device `controls`
array as `urn:x-nmos:control:ncp/v1.0`, and IS-14 as
`urn:x-nmos:control:configuration/v1.0` (each specification's
`docs/IS-04 interactions.md`). Their entries in the Device Control Types
register were not checked in this survey.

**Feature sets register** (`feature_sets.yml`) has exactly three sets:
Identification (NcIdentBeacon), Monitoring (NcStatusMonitor,
NcReceiverMonitor, NcSenderMonitor and status datatypes), and Device
configuration (NcBulkPropertiesManager and the restore datatypes). No audio
or processing feature sets exist yet.

**AES70 lineage.** MS-05-01, MS-05-02 and IS-12 do not mention AES70 or OCA
anywhere in their text (grep of the cloned repositories). The class shape
(root object, blocks, workers, managers, object IDs, property-changed events)
is clearly similar, and AMWA presentations describe that link. The survey
found no normative statement of derivation.

### Open implementations (facts)

| Project | Owner | Licence | What it covers |
|---|---|---|---|
| nmos-cpp (<https://github.com/sony/nmos-cpp>) | Sony (open source) | Apache-2.0 | README lists IS-12, IS-13, IS-14, BCP-007-03, BCP-008-01/02, MS-05-01/02. No tagged releases; master pushed 2026-10-05 |
| AMWA NMOS testing tool (`nmos-testing`) | AMWA | Apache-2.0 | Suites IS-12-01, IS-14-01, BCP-008-01-01, BCP-008-02-01, MS-05, BCP-007-03-01; invasive tests sit behind `MS05_INVASIVE_TESTING`. Last tagged release 2022, so use master |
| nmos-device-control-mock | AMWA | Apache-2.0 | TypeScript device with MS-05-02, IS-12, BCP-008, IS-14 |
| nmos-js | Sony | Apache-2.0 | Browser IS-04/IS-05 controller |
| easy-nmos | third party | Apache-2.0 | Docker Compose bundle of registry, controller and test node |
| nmos-control-serpenty-device | third party | MIT | Example IS-12 device |

Source: `gh api` reads of each repository, 2026-10-22. Badge pass status and
nmos-cpp version numbers were not verified.

### AMWA work on packaging or cloud media functions

- No AMWA spec on media function packaging, Helm, signing or container images
  was found. IN-003 is the only item on deploying a media function.
- No NMOS-in-containers BCP and no "NMOS orchestration" spec was found.
- BCP-007-03 is released (v1.0.0, 2026-08-18). The project's archived
  make-vs-adopt review (2026-07-18) still calls it work in progress, so that
  review is now out of date on this point.

### Judgment

- For a function that already registers as an IS-04 Node, MS-05-02 plus IS-12
  plus IS-14 gives everything the brief asks for on the device side, in one
  coherent family. The gap is pre-deployment: these descriptors exist only
  once the function is running.
- IS-14 restore works on a whole data set. It fits configuration profiles and
  templates well. For one-off live changes, IS-12 Set is the right tool.

## 3. Other open, multi-vendor initiatives

### IAMT Dynamic Software Licensing (DSL) v1.0.0

Facts (from the project's
[summary of the IAMT document](iamt-dsl-v1-0-0-summary-and-relevance.md); the
PDF reading was secondary):

- Published 2026-09-07, Apache-2.0, 297 pages. It uses the DMF terms Media
  Function and Media Workload, but puts media functions themselves out of
  scope (section 02.02).
- Reusable shapes: a REST API (`POST /v1/leases`, renew, reissue, revoke,
  `POST /v1/usage-records`, `/.well-known/jwks.json`) with a referenced but
  not included OpenAPI file; RFC 9457 errors; Entitlement, Lease, Policy,
  Usage Event, Token Claims and Identity Evidence objects; a lease state model
  (Annex D); a `workId` correlation ID.
- Identity and capability: only an `app` string, and an entitlement scope that
  "may point to a product family, feature set, or structured catalog entry"
  (section 11.02). Typed licence dimensions (channels, frame rate, bandwidth,
  sessions) are checked before a lease is issued.
- No function descriptor, no feature-declaration schema and no configuration
  API.

Judgment: DSL is reusable for licensing only. Two patterns transfer: typed
dimensions checked before issue (an admission check), and the RFC 9457 error
model. If a DSL entitlement can point to a "structured catalog entry", the
dmfdeploy catalog entry is a good candidate target.

### IAMT, SMPTE RIS-OSA and Catena (SMPTE ST 2138)

Facts (secondary):

- The Open Services Alliance merged into SMPTE as a Rapid Industry Solution
  (RIS-OSA). <https://www.smpte.org/rapid-industry-solutions/osa>.
- **Catena, SMPTE ST 2138**: an open control framework that started as Ross
  Video openGear work. Parts: -00 overview, -10 model, -11
  gRPC, -12 REST, -19 protocol objects, -50 security. The documents seen are
  Public Committee Drafts dated 2025-09 to 2026-03, and -12 is a working
  draft. It is not yet published as a standard.
- Repositories: `github.com/SMPTE/st2138-a` (BSD-3-Clause, pre-FCD tags
  v1.1.0 and v1.1.1, latest 2026-10-19) and `github.com/rossvideo/Catena` (the Ross Video SDK,
  BSD-3-Clause).
- Model (verified from `st2138-a/interface/proto`): a device has params,
  commands and shared constraints keyed by OID. Types include INT32, FLOAT32,
  STRING, STRUCT, variants and arrays. Constraints include ranges with step
  and choice lists with a strict flag. Params can be read-only.
  `MultiSetValue` batches sets. `Connect` returns a stream of updates and
  `UpdateSubscriptions` selects them.
- No dry-run or validate-only RPC was seen.
- **SMPTE ST 2133 Job Processing Architecture**: Public Committee Draft, built
  on EBU MCMA. It groups services into jobs. It is not a function
  configuration spec.
- IAMT lists working groups on Dynamic Software Licensing, a Control Plane
  group that feeds SMPTE, and Catena (<https://theiamt.org/?p=3500>,
  <https://theiamt.org/?p=4701>). No published spec other than DSL was found.

Judgment: Catena is the only serious open alternative to MS-05/IS-12 for a
typed, self-describing parameter model. IN-004 names it ("ST 2138") as a
candidate monitoring protocol. It is still a draft, and it lacks the IS-14
validate and restore step. Watch it, and wait before building on it.

### Linux Foundation, EBU open source, MovieLabs, VSF

- **MXL** (<https://github.com/dmf-mxl/mxl>, Apache-2.0, Linux Foundation with
  EBU and NABA). v1.1.0 released 2026-09-09. A flow definition is an NMOS
  IS-04 flow JSON stored as `flow_def.json`. The only configuration is a
  domain-level `options.json` with URN keys. There is no control,
  orchestration or configuration API. IN-001 says "MXL does not define a
  control API".
- **EBU MCMA** (<https://github.com/ebu/mcma-libraries>, Apache-2.0): active,
  v2.0.0 on 2026-10-18. It is a job and service-registry model for file-based
  cloud workflows. It does not configure live functions.
- **EBU PI-LIST** (GPL-3.0): ST 2110 capture analysis, which is separate from
  configuration.
- **VSF**: TR-11 (GCCG transport and timing, draft), TR-12 (Client Device
  Discovery, 2026), `vsf-tv/gccg-api` (draft, Apache-2.0). None covers
  function configuration (<https://vsf.tv/technical_recommendations.shtml>).
- **MovieLabs**: Ontology for Media Creation and the 2030 Vision. They cover
  other topics than runtime configuration of functions (secondary, not
  fetched).
- No other Linux Foundation media project on function configuration was
  found.

## 4. Broadcast and media protocols

### AES70 / OCA

- **What:** AES standard for control and monitoring of networked media
  devices. Owner: Audio Engineering Society; promoted by the OCA Alliance.
  Editions AES70-2015, AES70-2023 (published January 2024), AES70-2024
  (announced October 2024). Free to implement.
  Sources: <https://ocaalliance.com/>,
  <https://www.prosoundweb.com/oca-alliance-announces-public-availability-of-aes70-2024/>.
- **Adoption:** strong in pro audio and live sound, where d&b audiotechnik,
  L-Acoustics and others adopted it (NDI joined in 2025).
  Little in video facilities.
- **Implementations:** AES70.js (DeutscheSoft, GPL-2.0, controller only), OCAMicro (C++
  device), SwiftOCA, and an open conformance test tool.
- **Capabilities:** typed properties with ranges, Get and Set, and
  property-changed events. No standard validate step was confirmed.

### Ember+

- **What:** open protocol from Lawo. Repository
  <https://github.com/Lawo/ember-plus>, Boost Software Licence 1.0. It defines
  the transport (Glow over S101) and a tree of nodes, parameters and
  functions, and leaves the tree's content to each device.
- **Adoption:** very wide in broadcast mixers, routers and monitoring.
- **Capabilities:** parameters carry type, access and enumerations. Min, max
  and format fields, and subtree subscriptions, are background knowledge and
  were not verified. No validate step.

### SNMP and MIBs

- IETF standard. SMIv2 gives ranges, sizes and enumerations. SET is atomic per
  PDU; traps and informs give notifications. This is background knowledge and
  was not fetched.
- In broadcast it is used for legacy device monitoring. No published SMPTE ST
  2110 MIB was found, which does not prove that none exists.

### SMPTE ST 2110 and ST 2059 management

- ST 2110-10 SDP describes a stream and leaves a function's configuration
  undescribed.
- No SMPTE PTP management MIB or YANG model was found. RP 2129:2023 is an
  inter-entity trust-boundary practice and defines no configuration API.
- JT-NM TR-1001-1 v1.1 (2020-11-11) sets node behaviour (DNS, DHCP, IS-04,
  IS-05, IS-09 system parameters). It defines no parameter model.

## 5. Cross-industry protocols

### NETCONF and RESTCONF with YANG (IETF)

- NETCONF RFC 6241 (2011) has a candidate datastore, a `validate` capability,
  confirmed commit with rollback, and locking. YANG-Push RFC 8641 (2019) adds
  on-change and periodic subscriptions. NMDA (RFC 8342) separates intended
  from operational state. Sources:
  <https://datatracker.ietf.org/doc/html/rfc6241>,
  <https://datatracker.ietf.org/doc/html/rfc8641>.
- **This is the most complete four-capability model anywhere**, and the best
  design reference. No broadcast YANG models were found.

### gNMI and OpenConfig

- OpenConfig is a vendor-neutral group led by network operators. gNMI spec
  0.10.0 (2023-05-25), reference code Apache-2.0. `Set` is one all-or-nothing
  transaction. `Subscribe` supports on-change. Schemas are YANG.
  Source: <https://github.com/openconfig/reference/blob/master/rpc/gnmi/gnmi-specification.md>.
- No validate-only mode was seen. No broadcast adoption.

### DMTF Redfish

- DMTF standard for server and hardware management. DSP0266 v1.24.0 in release
  2026.1 (2026-05-17). Schemas ship as CSDL, JSON Schema and OpenAPI. Settings
  resources with apply time, allowable values and an event service are
  background knowledge and were not verified. Relevant to layers 1 and 2 only.

### OPC UA

- OPC Foundation, IEC 62541 (several parts revised 2025). A typed,
  self-describing information model with companion specifications and
  subscriptions. open62541 is MPL-2.0. No broadcast adoption.
- It is the best cross-industry precedent for companion specifications, which
  is the role the NMOS Control Feature Sets register plays.

### ETSI NFV and Nephio (telecom analogy)

- ETSI NFV packages a network function as a signed package (SOL004) with a
  descriptor (SOL001 TOSCA, SOL006 YANG). Release 5 v5.1.1 was published in
  September 2024. Current versions were not verified.
- Nephio (Linux Foundation Networking) is active; Release 6 came out around
  February 2026. It configures network functions through Kubernetes resources.
- These are the closest precedent for "package plus configuration descriptor
  plus lifecycle". O-RAN O1 (NETCONF/YANG) was not researched.

## 6. Cloud-native patterns

- **Kubernetes CRDs.** Structural OpenAPI v3 schemas; CEL validation rules
  (`x-kubernetes-validations`) stable since v1.29, including transition rules
  with `oldSelf`; ValidatingAdmissionPolicy GA in v1.30; a status
  subresource; `metadata.generation` bumps on spec changes. Server-side
  dry-run (`dryRun=All`) runs validation and admission without persisting
  (background knowledge, which the project did not re-read). Source:
  <https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/>.
- **Operator pattern.** A controller watches a custom resource, reconciles
  managed objects, and writes `status` with conditions and
  `observedGeneration`. Operator Framework is CNCF incubating.
- **Helm `values.schema.json`.** Validated on install, upgrade, lint and
  template against the merged values. Source:
  <https://helm.sh/docs/topics/charts/>. Supported drafts were not confirmed;
  the docs example uses draft-07.
- **JSON Schema and OpenAPI.** OpenAPI 3.1 aligns with JSON Schema 2020-12;
  OpenAPI 3.2.0 was released 2025-09-19.
- **CNCF policy and GitOps.** Graduated: Kyverno (March 2026), Open Policy
  Agent, Crossplane (November 2025, trade press), Argo, Flux. KubeVela/OAM
  (incubating) declares component parameters in CUE. Argo CD and Flux report
  sync and health status and detect drift. Source:
  <https://www.cncf.io/projects/>. Gatekeeper's own status was not confirmed.
- **Limits.** All of this checks the Kubernetes object. None of it knows
  whether the running media function accepted the parameter. Argo CD "Synced
  and Healthy" means the manifests match. It says nothing about whether the
  function's internal state matches.

## 7. Comparison table

Legend: **Yes** = defined by the spec. **Partial** = possible but not
standardised, or limited. **No** = not provided. **?** = not verified.

| Item | Open? Owner | Broadcast adoption | 1. Declare types and constraints | 2. Validate before apply | 3. Confirm applied state | 4. Notify on change |
|---|---|---|---|---|---|---|
| MS-05-02 + IS-12 | Open, AMWA | Growing (multi-vendor BCP-008 demonstrations announced for IBC 2026) | Yes, three constraint levels, runtime discovery | No (IS-12 Set fails if invalid) | Yes, Get | Yes, subscriptions |
| IS-14 | Open, AMWA | Early (released 2025-08) | Yes, via descriptors | **Yes, PATCH dry run** | **Yes, per-object result + GET** | No (uses IS-12) |
| BCP-008 | Open, AMWA | Early, multi-vendor | Yes, fixed status classes | n/a | Yes | Yes, via IS-12 |
| IS-07 | Open, AMWA | Moderate (tally) | Partial, typed event state | No | Partial | Yes |
| IS-08 | Open, AMWA | Moderate | Partial, map constraints | Partial, staged/active | Yes, active map | No |
| IS-05 + BCP-004 (+ BCP-007-03) | Open, AMWA | High | Yes, transport constraints and caps | Partial, staging is rejected if invalid | Yes, `/active` | Partial, IS-04 version bumps |
| IS-13 | Open, AMWA (WIP) | None yet | Partial, labels and tags only | No | Yes | Partial, IS-04 |
| JT-DMF IN-003 | Open, AMWA/EBU (WIP) | Prototype | Yes for resources; **No for config params** | Partial, schema validation | No | No |
| Catena ST 2138 | Open, SMPTE (draft) | Early, Ross openGear | Yes, ranges, choices, read-only | No dry run seen | Yes, GetValue | Yes, streams |
| AES70 | Open, AES | Pro audio | Yes, typed properties with ranges | ? | Yes | Yes |
| Ember+ | Open protocol, Lawo | Very high | Partial, per-device trees, no shared schema | No | Yes | Yes |
| SNMP | Open, IETF | Legacy monitoring | Yes, SMIv2 | No | Yes | Yes, traps |
| NETCONF/YANG | Open, IETF | None found | Yes, YANG | **Yes, candidate + validate** | **Yes, operational datastore** | Yes, YANG-Push |
| gNMI/OpenConfig | Open, OpenConfig | None found | Yes, YANG | Partial, atomic Set | Yes | Yes |
| Redfish | Open, DMTF | Hardware only | Yes, JSON Schema | ? | Partial | Yes |
| OPC UA | Open, OPC Foundation / IEC | None found | Yes | ? | Yes | Yes |
| MXL | Open, LF/EBU | Early products | No (flow def only) | No | Partial, flow def | No |
| IAMT DSL | Open, IAMT | New | Licence dimensions only | Yes for licences | Yes for leases | Partial |
| K8s CRD + CEL + admission | Open, CNCF | Used by dmfdeploy and others | Yes, OpenAPI + CEL | Yes, server dry run, admission | Partial, `status` written by a controller | Yes, watch |
| Helm values.schema.json | Open, CNCF | Wide in K8s | Yes, JSON Schema | Yes, at install | No | No |
| Kyverno / Gatekeeper | Open, CNCF | n/a | No (the tools check policies and define no schemas) | Yes, admission | Partial, audit reports | Partial |
| Argo CD / Flux | Open, CNCF | n/a | No | Partial, diff | Partial, object drift only | Yes |

## 8. Recommendation for dmfdeploy (judgment)

This section is the project's judgment. It is a starting hypothesis for the
RFC in [#685](https://github.com/dmfdeploy/dmfdeploy/issues/685).

Context: ADR-0013 says a media function is a YAML manifest (intent) joined to
a NetBox runtime tag, and the console drives Configure and Finalise. ADR-0012
keeps Configure separate from Provision. ADR-0046 puts the lifecycle at
workload level. ADR-0047 requires a signed, digest-pinned package through a
generic declarative launcher that fails closed.

The combination the survey favours:

1. **Parameter model: MS-05-02.** In `dmf-function.yaml`, add a `control`
   section that names the function's MS-05 class IDs (standard and vendor),
   their property descriptors and datatype constraints, and the role paths
   operators may configure. This is a static copy of what the running device
   will publish over IS-12, so the console can render forms and the launcher
   can check values before deployment. Use the NMOS constraint vocabulary
   and avoid inventing a new one.
2. **Static check: JSON Schema generated from that section.** Generate a JSON
   Schema (and a Helm `values.schema.json` for deploy-time parameters) from
   the MS-05 declarations. Check it in CI when the package is signed
   (ADR-0047) and in the console before submit.
3. **Deploy-time parameters and live parameters.** Split them. Anything that
   needs a restart or a different pod shape goes through Helm values and the
   IN-003 resource manifest. Anything the function can change at run time
   goes through NMOS. IN-004's deploy-time file and IN-001's exclusion of
   processing parameters support this split.
4. **Admission check against live constraints: IS-14 PATCH.** Before applying
   a configuration profile, send it as an IS-14 validate. That checks against
   the device's runtime constraints (level 2), which a static schema cannot
   see.
5. **Apply and read-back: IS-14 PUT, then GET bulkProperties.** Record the
   per-object result and the `validationFingerprint`. Compare GET with the
   desired state. This answers the white paper's question "does a Media
   Function have the correct parameters set".
6. **Notifications and drift: IS-12 subscriptions and BCP-008 monitors.** An
   out-of-band change (an operator on another controller) shows up as a
   property-changed event. The controller then reports drift and leaves the
   value alone, unless the workload policy says to enforce.
7. **Kubernetes as the record of desired state.** A `MediaFunctionConfig`
   custom resource holds the desired profile, with CEL rules generated from
   the same declarations. Its `status` carries IS-14 results, the
   fingerprint, `observedGeneration` and conditions such as `Validated`,
   `Applied` and `InSync`. Argo CD or Flux can then show GitOps drift for the
   object, while the controller covers drift inside the function.
8. **Track for later:** Catena (ST 2138) as a second control binding, MS-05-03
   Blockspecs as the eventual source of the static declarations, and IN-003
   for the resource half of the descriptor.

Every capability above already has an open, released definition in NMOS, and
the project's descriptor can reference it. A bespoke parameter schema adds
cost and little else.

## 9. "Controller as a platform function" in NMOS terms (judgment, with facts)

Facts:

- In NMOS, a controller is a client. It reads the IS-04 Query API and calls
  device APIs (IS-05, IS-12, IS-14). Controllers do not register as Nodes,
  though nothing stops a controller process from also running a Node.
- MS-05-01 supports many simultaneous controllers with no polling. IS-12
  connections carry per-controller subscriptions and are lost on disconnect,
  so a controller must re-subscribe and re-read state after reconnecting
  (`is-12/docs/Protocol messaging.md`).
- Precedents for containerised controllers: easy-nmos runs the nmos-js
  controller, an nmos-cpp registry and a node in Docker Compose. The AMWA
  NMOS testing tool is a test controller that is commonly run as a container.
  IN-003 places "Operator(s)" in the Container Platform tier. Nephio
  configures network functions from Kubernetes controllers. The survey found
  no published open project that packages an IS-12/IS-14 configuration
  controller as a Kubernetes operator.

What the idea looks like:

- A `config-controller` platform function, packaged and signed like any other
  function (ADR-0047, `project` source). It is a Kubernetes operator that
  watches `MediaFunctionConfig` objects, and an NMOS controller that uses
  IS-04 Query to find the target device's `urn:x-nmos:control:ncp/v1.0` and
  `urn:x-nmos:control:configuration/v1.0` endpoints.
- Its own `dmf-function.yaml` declares a role such as `platform/controller`
  and requests BCP-003-02 OAuth scopes for IS-12 and IS-14 on the target
  functions. It needs no media inputs or outputs.
- It may itself expose an MS-05-02 device model (NcStatusMonitor for its own
  health) so the console monitors it with the same tooling. That makes it a
  Node with no senders or receivers, which NMOS allows.
- The console stops talking to function control APIs directly for profile
  changes. It writes desired state, and the controller validates, applies,
  reads back and reports. Live operator actions (one fader, one label) can
  still go straight over IS-12 from the UI, and the controller sees them as
  events.

## 10. Open questions

1. Where does the static parameter declaration come from: the vendor's
   package, an MS-05-03 Blockspec, or a capture from a running instance with
   IS-12 class discovery? How does the project detect drift between the
   declaration and what the device publishes?
2. Should dmfdeploy propose a typed `args` or `config` section to JT-DMF
   IN-003 instead of extending `dmf-function.yaml` on its own? This is
   external contact, so the project reviews the text first.
3. How do vendor-specific MS-05 classes get onto a catalog's trust path? Does
   the project require them in the signed package?
4. What does the controller do on drift: report only, or enforce? Is that a
   workload policy (ADR-0046) or a function policy?
5. With multiple controllers (the console, an automation system and a
   hardware panel may all write), is a lock or ownership convention needed?
   NMOS has none for IS-12 beyond authorisation scopes.
6. Which IS-14 restore mode (Modify or Rebuild) does the project allow, and
   who may use Rebuild?
7. Does the Configure stage (ADR-0012) end at IS-14 PUT success, or only after
   read-back and a BCP-008 "healthy" status?
8. How do IS-12 and IS-14 authorisation (BCP-003-02) fit the project's
   identity direction, given the ADR-0028 note that identity work is
   unsettled?
9. For functions without NMOS control (most today), is a thin adapter (Helm
   values to MS-05 facade) worth building, or does the project accept a
   restart-to-reconfigure path?

## 11. What the survey could not verify or find

- Rendered `specs.amwa.tv` status banners. Status strings come from
  `spec.yml`.
- A normative statement that MS-05 is derived from AES70.
- Whether IS-12 (`ncp`) and IS-14 (`configuration`) are in the Device Control
  Types register.
- Contents of unmerged AMWA branches (only names were listed). IS-12, IS-14,
  MS-05-02, BCP-008 and the feature-sets register show no work-in-progress
  branches.
- nmos-cpp version numbers and whether its IS-12 and IS-14 test badges pass.
- Any JT-DMF document beyond the IN repositories; the June 2026 agenda text.
- SMPTE ST 2138 final publication status, and whether Catena has a validate
  RPC.
- Any SMPTE PTP management MIB or YANG, or a ST 2110 MIB.
- EBU Tech 3371 v3.0, R 143 v3, R 148 and R 160 contents.
- Ember+ field-level details; AES70 constraint and validate semantics;
  Redfish settings and apply time; OPC UA current version; Gatekeeper, CUE,
  kpt and Porter CNCF status; current ETSI SOL versions.
- VSF GCCG API contents and AIMS work.
- IAMT's OpenAPI companion file and any other IAMT working-group output.
