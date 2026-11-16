# The DMF thesis in one page

**The idea:** dmfdeploy is an open-source prototype for exploring how a
software-defined media facility can be installed, managed, and monitored. It
brings together supporting services for identity, deployment, inventory, and
monitoring, based on the [EBU](https://tech.ebu.ch/) *Dynamic Media Facility*
Reference Architecture.

**The experiment:** The initial setup runs on a single computer or virtual
machine, so engineers can learn and experiment without first building a
cluster. This test environment leaves the size and architecture of future
facilities open.

**What has been demonstrated:** The author has installed the platform and
deployed an NMOS registry. An independent user has yet to reproduce the
process using the public instructions. That is the goal of the current
[`v0.1-polish` milestone](https://github.com/dmfdeploy/dmfdeploy/milestone/1).
The [Move 1 learnings](reviews/dmf-platform-move-1-learnings.md) record what
has been tested and what remains open.

## Who it's for

Broadcast and media-tech engineers who want to explore how to build and operate
an IP-media facility, including at the scale of an outside broadcast truck or a
small flypack. It is also for anyone who wants to study a working prototype
aligned with the EBU reference architecture, with its decisions on the record.

## The problem it addresses

Media functions perform tasks such as video mixing or format conversion. They
can use the Media eXchange Layer (MXL) to exchange media and AMWA NMOS
specifications for discovery and control. An NMOS registry supports discovery;
it is infrastructure for media workflows.

A facility also needs a way to manage access, protect secrets, keep an inventory,
deploy services, and monitor their health. dmfdeploy brings these supporting
services together in a platform that can be installed from a single container.
An operator console provides access to a catalog of deployable services and
media functions.

## What an independent user can test

The author has run this test. The goal is for an independent user to complete
it in under an hour using public artifacts and instructions:

1. **Install:** run the [dmf-init](https://github.com/dmfdeploy/dmf-init)
   container against a blank ARM64 Debian computer or virtual machine with at
   least 4 virtual CPUs and 16 GiB of memory.
2. **Sign in:** enroll a passkey and open the operator console. The steady-state
   design uses passkeys without passwords
   ([ADR-0015](decisions/0015-dmf-console-passkey-only.md)).
3. **Deploy:** choose the NMOS registry in the catalog and deploy it.
4. **Verify:** check that the deployment completed, the inventory reflects the
   service, and monitoring has discovered it.

Together, these steps test the path from an operator's request to deployment,
inventory, and monitoring. They do not yet demonstrate a complete production
media facility.

## What the prototype does not claim

The current prototype does not claim production-ready real-time media transport
or timing, resilience across multiple machines or sites, or measured
performance. The detailed boundaries are in
[ADR-0031](decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
and [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md).

## What comes next

The [roadmap](../ROADMAP.md) describes two later milestones. In
[`v0.2`](https://github.com/dmfdeploy/dmfdeploy/milestone/2), a team uses one
console to run a workload made up of multiple media functions. In
[`v0.3`](https://github.com/dmfdeploy/dmfdeploy/milestone/4), the team designs
and plans a workload and facility in the console.

The project's development is recorded in [JOURNEY.md](JOURNEY.md), and its
architectural decisions are in the [ADR record](decisions/INDEX.md#start-here).
