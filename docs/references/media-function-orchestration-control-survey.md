---
date: 2026-10-22
---

# Media function orchestration and parameter control: a survey of orchestrators, translators and standards

**What this is:** a survey of who controls runtime parameters in media
facilities today. It covers commercial media orchestration and control
products, what the AMWA, SMPTE and EBU documents say about the controller role,
how protocol translators could expose legacy devices through the standard
contract, and three designs for the controller. It builds on the
[configuration control survey](media-function-configuration-control-survey.md)
and does not repeat it. A second companion note covers
[telemetry declaration](media-function-telemetry-declaration-survey.md).

**Status in dmfdeploy:** reference input only. This is a **Record** doc. It
decides nothing and schedules nothing. The RFC tracked in
[dmfdeploy/dmfdeploy#685](https://github.com/dmfdeploy/dmfdeploy/issues/685)
builds on it, together with the descriptor work in
[#634](https://github.com/dmfdeploy/dmfdeploy/issues/634). Vendor and product
names appear because this is a research reference. A product named here is
evidence about the market. It is not a design dmfdeploy follows.

## How to read this survey

- The project accessed every web source on 2026-10-22.
- Each claim carries a source-strength tag:
  - **[DOC]**: vendor technical documentation, a standard, or source code.
  - **[MKT]**: a press release, a product page, or a trade-press article.
  - **[NF]**: not found. The search found nothing. The item may still exist.
- **Judgment** is always labelled. Everything else is fact with a source.
- Method: the survey read these AMWA repositories directly: MS-05-01,
  MS-05-02, IS-12, IS-14, BCP-003-02 (both branches), BCP-008, INFO-006, the
  feature-sets register, and IN-001, IN-003, IN-004 and IN-006. It also read
  SMPTE `st2138-a`, the Skyline `dataminer-docs` repository, the EBU DMF
  Reference Architecture v2.0 PDF, and an AMWA deck from VSF VidTrans 2025.
- Four parallel research passes covered the vendors. Where a pass
  relied on a search summary and skipped the page itself, the text says "search
  summary".
- Vendor coverage is thin. Most broadcast control vendors keep their technical
  manuals behind customer portals, so section 1 has many [NF] tags. They are a
  finding in their own right: the public evidence that this problem is solved
  in practice is mostly marketing.

## Summary

1. **In practice, large driver libraries solve parameter control. Open
   contracts play a small part.** EVS Cerebrum ships "250 included protocols".
   Ross claims 200+. Nevion VideoIPath claims "100s of drivers". Lawo VSM,
   Skyline DataMiner and Evertz VistaLINK all work the same way. The device
   knowledge lives in the controller vendor's driver and stays out of the
   device and any descriptor. That is the lock-in the EBU DMF architecture
   aims to remove.
2. **Incumbents publicly stop at NMOS IS-04 and IS-05.** No orchestrator
   vendor's product documentation claims an IS-12 or IS-14 *controller*. The
   IBC 2026 BCP-008 demo lists ten vendors as *devices* reporting status. AMWA
   ran a "controller vendors" track at its November 2025 workshop, so
   controller support is coming. Nobody has shipped it publicly yet.
3. **Real systems stack controllers.** DataMiner orchestrates Grass Valley AMPP
   workloads and Techex modules. Cerebrum orchestrates Matrox ORIGIN. VSM
   exposes its own parameters northbound over Ember+ and SW-P-08. The
   "orchestrator over domain controllers" shape is the norm, so the platform
   has to plan for more than one controller.
4. **Standards assume many controllers and give no lock.** MS-05-01 says
   "multiple simultaneous Controllers are fully supported", coordinated or
   uncoordinated, and counts a front panel as one. Keeping in sync relies on
   change notifications and uses no locks. MS-05-02 defines a `Locked` (423)
   status code and no locking mechanism. The only standard tool for splitting
   authority is BCP-003-02's per-role-path read and write claims, and its IS-12
   and IS-14 sections sit on the unreleased `v1.1-dev` branch.
5. **AMWA's own framing splits the controller into two roles.** A 2025 AMWA
   deck puts IS-14 on a "provisioning and commissioning axis", driven by
   "Ansible, Chef, Puppet, facility controller, scripts etc.". It puts IS-12 on
   an "operational control & monitoring axis" driven by a "facility
   controller". IN-001 also separates the "orchestration system" (deploys) from
   the "control system" (sets parameters).
6. **No standard calls an orchestrator a media function.** IN-003 defines a
   Media Function as something that "produces and/or consumes ... live media
   streams". The EBU architecture puts control applications in the Application
   and UI layer, which the platform launches like other software. A controller
   is deployable, and the fitting names are application or platform function.
7. **No public Ember+ to IS-12 or SNMP to IS-12 translator was found.** The
   building blocks exist. IS-04 Nodes hold many Devices, each with its own
   `controls` entry. MS-05-02 has nested blocks with stable role paths. IS-14
   has rebuildable blocks. Catena (ST 2138) has first-class `slot` addressing,
   with slots added and removed on a live connection.
8. **Two refinements to the configuration control survey and the RFC draft.**
   IS-14's `validationFingerprint` records device hardware, software and
   firmware versions. It works as a compatibility check and cannot prove
   read-back, because it is no state hash. Also, Catena's SDK documents that
   range constraints *round* an out-of-range value and do not reject it, and
   DataMiner ignores out-of-range values. Silent coercion is common, so
   read-back has to compare values and cannot rely on a success code.
9. **Recommendation (judgment): design (c), with the platform defining the
   contract.** The function, or a translator in front of a device, declares
   MS-05, IS-12, IS-14 and BCP-008. Any conforming controller can drive it. The
   actuator seam routes intent to the controller that holds the write scope.
   The platform always keeps its own read-only observer, so evidence never
   depends on a third party's claim. dmfdeploy ships a small default controller
   so that (c) works on day one. Translators are ordinary functions under the
   same contract, with one extra field: a per-property evidence level.

## 1. Media orchestration and control products

### 1.1 Comparison table

Legend: **Yes**, **Partial** or **No** where the source supports it. The tag in
brackets says how strong the source is.

| Product | Parameter model | Read and write protocols | Validate and confirm | Driven by another system | Container or cloud | NMOS control (IS-12, IS-14, BCP-008) |
|---|---|---|---|---|---|---|
| Skyline DataMiner | XML connectors; typed read and write parameter pairs; `Range` element [DOC] | Per connector: SNMP, HTTP, serial, WebSocket; IS-04 registry connector [DOC] | Write overlays read; read value is the confirmed state [DOC] | Web Services API, User-Defined APIs [DOC, shallow read] | Packages on the AMPP App Store [MKT]; Kubernetes [NF] | [NF] |
| Nevion VideoIPath | Versioned drivers, for example `com.nevion.NMOS_multidevice-0.1.0` [DOC, third-party wrapper] | NMOS southbound; NETCONF/YANG and OpenConfig for networks [MKT] | [NF] | REST, Ember+, NS-BUS northbound [MKT]; External Driver API planned for 2026 LTS [MKT] | [NF] | Nevion in BCP-008 demo, product unstated [MKT] |
| Lawo VSM | Drivers into a parameter tree; GADGETs [DOC, MKT] | NMOS client driver: IS-04 Node API and IS-05 only, HTTP only, polling [DOC]; Ember+ driver [DOC] | Polling at a set interval [DOC] | Ember+ Gateway, SW-P-08 [MKT] | "Standard IT servers" [MKT] | [NF] |
| Lawo HOME | Apps and HOME-native devices [MKT] | IS-04, IS-05; JT-NM tested as controller and registry [MKT] | [NF] | HOME API used by VSM [MKT] | Microservices [MKT]; Kubernetes [NF] | [NF] |
| Grass Valley AMPP | Each app registers a schema of its controllable features [DOC, white paper] | AMPP Control: JSON over HTTPS REST [DOC] | [NF] | Yes, one REST endpoint for third parties [DOC] | Platform on Kubernetes; apps on GV Node Agent [DOC] | Not NMOS for control [DOC]; [NF] |
| Grass Valley GV Orbit | [NF] | IS-04, IS-05, BCP-002-01 [MKT] | Monitoring by exception [MKT] | [NF] | [NF] | [NF] |
| EVS Cerebrum | Device points, 250 protocols, default templates, salvos [DOC, product sheet] | Ember+, NMOS IS-04/05, SNMP, REST, Python API [DOC, product sheet] | Alarms and backup switching [MKT] | [NF] for own northbound API | Client/server, distributed [DOC]; containers [NF] | EVS in BCP-008 demo [MKT] |
| Evertz MAGNUM-OS, VistaLINK | SNMP-based device configuration [MKT] | SNMP; NMOS IS-04/05 controller [MKT] | SNMP alarms [MKT] | [NF] | Hybrid cloud [MKT]; containers [NF] | [NF] |
| Imagine Magellan SDNO | Database of sources, levels, channels, salvos [DOC, REST API PDF] | IS-04, IS-05, native APIs [MKT] | `ConnectionStatus` field [DOC] | SDNO REST API with OData-style queries [DOC] | COTS fabric, Magellan Cloud Connect [MKT] | [NF] |
| Riedel | [NF] | Riedel ARTIST is a tested NMOS node in Lawo's driver doc [DOC] | [NF] | "hi" human interface, vendor-agnostic [MKT] | MediorNet apps on COTS [MKT] | Riedel in BCP-008 demo [MKT] |
| AWS MediaConnect, MediaLive | Typed JSON API schemas [DOC] | REST and SDK [DOC] | 400 on semantic error; 202 async; Describe calls and best-effort EventBridge events [DOC] | Yes, API only [DOC] | Managed service | No NMOS in MediaConnect docs [NF] |
| NVIDIA Holoscan for Media | Media Gateway takes a GStreamer pipeline string [DOC] | NMOS through nmos-cpp registry and controller [DOC] | [NF] | NMOS [DOC] | Helm charts on OpenShift or Kubernetes [DOC] | [NF] |
| Ross DashBoard, Catena | JSON device models, typed parameters, constraints, templates [DOC, SDK] | Catena gRPC and REST [DOC] | Offline schema validation only; constraints round values [DOC] | gRPC, REST [DOC] | DevContainer [DOC]; Kubernetes [NF] | Not NMOS [NF] |
| Techex tx darwin | 60+ modules [MKT] | [NF] | [NF] | DataMiner xOps partnership [MKT] | [NF] | [NF] |
| Telestream | Not researched | | | | | |

### 1.2 Per product: the facts that matter

**Skyline DataMiner**

- Connectors (also called protocols) are XML. A parameter of type `write` "is
  typically used to create a write overlay of a read parameter". If
  `Param@setter` is true, "the value gets copied to the corresponding read
  parameter". [DOC]
  <https://github.com/SkylineCommunications/dataminer-docs/blob/main/develop/devguide/Connector/LogicParameters.md>
- The `Range` element gives `Low` and `High`. A value outside the range "will
  be ignored". It "is only intended to be used for communication parameters",
  and "From a QAction, it is possible to set a value that is outside of this
  range". [DOC]
  `develop/schemadoc/Protocol/Protocol.Params.Param.Interprete.Range.md` in the
  same repository.
- DataMiner can provision elements from an NMOS IS-04 registry through the
  "AMWA NMOS IS-04 Registry" connector. The IS-04 workflow "is no longer
  supported as of Process Automation 1.3". [DOC]
  `dataminer/Frameworks/IDP/Reference/Using_your_IS04_registry_to_provision_DataMiner_with_IDP.md`
  in the same repository.
- Northbound: Web Services API v1 and User-Defined APIs exist in the docs. The
  survey did not read them in depth. [DOC, shallow]
- DataMiner packages for AMPP "planning, scheduling and automated deployment of
  required AMPP workloads" (NAB 2026). [MKT]
  <https://www.sportsvideo.org/2026/04/20/nab-2026-skyline-communications-launches-dataminer-packages-on-grass-valley-ampp-app-store/>
- IS-12, IS-14 and BCP-008 connectors: [NF].

**Nevion VideoIPath (Sony)**

- A third-party Python package wraps the server API. It creates devices with a
  versioned driver ID such as `com.nevion.NMOS_multidevice-0.1.0`. [DOC, third
  party] <https://pypi.org/project/videoipath-automation-tool/0.8.4.dev409/>
- The 2026 LTS release adds an "External Driver API" so that "customers, system
  integrators and technology partners" can write drivers. Northbound: "REST
  API, Ember+, NS-BUS". [MKT]
  <https://www.advanced-television.com/2026/09/01/nevion-expands-videoipath-integration-capabilities/>
- Acts as an IS-04 registry and IS-05 controller. [MKT, older press]
- Official driver documentation, reservation and locking: [NF].

**Lawo VSM and HOME**

- The VSM "NMOS Client (Generic)" driver supports the IS-04 Node API "Partial"
  and IS-05 "Partial". It does not use the Registration or Query APIs. Devices
  come from a CSV file. Transport is HTTP only, with no WebSocket, so no IS-12.
  Read-back is by a "Subscription Poll Interval". [DOC]
  <https://docs.lawo.com/vsm-ip-broadcast-control-system/vsm-interface-driver-and-application-details/driver-supported-protocol-driver/driver-nmos-client-generic>
- VSM's optional Ember+ Gateway exposes "vsmStudio internal parameters to 3rd
  party controllers". [MKT] <https://lawo.com/products/vsm/>
- HOME passed JT-NM tests as an IS-04 and IS-05 controller and registry. [MKT]
  <https://www.sportsvideo.org/2022/09/06/t-nm-test-confirms-homes-amwa-nmos-compatibility-directout-soon-home-native/>
- Lawo sits on the MXL Technical Steering Committee (search summary of the EBU
  announcement). [MKT]

**Grass Valley AMPP and GV Orbit**

- AMPP white paper (read in full): "all applications running on AMPP register a
  schema with the AMPP Platform, which describes the features and functions
  that can be controlled, and this schema acts as both live documentation and
  provides the data needed to build a user interface". [DOC, white paper]
  <https://www.grassvalley.com/wp-content/uploads/2025/01/ampp_system_architecture_wp-pub-3-1039a-en.pdf>
- "AMPP Control was developed using the standard web-based mechanisms of JSON
  messages of HTTPS REST". Third parties "post the required payload to a single
  secure endpoint, specifying what the workload it is meant for". [DOC]
- "Grass Valley uses Kubernetes ... to manage its platform", about 100
  microservices. Customer apps run on GV Node Agent compute nodes. [DOC]
- The schema format and any apply confirmation: [NF].
- GV Orbit: IS-04, IS-05 and BCP-002-01 [MKT]. Anything on IS-12: [NF].

**EVS Cerebrum**

- Product sheet V2.8, January 2026: "You don't buy device specific drivers or
  licenses. Instead you buy a number of device points which you can use for any
  device, using any of the 250 included protocols." Protocols include Ember+,
  NMOS IS-04/05, SNMP "wrapped as a Generic Device", and REST. [DOC, product
  sheet]
  <https://evs.com/sites/default/files/2026-01/Cerebrum%20-%20product%20Sheet%20+%20protocol%20list%20V2.8.pdf>
- "Federation of multiple routemasters (sync shared virtual routing / locks)"
  and "Parallel multi-user configuration". This is the only product here that
  names locks. Semantics: [NF]. [DOC, product sheet]
- Cerebrum "adds orchestration and monitoring capabilities to MXL-based
  workflows" through Matrox ORIGIN. [MKT]
  <https://www.sportsvideo.org/2026/09/04/evs-and-matrox-video-announce-technology-partnership-for-dynamic-media-facility-deployments/>

**Evertz MAGNUM-OS and VistaLINK**

- VistaLINK PRO "Uses SNMP to manage and configure devices" and supports
  "hundreds of third party devices". [MKT] <https://evertz.com/solutions/vistalink/>
- MAGNUM-OS uses "NMOS and direct APIs", IS-04 and IS-05, and is a JT-NM tested
  controller. [MKT]
  <https://www.sportsvideo.org/2024/08/27/ibc-2024-evertz-shows-new-additions-to-its-software-defined-video-networking-solution/>
- Northbound API, IS-12, MXL, JT-DMF: [NF].

**Imagine Magellan SDNO**

- REST API v1.6 (April 2023) exposes a database model of sources, levels and
  channels, for example
  `GET {SDNO_IP}/api/system/activedb/sources?$expand=levels/channels`. [DOC]
  <https://imaginecommunications.com/content/uploads/2024/11/SDNO_REST_API_1.6_20230405-1.pdf>
- Write endpoints were not verified. IS-12, Ember+, MXL: [NF].

**Riedel**

- Riedel is one of ten vendors in the IBC 2026 BCP-008 demo and on the MXL
  TSC. [MKT]
- The IN-003 repository contains `examples/riedel-mxl-sink-demo`, a Riedel MXL
  sink on kind with Kubernetes Dynamic Resource Allocation. [DOC, read in the
  cloned repository] <https://github.com/AMWA-TV/in-003>
- MediorNet control model, MediorWorks API: [NF].

**AWS Elemental MediaConnect and MediaLive**

- `UpdateFlow` is `PUT /v1/flows/{flowArn}` and returns 202 (accepted,
  asynchronous). A semantic error returns 400. [DOC]
  <https://docs.aws.amazon.com/mediaconnect/latest/api/API_UpdateFlow.html>
- MediaLive: "you can edit or delete a channel only when it is not running".
  Runtime changes go through schedule actions, and in a batch, if one create
  fails, "they all fail". [DOC]
  <https://docs.aws.amazon.com/medialive/latest/ug/editing-deleting-channel.html>,
  <https://docs.aws.amazon.com/medialive/latest/ug/about-batch-update-schedule.html>
- Applied state is confirmed with Describe calls. EventBridge state-change
  events are delivered "best effort". [DOC]
  <https://docs.aws.amazon.com/eventbridge/latest/ref/events-ref-medialive.html>
- AWS is on the MXL TSC (search summary). NMOS: [NF].

**NVIDIA Holoscan for Media**

- Ships Helm charts for an NMOS registry (nmos-cpp), an NMOS controller UI, a
  Media Gateway, and PTP and network monitoring. Targets OpenShift or
  Kubernetes. [DOC]
  <https://catalog.ngc.nvidia.com/orgs/nvidia/teams/holoscan-for-media/collections/holoscan_for_media>
- The Media Gateway is configured with "a GStreamer pipeline passed to the
  container". That is a free-form string with no typed schema. [DOC]
- This is the clearest public precedent for an NMOS controller packaged as a
  Kubernetes workload.

**Ross DashBoard, openGear and Catena (ST 2138)**

- Catena is "based on lessons learned and experience with Ross Video's openGear
  platform". [DOC] <https://github.com/rossvideo/Catena>
- Range constraints are "rounded down to the nearest valid value". [DOC, SDK]
  <https://raw.githubusercontent.com/rossvideo/Catena/develop/docs/Constraints.md>
- Parameters can share a descriptor through `template_oid`. [DOC, SDK]
- In `SMPTE/st2138-a`, every device and parameter carries `uint32 slot = 1; //
  Uniquely identifies the device at node scope`. The service has
  `GetPopulatedSlots`. The connect stream carries `slots_added` and
  `slots_removed`. The push schema includes `invalidate_device_model` ("Inform
  the client that the device model has been invalidated"). [DOC, read in the
  cloned repository] <https://github.com/SMPTE/st2138-a>
- A search of `st2138-a/interface` for lock, exclusive, concurrent, validate and
  transaction found nothing relevant. So the interface files hold no lock and
  no validate-only call. [DOC, negative]
- Catena SDK security: the device only checks "whether a token is attached".
  [DOC, SDK, draft]

**Techex, Telestream, others**

- Techex tx darwin: "more than 60 modules", MXL integration, an orchestration
  partnership with DataMiner xOps. [MKT]
  <https://www.sportsvideo.org/2026/09/10/ibc-2026-skyline-communications-techex-accelerate-dynamic-media-facility-adoption/>
- The survey did not research Telestream. Vizrt, Cinegy, Sony Live System
  Manager, Qvest and others: [NF] in this pass.

### 1.3 What the products show (judgment)

1. **The driver is the product.** Every incumbent sells a library of
   per-device translations. Their device knowledge is proprietary and lives
   inside the controller. If dmfdeploy let a third-party orchestrator own
   parameters through its own drivers, the parameter model would again sit
   inside one vendor. Putting the declaration in the function's descriptor, as
   the RFC draft proposes, is the right counterweight.
2. **"Applied" means "read back", everywhere.** DataMiner writes and then
   copies to the read parameter. VSM polls. AWS returns 202 and asks you to
   Describe. Catena rounds silently. Nobody trusts the write acknowledgement on
   its own. The draft's rule, "applied only when the read-back matches",
   matches industry practice.
3. **The deploy-time and runtime split is universal.** MediaLive edits need an
   idle channel, and schedule actions run live. AMPP separates workload setup
   from live control. This supports the draft's `apply: runtime | restart`
   field and an adversarial review finding (P2) that the two paths need
   separate evidence.
4. **Self-describing schemas are winning.** AMPP's schema registration and
   Catena's device models do what MS-05-02 class discovery does. The industry
   is converging on "the function publishes its own model", which the
   `parameters` block mirrors statically.
5. **Controllers are stacked.** DataMiner over AMPP, Cerebrum over ORIGIN, VSM
   exposing Ember+ northbound. A dynamic media facility will contain a
   facility orchestrator, domain controllers, panels and the platform at once.
   A design for one controller would struggle in a real facility.
6. **Locks are rare and proprietary.** Only Cerebrum names them. NMOS defines
   none. Ownership has to come from the platform's own authority model.

## 2. Standards trajectory

### 2.1 Vendor support for NMOS control and related work

| Vendor | IS-12 | IS-14 | BCP-008 | Ember+ to NMOS bridge | ST 2138 Catena | MXL | JT-DMF, AMWA, EBU |
|---|---|---|---|---|---|---|---|
| Sony, Nevion | nmos-cpp implements it (Sony open source) [DOC] | nmos-cpp [DOC] | Demo vendor, IBC 2026 [MKT] | [NF] | [NF] | MOXELA and M2L-X over MXL (search summary) | Sony maintains nmos-cpp |
| EVS | [NF] | [NF] | Demo vendor; pre-show interop at EVS in Belgium [MKT] | [NF] | [NF] | Through Matrox ORIGIN [MKT] | [NF] |
| Riedel | [NF] | [NF] | Demo vendor [MKT] | [NF] | [NF] | MXL TSC; IN-003 example [DOC] | IN-003 contributor [DOC] |
| Pebble, Simplexity, Arkona, DirectOut, Leader, Providius | [NF] for products | [NF] | Demo vendors [MKT]; Simplexity is NMOS Control project lead [MKT]; Pebble leads the workshop [DOC] | [NF] | [NF] | | AMWA leads |
| Grass Valley | [NF] | [NF] | [NF] | [NF] | [NF] | MXL implementer and TSC (search summary) | [NF] |
| Lawo | [NF] | [NF] | [NF] | [NF] | [NF] | MXL TSC (search summary) | [NF] |
| AWS, NVIDIA | [NF] | [NF] | [NF] | [NF] | [NF] | MXL TSC (search summary) | [NF] |
| Ross | [NF] | [NF] | [NF] | [NF] | Originator [DOC] | | SMPTE RIS-OSA |
| Skyline, Evertz, Imagine | [NF] | [NF] | [NF] | [NF] | [NF] | [NF] | Skyline says xOps is "aligned with" DMF [MKT] |

Sources:

- BCP-008 demo article. It names only BCP-008, describes the products as
  devices "reporting device status consistently", and does not mention IS-12,
  IS-14, JT-DMF or controllers. [MKT]
  <https://www.sportsvideo.org/2026/08/12/ibc-2026-amwa-and-ebu-to-demo-nmos-bcp-008-multi-vendor-ip-status-reporting/>
- AMWA workshop page: Porto, 24 to 26 November 2025, covering "NMOS Control,
  Config and Minimum Status Reporting (IS-12, IS-14, BCP-008-01, BCP-008-02)",
  with a track for "Controller vendors looking to add support for
  IS-12/BCP-008", and "a tested event prior to NAB". [DOC]
  <https://go.amwa.tv/nmos-workshop>
- nmos-cpp README (see the
  [configuration control survey](media-function-configuration-control-survey.md)).

One conflict to flag: The Broadcast Bridge calls IS-14 "Draft". The AMWA GitHub
release v1.0.0 (2025-08-26) and `spec.yml` say "AMWA Specification". The
release record was checked directly, so the trade-press article is out of date.
<https://www.thebroadcastbridge.com/content/entry/21347/broadcast-standards-the-nmos-standards-deep-dive>

### 2.2 Who the controller is, according to the documents

**MS-05-01 (Control Architecture, v1.0.0)** [DOC], `docs/Core Mechanisms.md`:

- "NCA supports the use of multiple simultaneous Controllers. Those Controllers
  might be coordinated - when a system has redundant Controllers, for example -
  or they might be uncoordinated - for example, when a system includes
  Controllers from multiple manufacturers."
- "A common multiple Controller case arises when a network-controlled device
  includes a non-blank front panel. The front panel is a separate Controller."
- "PropertyChanged is the key mechanism for NCA's support of multiple
  Controllers without polling ... a Controller can stay in sync with the device,
  even when those properties are being changed by other controllers."
- Scope: "NCA's purpose is device control (and status monitoring) only. NCA
  does not define higher-level mechanisms such as ... facilities reservations."
  (`docs/Scope.md`)

**MS-05-02 (Control Framework, v1.0.0)** [DOC]:

- `NcMethodStatus` includes `"Locked", // 423 Addressed object is locked`.
  Nothing else in MS-05-02, IS-12, IS-14, BCP-008 or the feature-sets register
  defines how an object becomes locked. A search of all of them for "lock"
  finds only this status code and PTP "locked" states.
- `NcPropertyChangedEventData` has `propertyId`, `changeType`, `value` and
  `sequenceItemIndex`. It names no controller as the source of the change. A
  controller can see that a value changed and cannot see who changed it.

**IS-12 (Control Protocol, v1.0.1)** [DOC]:

- A command message has `handle`, `oid`, `methodId` and `arguments`. There is
  no field for the requesting user or the originating system.
- Authorization is by BCP-003-02 tokens on the WebSocket connection.

**BCP-003-02 (Authorization in NMOS Systems)** [DOC]:

- The `v1.1-dev` branch (last commit 2025-07-02) has IS-12 and IS-14 sections.
  Tokens carry an `x-nmos-control` claim with `read` and `write` lists of role
  paths, for example `"write": ["root.receiver-monitors.monitor-01"]`. "Access
  to modify object properties MUST only be given if the token claim includes a
  write claim with a role path that includes the object."
- The released `v1.0.x` branch (v1.0.0) has no IS-12 section (search count 0).
  So per-role-path control authorization is unreleased.

**IS-14 (Device Configuration, v1.0.0)** [DOC]:

- "Backup validation fingerprint is an optional string ... that can be used to
  capture the various versions of the hardware, software and/or firmware that
  made up a device at the time the backup was performed." It is no state hash.
  IS-14 has no conditional restore and no precondition token, so two
  controllers restoring at once is undefined.

**INFO-006 (Device Control implementation guide)** [DOC]:

- Controllers are expected to discover the device model, use the class
  manager, subscribe to the objects they care about, and decode touchpoints. It
  says nothing about multiple controllers or ownership.

**IN-001 (Control of MXL v1.0)** [DOC]:

- "The API enables a control system to: Set parameters ... Query their current
  status."
- "MXLReaders and MXLWriters are part of Media Functions deployed by an
  orchestration system."
- "The FlowID of a writer is not created by the control system. It is created
  either by: The orchestration system, or The writer itself."
- So IN-001 names two parties, an orchestration system and a control system. It
  assumes one control system and says nothing about several.

**IN-004 (Flow Connection Phase 2)** [DOC]:

- Uses the joint term "orchestration/control system" as the party that
  functions notify about new flows.
- Static configuration exists "To be able to create DMFs with only static
  connections that do not require a separate realtime control system".
- It mentions "a gateway media function" whose input signal may change. That is
  a media gateway and does not translate control.

**IN-003 (Compute Resource Management, WIP)** [DOC]:

- Tiers: an "Application and UI Tier" of "Media Workloads composed of one or
  more modular Applications", a Media Functions tier, a Container Platform tier
  with "Operator(s)", and cross-tier "Orchestration & Monitoring".
- A Media Function "produces and/or consumes a tightly coupled group of one or
  more live media streams". Its specification names a "Control type (NMOS,
  etc.)".
- "Media Function Config" covers "cluster-wide configuration and deployment of
  high-level components, such as a database or license server".
- It allows "Multiple Media Function instances per pod, where a logical Media
  Function instance is an independently configured session/channel/task".

**EBU DMF Reference Architecture v2.0 (2026-04-15)** [DOC], pages 20 to 22:

- Media Functions layer: "Media Functions can be discovered, configured,
  connected and controlled using open APIs."
- Application and UI layer, Control: "Automation applies changes to Media
  Functions to corresponding to live user operations through a UI or
  pre-prepared operations, e.g. based on a schedule."
- Application and UI orchestration: "Provision: Launch Applications and UIs.
  Configure: Configure the Applications and UIs."
- Container orchestration: "Currently this assumes a single Container
  Orchestration."

**AMWA deck, VSF VidTrans 2025** (AMWA and Pebble presenters) [DOC]: the NMOS
control presentation on the event page, <https://vsf.tv/2025-vsf-vidtrans25/>.

- Slide 18: IS-14 "Provisioning", driven by "Ansible, Chef, Puppet, facility
  controller, scripts etc.".
- Slide 19: two axes. A "Provisioning and commissioning axis" with a
  provisioning tool and IS-14. An "Operational control & monitoring axis" with
  IS-12 and a "Facility controller".
- Slide 20: "IS-12 is very simple" and "it's a thin wrapper around the models",
  followed by the claim that you can build another protocol in a couple of
  hours. The slide joins the two phrases with an en dash, which this note
  replaces with quotation marks.

### 2.3 What this adds up to

**Facts:**

- No standard or Increment read for this survey defines controller
  arbitration, ownership or locking. MS-05-01 explicitly expects several
  uncoordinated controllers and relies on notifications.
- The only standard partition of write authority is BCP-003-02's per-role-path
  claims, and its IS-12 part is unreleased.
- Change notifications carry no writer identity.
- No standard or Increment describes an orchestrator or controller as a
  deployable *media function*. The EBU architecture describes control
  applications that the platform launches, in the Application and UI layer.
  IN-003's Media Function definition requires media streams.

**Judgment:**

- The standards point to design (c). AMWA's own deck shows a provisioning actor
  (which can be "Ansible ... facility controller, scripts") and a facility
  controller as two roles over one device model. That is a contract with
  several possible drivers.
- "Orchestrator media function" is the wrong name. In IN-003 and EBU terms it
  is an Application (or a platform component). Using "media function" for
  something with no media streams would confuse JT-DMF readers.
- Arbitration is a platform problem. The standards leave it open, and the
  platform already has an authority model.

## 3. Protocol translators

The goal is maximum compatibility and extensibility. A translator function
exposes a device, or many devices, that speak Ember+, SNMP, vendor REST or
another protocol, through the standard contract.

### 3.1 Existing translators and gateways

| Item | What it does | Status |
|---|---|---|
| Ember+ to IS-12 bridge, open or commercial | | [NF]. GitHub repository and code searches for Ember+ with NMOS or IS-12 returned nothing relevant |
| SNMP to IS-12 bridge | | [NF] |
| AMWA work item on Ember+ or AES70 mapping | | [NF] in IS-12 and MS-05-02 issues |
| Lawo VSM Ember+ Gateway | Exposes VSM internal parameters to third parties over Ember+ | [MKT] |
| VideoIPath | "enable NMOS senders or receivers to connect with non-compliant devices"; "100s of drivers" | [MKT] <https://broadcastbeat.com/news/nevion-enhances-videoipath-system-with-nmos-discovery-registration-and-connection-management> |
| DataMiner | IS-04 registry connector provisions nodes into DataMiner (southbound mediation; it does not expose NMOS) | [DOC] |
| EVS Cerebrum | "SNMP wrapped as a Generic Device" | [DOC, product sheet] |
| Tieline codecs | Run NMOS and Ember+ side by side: NMOS for discovery and connection, Ember+ for finer control | [DOC, vendor article] <https://tieline.com/controlling-codecs-with-nmos-and-ember/> |
| SMPTE Motion Imaging Journal paper | Prototype using Ember+ and NMOS IS-08 together, on control-protocol lock-in | Title seen only <https://journal.smpte.org/periodicals/SMPTE%20Motion%20Imaging%20Journal/132/5/13/> |
| Four small GitHub repositories named `shure-nmos-bridge`, `aes67-nmos-bridge`, `nmos-bridge` and `mxl-nmos-bridge` | Unknown, empty descriptions | Unverified hints only. The survey omits the owner accounts and links |

Translation is a feature *inside* controllers today. The survey found no
standalone translator that exposes legacy devices through IS-12.

### 3.2 Building blocks the standards already give a translator

- **IS-04: one Node, many Devices.** A Node can register several Devices. Each
  Device has its own `controls` array, and IS-12 says "Devices MUST include the
  `urn:x-nmos:control:ncp` control type". So a translator can register one
  IS-04 Device per downstream target, each with its own IS-12 `href`. [DOC]
  `is-12/docs/IS-04 interactions.md`
- **MS-05-02 nested blocks.** "An object in a hierarchy of nested blocks MUST
  be uniquely identified by its role path which MUST be persisted across device
  reboots." Blocks expose `members` and `FindMembersByPath`, `ByRole` and
  `ByClassId`. [DOC] `ms-05-02/docs/Blocks.md`
- **MS-05-02 touchpoints** link control objects to IS-04 and IS-08 resources.
  [DOC] `ms-05-02/docs/NcObject.md`
- **MS-05-02 class lineage.** Vendor classes extend standard ones, and INFO-006
  expects controllers "to use the class identity lineage information" to handle
  non-standard classes. A translator can publish a vendor class per device
  type. [DOC]
- **IS-14 rebuildable blocks.** If a block is rebuildable, "its members can be
  added or removed". That fits a translator whose downstream inventory changes.
  [DOC] `is-14/docs/Backup & restore.md`
- **Catena slots.** One Catena service fronts many device models by slot, with
  slots added and removed live and a push to invalidate a device model. [DOC]
  `st2138-a/interface/proto`
- **IN-003 `[N..1]`.** Several logical Media Function instances per pod is an
  accepted deployment pattern. [DOC]
- **The model carries most of the work.** AMWA's own deck says IS-12 is "a thin
  wrapper around the models". A translator's main job is to map a device onto
  MS-05-02 classes, and the protocol on top is the easy part. [DOC]

### 3.3 What the contract and descriptor need for translators (judgment)

1. **A role.** The descriptor declares `role: translator` (control plane only,
   no media ports). It lists southbound protocols (`emberplus`, `snmp`,
   `http-vendor:<name>`) and the northbound contract it offers (`nmos-is12`,
   `nmos-is14`, `nmos-bcp008`).
2. **Targets, one translator to many.** Each target becomes its own IS-04
   Device with its own IS-12 endpoint. That keeps one identity, one
   BCP-003-02 claim scope and one NetBox instance per target. Nested blocks
   under one Device are the fallback when a vendor cannot split endpoints.
3. **Static where possible, dynamic where needed.** Each target type has a
   *profile*: a static `parameters` declaration for one device type (for
   example "Vendor X router, firmware 4.x"), shipped and signed with the
   translator package. Dynamic discovery (walking an Ember+ tree or an SNMP
   MIB) is allowed and produces an *undeclared* model. The platform shows those
   values and withholds validated-profile behaviour until a profile exists. The
   conformance tool can generate a draft profile from a discovery capture,
   which a human then reviews and signs.
4. **Per-property evidence level.** Translators cannot always prove what native
   functions prove. Each property declares:
   - `validate: device | translator | none`. Did the device itself check it, or
     only the translator's static constraints?
   - `readback: device | cached | none`. Is the read a fresh southbound read
     after the set, a cached echo, or impossible (write-only SNMP objects,
     Ember+ functions)?
   - `notify: device | poll:<interval> | none`. Ember+ subscriptions are
     native. SNMP usually means polling.
5. **Link health as telemetry.** Each target exposes BCP-008-style status for
   the southbound link (connected, degraded, lost), plus the translator's own
   health. A lost southbound link must never look like a healthy device.
6. **Target binding from NetBox.** Targets come from NetBox (instances and
   addresses) and the translator's own config holds none. That keeps one source
   of truth and lets the closed-loop model flag a "presence delta" when a
   target is configured and does not answer.

### 3.4 Keeping validation and read-back provable through a translator (judgment)

- **IS-14 validate** through a translator proves only what the property's
  `validate` level says. The console labels a `translator`-level validation as
  "checked against the declared profile". Only `device`-level validation reads
  "accepted by the device".
- **Read-back** counts as proof only at `readback: device`, and only from a
  fresh read *after* the set, with a timestamp later than the set. The
  translator must never answer a Get from the value it wrote moments earlier. The
  conformance tool tests this with a southbound simulator that deliberately
  coerces or refuses a value. The translator must report the device's value.
- **Coercion is normal.** Catena rounds and DataMiner ignores out-of-range
  values. The platform compares the normalised read-back with the request and
  records "coerced" as its own outcome, separate from "applied" and "failed".
- **Write-only properties** (`readback: none`) can only reach "sent". The
  console never calls them applied, which is the same rule the draft already
  uses for functions with no NMOS control.
- **Certification tier**: run the NMOS Testing Tool IS-12 and BCP-008 suites on
  the translator's northbound side. Run a recorded southbound session against a
  simulator (an Ember+ provider, an SNMP agent) to prove the mapping.

### 3.5 How a translator fits each design (judgment)

- **(a) Platform controller.** The translator is one more IS-12 device.
  This is the cleanest fit. The platform controller needs no knowledge of any
  legacy protocol.
- **(b) Third-party orchestrator.** Third-party orchestrators already have
  native drivers, so they would likely skip the translator and talk Ember+ or
  SNMP directly. The platform then loses its view of the device unless the
  orchestrator reports back. The translator becomes redundant or a second,
  competing writer.
- **(c) Contract plus any controller.** The translator is the point where all
  controllers meet. The platform controller, a facility orchestrator and a
  panel can all use the same IS-12 surface, and the platform observes all
  changes. This only works if third-party controllers are required to use the
  contract for targets the platform manages.

## 4. Synthesis: three designs compared

Context: the platform keeps a backend-agnostic actuator seam in every design
(closed-loop assurance plan, gap 4: "Deploy and drift actions go through one
interface, so the loop keeps working if the workflow engine changes").

### 4.1 The designs

- **(a) Platform-owned controller.** dmfdeploy builds and runs the only
  controller behind the actuator seam. It does IS-14 validate and restore,
  IS-12 Set and subscribe, and BCP-008 monitoring.
- **(b) Third-party orchestrator as the controller.** A vendor orchestrator
  (DataMiner, Cerebrum, VideoIPath, or a future IS-12 controller) plugs in
  through a standard interface and owns runtime parameters. The seam forwards
  intent to it.
- **(c) Both, under a platform contract.** The function or translator declares
  MS-05, IS-12, IS-14 and BCP-008 control. Any conforming controller can drive
  it. The seam routes intent to whichever controller holds the write scope for
  that target. The platform keeps a read-only observer on every target.

### 4.2 Comparison

| Criterion | (a) Platform controller | (b) Third-party orchestrator | (c) Contract plus any controller |
|---|---|---|---|
| Alignment with standards | Good. Uses MS-05, IS-12, IS-14 as written | Weak today. No orchestrator vendor documents an IS-12 or IS-14 controller; they would use their own drivers | Best. Matches MS-05-01's multiple controllers, AMWA's provisioning and operational axes, IN-001's two parties, and EBU's launched control applications |
| Descriptor must declare | `parameters`, `telemetry`, control endpoints | Little. The orchestrator's driver holds the model, so the descriptor may be bypassed | `parameters`, `telemetry`, control endpoints, evidence levels, and for translators the targets and profiles |
| Provable validate and read-back | Yes. The platform does every step | Only if the orchestrator reports evidence. No standard report format exists | Yes. The platform observer reads the device itself with a read-only claim, whoever wrote |
| Authority and identity | Clear. The platform records the requesting human at the seam | Weak. IS-12 carries no user field, and the orchestrator has its own user model | Clear at the seam for platform-routed intent. Third-party writes are attributed to the controller's identity, and the observer flags them |
| Arbitration with two controllers | Not designed. A second controller (a panel, a facility system) still appears in practice | Inherits the orchestrator's locks, if any (only Cerebrum names them) | Platform assigns write scopes per target or role path. Others get read only. Out-of-scope changes show up as deltas |
| What dmfdeploy builds | Controller, observer, schema tooling | Adapter to one vendor's API; evidence import | Small default controller, observer, scope assignment, schema and conformance tooling |
| Translator fit | Clean | Poor, often bypassed | Clean, and the translator is where controllers meet |
| Lock-in risk | Low, but dmfdeploy becomes a controller vendor | High: the driver library holds the model | Low |
| Effort to first value | Medium | Low if you already own the orchestrator | Medium. (a) is a subset, so you build (a) first |

### 4.3 Points the RFC must settle under (c) (judgment)

1. **Write scope is a platform grant.** For each target, and optionally each
   role path, the platform records which controller may write. It enforces this
   by issuing BCP-003-02 style tokens with `x-nmos-control` write claims only
   to that controller. Until BCP-003-02 v1.1 is released and functions
   implement it, enforcement is advisory and the observer catches violations.
2. **One writer per scope at a time.** The scope is a lease that the platform
   moves between controllers, for example from the facility orchestrator to the
   platform controller during a show change-over. That is the arbitration
   mechanism. It uses the platform's existing authority path and needs no
   protocol lock.
3. **The observer is always the platform's.** It holds a read-only claim on
   every managed target, subscribes over IS-12, and records every change. This
   keeps evidence provable in (b) and (c). It is also the "IS-12 to Prometheus
   bridge" the draft asks about, so the two can be one component.
4. **Human attribution lives at the seam.** IS-12 has no user field and
   notifications have no writer field. So the seam records the requesting human
   for every intent it routes. For a third-party controller, dmfdeploy can only
   attribute changes to the controller's identity unless that controller passes
   an on-behalf-of identity. Requiring that is a reasonable admission condition
   for third-party controllers, though NMOS does not standardise it.
5. **Naming.** Call a third-party controller a "control application" (EBU
   Application and UI layer, IN-003 Application tier). Call a translator a
   "translator function". Reserve "media function" for functions that handle
   media streams.
6. **Third-party controllers are packaged like anything else.** A control
   application ships as a signed package with a descriptor that declares
   `role: controller`, the write scopes it requests, and the contract it
   speaks. The ADR-0047 separate-ADR requirement for operator install paths
   still applies.

### 4.4 Recommendation (judgment)

Choose **(c)**, and build it as (a) first.

- **The contract is the product.** Every incumbent hides the parameter model in
  a driver. dmfdeploy's contribution is to put that model in the descriptor,
  in MS-05 terms, so any controller can use it. That is also the most useful
  evidence to share upstream with JT-DMF later (with project approval).
- **Ship a small default controller.** It does IS-14 validate and restore,
  IS-12 Set and Get, and BCP-008 monitoring for platform-routed intent. Without
  it, (c) has nothing to route to on day one. This also answers an adversarial
  review finding (P1): the controller can start as a worker that AWX invokes
  through the actuator seam, so AWX stays the actuator under ADR-0025,
  ADR-0037 and ADR-0043. Moving the actuator role would then be a later,
  separate ADR.
- **Ship the observer as its own component.** It is read-only, so it carries
  less risk than the controller and can come first. It gives the closed-loop
  model its configuration and media-health deltas even before any controller
  writes.
- **Make translators first-class, starting with Ember+.** Ember+ is the most
  widely used legacy control protocol in this survey, and the survey found no
  published Ember+ to IS-12 translator. A reference Ember+ translator with one
  device profile would prove the evidence-level model. SNMP follows the same
  pattern with `readback` and `notify` set to polling.
- **Admit third-party controllers by scope.** A third-party controller gets
  write scopes the platform grants and can revoke. The platform's observer
  always watches. Out-of-scope writes become deltas and are never silent.
- **Track, and take no dependency on:** BCP-003-02 v1.1 (claims), Catena (slots
  map cleanly onto translator targets), MS-05-03 Blockspecs (a source for
  profiles), and the AMWA "tested event" for controller vendors.

### 4.5 Suggested changes to the RFC draft (judgment)

1. Replace "The configuration controller as a platform function" with a section
   on the control contract. Present the controller as the default
   implementation among several possible ones.
2. Add the evidence-level fields (`validate`, `readback`, `notify`) to the
   `parameters` block, with an example for a translator.
3. Add `role: translator` and `role: controller` descriptor shapes, with
   targets and profiles for translators and requested write scopes for
   controllers.
4. Replace "record the `validationFingerprint`" with "record the device's
   `validationFingerprint` as a compatibility check". Proof of applied state
   comes from comparing values on read-back.
5. Add "coerced" as an outcome next to "applied", "failed", "deployed with
   values" and "sent".
6. Answer question 4 ("NMOS defines no lock for IS-12") with the write-scope
   lease and the observer. Cite MS-05-01's multiple-controller text.
7. Name ADR-0025, ADR-0037 and ADR-0043 in "Decisions this would amend", or
   state that the controller runs as an AWX-invoked worker so those ADRs stand.
8. Drop "orchestrator media function" wording if it appears in later drafts.
   Use "control application" and "translator function".

## 5. Open questions

1. Should the observer be the first thing to build, ahead of any writer? It is
   read-only and feeds [#669](https://github.com/dmfdeploy/dmfdeploy/issues/669)
   directly.
2. Is a write-scope lease per target enough, or do some workloads need scopes
   per role path (for example, a panel owns `root.audio.gain` while the
   platform owns the rest)?
3. Should dmfdeploy require third-party controllers to pass an on-behalf-of
   identity, and how does that fit the identity direction, given the
   [ADR-0028](../decisions/0028-identity-and-authority-chain.md) note?
4. Who signs a translator device profile: the translator publisher, the device
   vendor, or the facility after review?
5. Should dmfdeploy share the evidence-level idea with AMWA as a question,
   alongside the existing IN-003 question? That is external contact and needs
   project approval first.

## 6. What the survey could not verify

- Any vendor's IS-12 or IS-14 controller implementation. None is documented
  publicly.
- Controller versus device roles in the IBC 2026 BCP-008 demo.
- VideoIPath official driver documentation and its reservation or lock model.
- DataMiner northbound APIs in depth, its Kubernetes deployment, and any IS-12
  connector.
- Lawo HOME API, Riedel MediorWorks, GV Orbit and Evertz northbound APIs.
- AMPP schema format and its apply confirmation.
- Lock semantics of Cerebrum's federated routemasters.
- Whether the normative ST 2138 committee drafts (beyond `st2138-a` and the
  Ross SDK) define multiple-client behaviour.
- The content of the four small "nmos-bridge" GitHub repositories.
- The SMPTE journal paper on Ember+ and IS-08 (title only).
- Telestream, Vizrt, Cinegy, Sony Live System Manager, Qvest and others were
  not covered.
- MXL TSC membership for Lawo, AWS, NVIDIA and Grass Valley rests on a search
  summary of the EBU announcement and not on a read of the page.
- Cross-industry precedents for gateways (OPC UA aggregating servers,
  OpenDaylight NETCONF mount points) were not sourced, so the survey leaves
  them out.
