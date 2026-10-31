---
date: 2026-10-31
---

# EBU Dynamic Media Facility overview talk and its comparison register

**What this is:** a project summary of a public conference talk about the EBU
Dynamic Media Facility (DMF) reference architecture, plus a register of the
talk's individual claims. A later pass compares each row with the dmfdeploy
platform. This page records what the speaker said. It decides nothing and
assesses nothing.

## Source

| Field | Value |
|---|---|
| Title (as shown on the video page) | "IP SHOWCASE OTW The Dynamic Media FeacilityWillem Vermost EBU" (spelling as published) |
| Speaker (as shown on the video page) | Willem Vermost, EBU |
| Channel | AIMS Alliance for IP Media Solutions |
| Upload date | 2025-10-01 |
| Duration | 17:09 (1029 seconds) |
| URL | <https://www.youtube.com/watch?v=c30xDznESOE> |
| Date accessed | 2026-10-31 |
| Video description | Says the initiative proposes a containerised architecture with modular media functions and a Media Exchange Layer for interoperability, and that its SDK promotes open standards. |
| Chapters | None published. The outline below is derived from the transcript. |

**How it was extracted.** The project operator produced an automatic
speech-recognition transcript of the audio, with speaker labels and per-segment
timestamps. No manual captions were used. The transcript is readable and
consistent, but it has errors on names and acronyms. Items that look wrong are
marked "caption unclear" and left unguessed.

**Limits of the extraction.**

- The slides were not seen. Frame extraction produced no images, so the
  register covers what the speaker said aloud. Numbers read from slides (for
  example switch speed-up and CPU thread counts) come from the speech only.
  The speaker says some slides are too small to read and refers to a use-case
  document that this register does not cover.
- The talk is short and high level. It states few testable requirements. Most
  rows are descriptions and aspirations.
- A second speaker introduces the next session and speaks only a few words.
- The raw transcript is kept outside the repository. This page paraphrases it.
  Timestamps point to the start of the segment where the statement begins.
- Company names in the talk are left out of this page. Open standards and the
  EBU reference architecture are named.

## Summary

The speaker argues that live media production should move from dedicated
hardware to software on commodity IT. The talk starts from the operations problem:
broadcasters must serve more outlets with the same resources, and facility
technology changes more slowly than production teams do. IP replaced SDI
cabling but kept the same dedicated boxes, so facilities moved to IP without
moving to IT. Meanwhile Ethernet switches and CPUs have grown fast, which
makes commodity servers attractive. The speaker contrasts how cloud operators treat
servers (replace a failed one) with how broadcasters treat boxes (nurse each
one), and expects support effort to shrink under the first model. The proposed
building block is the media function, a containerised unit of media processing.
A graph of media functions is a workflow that an operator can script, start and
stop. The speaker then describes the reference architecture: a generic IT base that
broadcasters should reuse, a media layer for exchange between media functions,
and an application and UI zone, with provisioning, orchestration, control,
monitoring and security cutting across them. The speaker highlights cost and frame loss
when media leaves a compute resource between functions, and proposes in-memory
exchange. The speaker ends with how the open-source project formed (an industry meeting,
a North American co-host, Linux Foundation governance, a June 2025 launch) and
says the media exchange layer is the first deliverable.

## Outline

| Time | Topic |
|---|---|
| [0:00](https://youtu.be/c30xDznESOE?t=0) | Introduction and audience poll |
| [0:46](https://youtu.be/c30xDznESOE?t=46) | Why broadcasters want agility: newsroom operations and past rebuilds |
| [2:19](https://youtu.be/c30xDznESOE?t=139) | Changing ecosystem: online distribution and the efficiency driver |
| [3:29](https://youtu.be/c30xDznESOE?t=209) | From SDI to IP, and the gap before IT |
| [5:07](https://youtu.be/c30xDznESOE?t=307) | Technology trends: switches and CPUs |
| [6:31](https://youtu.be/c30xDznESOE?t=391) | Pets versus cattle and the support argument |
| [8:14](https://youtu.be/c30xDznESOE?t=494) | Commodity stack, containers, media functions and workflows as graphs |
| [10:19](https://youtu.be/c30xDznESOE?t=619) | Use cases and a broadcaster example |
| [11:05](https://youtu.be/c30xDznESOE?t=665) | Cost of leaving compute between functions, and in-memory exchange |
| [11:42](https://youtu.be/c30xDznESOE?t=702) | The reference architecture: layers, zones, cross-cutting concerns |
| [13:38](https://youtu.be/c30xDznESOE?t=818) | Security and the Cyber Resilience Act |
| [14:22](https://youtu.be/c30xDznESOE?t=862) | Industry meeting, co-host, Linux Foundation, project launch |
| [16:37](https://youtu.be/c30xDznESOE?t=997) | Scope: the media exchange layer first |

## Glossary

| Term in the talk | Meaning in the talk | dmfdeploy equivalent |
|---|---|---|
| Dynamic Media Facility (DMF) | The EBU reference architecture for software-based, containerised live media production. | The architecture the dmfdeploy platform aligns with. See [EBU mapping](../architecture/DMF%20EBU%20Mapping%20(2026-04-25).md) and [ADR-0003](../decisions/0003-ebu-v2-taxonomy.md). |
| Media function | A containerised unit of media processing, for example a vision switcher or an equaliser. | Media Function in the catalog. See [ADR-0013](../decisions/0013-media-function-catalog-model.md) and [ADR-0047](../decisions/0047-media-function-packaging-catalog-sources-trust-model.md). |
| Workflow (graph of media functions) | Connected media functions that together do a production job; can be scripted, started and stopped. | Media Workload. See [ADR-0046](../decisions/0046-first-class-media-workload-entity.md) and [ADR-0037](../decisions/0037-media-workloads-netbox-instance-inventory.md). |
| Media Exchange Layer | The layer that moves media between media functions, ideally in memory on one host. | Media eXchange Layer (MXL), layer 4 in the EBU mapping. See [ADR-0017](../decisions/0017-mxl-intra-host-data-plane.md). |
| Base layer (generic IT) | Infrastructure, networks, host platforms and container platforms that broadcasters should reuse. | Layers 1 to 3 in the EBU mapping: the k3s cluster and its host. See [ADR-0018](../decisions/0018-self-managed-k3s-not-ack.md). |
| Application and UI | The top zone: control applications, physical panels or touchscreens. | Layer 6; the operator console (dmf-cms). |
| Provisioning, orchestration, control, monitoring | Concerns the talk says cut across all layers. | The verticals and lifecycle stages in the EBU mapping. See [ADR-0012](../decisions/0012-configure-stage-distinct-from-provision.md), [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md) and [ADR-0038](../decisions/0038-netbox-driven-dynamic-monitoring.md). |
| Security (cross-cutting) | Protecting IP-based facilities, including product vulnerability obligations. | The security vertical. See [ADR-0008](../decisions/0008-openbao-secrets-architecture.md). |
| Pets versus cattle | Contrast between nursing individual machines and replacing failed ones. | No project term. Related: [ADR-0043](../decisions/0043-workload-scale-to-zero-availability.md). |
| Off-the-shelf servers | Commodity compute with network cards and GPUs in place of dedicated boxes. | The target hosts: commodity ARM64 nodes. See [THESIS](../THESIS.md). |
| SDI, ST 2110, IPMX, SRT, WebRTC | Baseband video and IP transports named as flow entry and exit paths. | Industry vocabulary; the platform's transport stance is in [ADR-0017](../decisions/0017-mxl-intra-host-data-plane.md). |
| Cyber Resilience Act | EU regulation on the security of products with digital elements. | No project term. See [ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md). |
| Requirements council, technical steering committee, tiger team | Governance bodies and the small team that wrote the first proposal for the open-source project. | None. |

## Comparison register

Each row is one claim. Strength follows the speaker's wording: Requirement or
recommendation, Description, Aspiration, Example, or Unclear. Both assessment
columns stay empty of findings until the comparison runs.

| ID | Topic | Statement | Strength | Timestamp | dmfdeploy status | Evidence and links |
|---|---|---|---|---|---|---|
| V-001 | Operations and lifecycle | Live news production changes plans minute to minute, and the technology under it is less flexible than the people who use it. | Description | [0:51](https://youtu.be/c30xDznESOE?t=51) | Not assessed | |
| V-002 | Infrastructure and platform | Moving from SD to HD video meant replacing cabling and rebuilding each studio in turn, and one studio rebuild took a year. | Example | [1:28](https://youtu.be/c30xDznESOE?t=88) | Not assessed | |
| V-003 | Operations and lifecycle | Broadcasters now run online services next to linear channels, so budget and staff move into online distribution. | Description | [2:19](https://youtu.be/c30xDznESOE?t=139) | Not assessed | |
| V-004 | Operations and lifecycle | Serving more outlets with the same resources makes production efficiency the driver behind the EBU work. | Description | [2:55](https://youtu.be/c30xDznESOE?t=175) | Not assessed | |
| V-005 | Interoperability and standards | The move from SDI to IP followed the earlier move from tape to files, and IP production standards existed from about 2016 to 2017. | Description | [3:29](https://youtu.be/c30xDznESOE?t=209) | Not assessed | |
| V-006 | Operations and lifecycle | Remote and software-based production trials during 2020 showed that live production can run on software. | Example | [4:15](https://youtu.be/c30xDznESOE?t=255) | Not assessed | |
| V-007 | Infrastructure and platform | The industry moved to IP but not yet to IT: facilities still use dedicated boxes with a different connector at the back. | Description | [4:53](https://youtu.be/c30xDznESOE?t=293) | Not assessed | |
| V-008 | Infrastructure and platform | Ethernet switch speed has grown about 64 times since the ST 2110 discussions began, while workflow needs grew less, so switch capacity per workflow is cheaper. | Description | [5:22](https://youtu.be/c30xDznESOE?t=322) | Not assessed | |
| V-009 | Infrastructure and platform | CPU clock rates stay flat while thread counts grow fast, with a rise from 192 to 384 threads per CPU within a year given as an example. | Description | [5:44](https://youtu.be/c30xDznESOE?t=344) | Not assessed | |
| V-010 | Infrastructure and platform | Cheaper switching and many-threaded CPUs should let the industry move to off-the-shelf servers. | Aspiration | [6:23](https://youtu.be/c30xDznESOE?t=383) | Not assessed | |
| V-011 | Operations and lifecycle | Cloud-style operations replace a failed server with a new one without repairing it (the pets versus cattle contrast). | Description | [6:41](https://youtu.be/c30xDznESOE?t=401) | Not assessed | |
| V-012 | Operations and lifecycle | Broadcast support engineers still spend engineering effort on individual boxes, including ST 2110 boxes. | Description | [7:29](https://youtu.be/c30xDznESOE?t=449) | Not assessed | |
| V-013 | Operations and lifecycle | Running on commodity servers would reduce support to one or two people, where today each product line has its own specialist. | Aspiration | [7:55](https://youtu.be/c30xDznESOE?t=475) | Not assessed | |
| V-014 | Infrastructure and platform | The target stack is a standard IP network with commodity servers (network cards, GPUs) and applications running on top as software. | Description | [8:14](https://youtu.be/c30xDznESOE?t=494) | Not assessed | |
| V-015 | Infrastructure and platform | Containers suit media functions because they are lighter than full virtualisation and start and stop in a short time. | Description | [8:31](https://youtu.be/c30xDznESOE?t=511) | Not assessed | |
| V-016 | Resource and function model | A media function is one unit of media processing, such as a vision switcher or an equaliser, and the right granularity is left open. | Description | [8:54](https://youtu.be/c30xDznESOE?t=534) | Not assessed | |
| V-017 | Resource and function model | A graph of media functions running as containers is a workflow. | Description | [9:03](https://youtu.be/c30xDznESOE?t=543) | Not assessed | |
| V-018 | Orchestration and control plane | Workflows are scripted, started on demand and brought down again when finished. | Description | [9:14](https://youtu.be/c30xDznESOE?t=554) | Not assessed | |
| V-019 | Resource and function model | The industry has spent much effort on metadata schemas and control types that add little value; the value sits in the media function that changes the media. | Requirement or recommendation | [9:41](https://youtu.be/c30xDznESOE?t=581) | Not assessed | |
| V-020 | Resource and function model | The initiative collected a set of use cases and published them in a document. | Description | [10:19](https://youtu.be/c30xDznESOE?t=619) | Not assessed | |
| V-021 | Resource and function model | A workflow is defined by connecting media functions as a graph, for example camera input, video processor and vision mixer. | Example | [10:25](https://youtu.be/c30xDznESOE?t=625) | Not assessed | |
| V-022 | Media transport and timing | Flows reach cloud or on-premises compute over ST 2110 or IPMX. | Description | [10:55](https://youtu.be/c30xDznESOE?t=655) | Not assessed | |
| V-023 | Media transport and timing | Flows leave the compute environment over ST 2110, SRT or WebRTC. | Description | [10:55](https://youtu.be/c30xDznESOE?t=655) | Not assessed | |
| V-024 | Media transport and timing | In current practice, connections between media functions leave one compute resource over ST 2110 and enter another. | Description | [11:05](https://youtu.be/c30xDznESOE?t=665) | Not assessed | |
| V-025 | Media transport and timing | Each hop over uncompressed ST 2110 needs resynchronisation, which costs frames. | Description | [11:24](https://youtu.be/c30xDznESOE?t=684) | Not assessed | |
| V-026 | Media transport and timing | ST 2110 is a good protocol for uncompressed media. | Description | [11:22](https://youtu.be/c30xDznESOE?t=682) | Not assessed | |
| V-027 | Media transport and timing | Media should not leave a compute resource when the media functions that exchange it run within that resource. | Requirement or recommendation | [11:29](https://youtu.be/c30xDznESOE?t=689) | Not assessed | |
| V-028 | Media transport and timing | Media functions on the same host could exchange media in memory. | Aspiration | [11:36](https://youtu.be/c30xDznESOE?t=696) | Not assessed | |
| V-029 | Architecture layers | The EBU published the Dynamic Media Facility Reference Architecture the year before the talk, free to download. | Description | [11:42](https://youtu.be/c30xDznESOE?t=702) | Not assessed | |
| V-030 | Architecture layers | The reference architecture is a small set of layers, grouped in three zones. | Description | [12:09](https://youtu.be/c30xDznESOE?t=729) | Not assessed | |
| V-031 | Architecture layers | The base zone is generic IT: infrastructure, networks, host platforms and container platforms. | Description | [12:15](https://youtu.be/c30xDznESOE?t=735) | Not assessed | |
| V-032 | Infrastructure and platform | The broadcast industry should not rebuild generic IT, such as servers, because the IT industry already does it at larger scale. | Requirement or recommendation | [12:18](https://youtu.be/c30xDznESOE?t=738) | Not assessed | |
| V-033 | Infrastructure and platform | The broadcast industry should not create its own container platform. | Requirement or recommendation | [12:36](https://youtu.be/c30xDznESOE?t=756) | Not assessed | |
| V-034 | Architecture layers | A media layer sits above the base zone and provides media exchange between media functions, within a host or between hosts (caption unclear on which). | Description | [12:40](https://youtu.be/c30xDznESOE?t=760) | Not assessed | |
| V-035 | Architecture layers | Media functions use the media exchange layer. | Description | [12:52](https://youtu.be/c30xDznESOE?t=772) | Not assessed | |
| V-036 | Architecture layers | The application and UI zone sits on top and couples to the media functions. | Description | [12:55](https://youtu.be/c30xDznESOE?t=775) | Not assessed | |
| V-037 | Architecture layers | The user interface can be a physical panel with buttons and knobs or a touchscreen, and both make sense. | Description | [13:00](https://youtu.be/c30xDznESOE?t=780) | Not assessed | |
| V-038 | Operations and lifecycle | A small production run by one person is better served by a small UI than by a gallery of 15 people. | Requirement or recommendation | [13:08](https://youtu.be/c30xDznESOE?t=788) | Not assessed | |
| V-039 | Architecture layers | Cross-cutting concerns span all layers (the speaker says three, lists more, and the caption on their origin is unclear). | Description | [13:24](https://youtu.be/c30xDznESOE?t=804) | Not assessed | |
| V-040 | Provisioning and configuration | Media functions need provisioning. | Requirement or recommendation | [13:30](https://youtu.be/c30xDznESOE?t=810) | Not assessed | |
| V-041 | Orchestration and control plane | Media functions need orchestration. | Requirement or recommendation | [13:34](https://youtu.be/c30xDznESOE?t=814) | Not assessed | |
| V-042 | Orchestration and control plane | Media functions need control. | Requirement or recommendation | [13:35](https://youtu.be/c30xDznESOE?t=815) | Not assessed | |
| V-043 | Telemetry and monitoring | Media functions need monitoring. | Requirement or recommendation | [13:35](https://youtu.be/c30xDznESOE?t=815) | Not assessed | |
| V-044 | Security and trust | IP needs deliberate security work, unlike SDI, where the speaker has not seen a virus. | Description | [13:38](https://youtu.be/c30xDznESOE?t=818) | Not assessed | |
| V-045 | Security and trust | Security was raised during the ST 2110 work and gains weight with software-based facilities. | Description | [13:51](https://youtu.be/c30xDznESOE?t=831) | Not assessed | |
| V-046 | Security and trust | The EU Cyber Resilience Act applies from the end of 2027 and requires products on the market to be free of known exploitable flaws (caption unclear on the exact wording). | Requirement or recommendation | [13:57](https://youtu.be/c30xDznESOE?t=837) | Not assessed | |
| V-047 | Interoperability and standards | A shared framework would benefit the whole industry if vendors and broadcasters use it. | Aspiration | [14:16](https://youtu.be/c30xDznESOE?t=856) | Not assessed | |
| V-048 | Interoperability and standards | At a meeting of broadcasters, equipment makers, cloud providers and chip makers, attendees agreed within minutes to build the media exchange layer first. | Requirement or recommendation | [14:43](https://youtu.be/c30xDznESOE?t=883) | Not assessed | |
| V-049 | Interoperability and standards | Two companies offered to contribute code to the media exchange layer project. | Description | [14:55](https://youtu.be/c30xDznESOE?t=895) | Not assessed | |
| V-050 | Interoperability and standards | A European-only effort risks being seen as not invented elsewhere, so a North American broadcaster hosted a matching meeting in Montreal and the NABA joined. | Description | [15:11](https://youtu.be/c30xDznESOE?t=911) | Not assessed | |
| V-051 | Interoperability and standards | The project runs as open source under the Linux Foundation because the EBU does not see itself as an experienced steward of open-source code. | Description | [15:31](https://youtu.be/c30xDznESOE?t=931) | Not assessed | |
| V-052 | Interoperability and standards | A small team wrote a first proposal so that discussion had a concrete text to criticise. | Description | [15:56](https://youtu.be/c30xDznESOE?t=956) | Not assessed | |
| V-053 | Interoperability and standards | The project launched officially in June with a requirements council, a technical steering committee and partner participation on calls. | Description | [16:18](https://youtu.be/c30xDznESOE?t=978) | Not assessed | |
| V-054 | Interoperability and standards | The media exchange layer is the first deliverable, and several applications at the trade show already use it. | Description | [16:29](https://youtu.be/c30xDznESOE?t=989) | Not assessed | |
| V-055 | Interoperability and standards | The project builds only what is media-specific and reuses existing IT-industry components for everything else. | Requirement or recommendation | [16:55](https://youtu.be/c30xDznESOE?t=1015) | Not assessed | |
| V-056 | Interoperability and standards | The video description says the initiative offers an SDK that promotes open standards and a containerised architecture with modular media functions. | Description | [page description](https://youtu.be/c30xDznESOE) | Not assessed | |

### Rows by topic

| Topic | Rows |
|---|---|
| Architecture layers | 8 |
| Infrastructure and platform | 9 |
| Interoperability and standards | 11 |
| Media transport and timing | 7 |
| Operations and lifecycle | 8 |
| Orchestration and control plane | 3 |
| Provisioning and configuration | 1 |
| Resource and function model | 5 |
| Security and trust | 3 |
| Telemetry and monitoring | 1 |
| Total | 56 |

## How to run the comparison

Work through the register one row at a time. Each row ends with a status and
evidence, so a reviewer can check the result without redoing the search.

1. Read the row and, if the statement is ambiguous, listen to the video at the
   linked timestamp.
2. Find the matching decision, plan, issue or code. Start with
   [docs/decisions/INDEX.md](../decisions/INDEX.md), the
   [EBU mapping](../architecture/DMF%20EBU%20Mapping%20(2026-04-25).md) and the
   ADRs named in the glossary. Then search the component repositories.
3. Set `dmfdeploy status` to exactly one of: Implemented, Partial, Planned, Not
   planned, Out of scope. Use "Not assessed" only for rows you have not
   reached.
4. Fill `Evidence and links` with a path in the umbrella repository, an ADR,
   plan or issue link, or a component-repository path with a commit or tag.
   Cite claims about the running platform from the cluster, as
   [ADR-0006](../decisions/0006-cluster-is-the-truth.md) requires.
5. For every row marked Partial, Planned or Not planned, add a line to a gap
   list. File each gap as a GitHub issue with the `component:*` and
   `workstream:*` labels, as the [working model](../WORKING-MODEL.md) requires.
   Do not keep a local backlog in this file.
6. Rows with Unclear strength need a decision first: check the open questions
   below, then decide whether the row is a requirement worth testing.

Checks worth automating:

- A script that parses the register table and reports counts per status and per
  topic, and fails if any ID repeats or any status falls outside the fixed list.
- A check that every row has a timestamp link in the form
  `https://youtu.be/c30xDznESOE?t=<seconds>` with a value below 1029.
- A check that every row with a status other than "Not assessed" has non-empty
  evidence.
- A check that every Evidence path resolves in the repository.

## Open questions

- Which version of the reference architecture does the speaker mean by "last
  year, before IBC"? The talk dates to 2025. The [EBU mapping](../architecture/DMF%20EBU%20Mapping%20(2026-04-25).md)
  tracks a later version, so check whether the layers still match.
- The speaker says three cross-cutting concerns, then lists provisioning,
  orchestration, control, monitoring and security. How does the published
  architecture group them?
- Does the media exchange layer cover exchange between hosts, or only within a
  host? The caption on this point is unclear (about 12:40).
- What granularity does the architecture expect for a media function? The
  speaker leaves it open.
- What is in the use-case document that the speaker mentions? The register has
  no rows from it.
- Which slide figures back the 64 times switch speed-up and the 192 to 384
  thread counts? Ask the speaker or find the slides.
- What exactly does the Cyber Resilience Act require of a media function
  supplier, and from which date? The caption on the wording is unclear.
- Which parts of the stack does "reuse existing IT components" cover, for
  example scheduling and identity? The talk names only servers and container
  platforms.
- Who owns the requirements for the media exchange layer after the June 2025
  launch, and where are the requirements published?
- The names of one person mentioned by first name and of the next speaker are
  caption unclear. The page does not need them.
