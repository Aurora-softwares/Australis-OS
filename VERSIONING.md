# Australis OS versioning guide

The current development version comes from the
[Australis OS — Development project](https://github.com/orgs/Aurora-softwares/projects/3)
**Target version** and **Status** fields, together with the implemented work in
[map_to_gui.md](map_to_gui.md). A Git tag records a past source snapshot; it
does not determine which version is currently being developed.

## Where the project stands

As of **26 October 2026** (project board and source tree checked):

| Measure | Current position |
| --- | --- |
| **Current development version** | **`0.1.0` pre-release**: foundation implemented; release qualification is next |
| `0.1.0` release gate | 🟡 5 project items are **Ready**, 3 **Done**: freeze baseline, run/archive QEMU matrix, document limits/platforms, unify version identity, verify/tag artifacts |
| Clean ISO build | 🟢 A fresh recursive `Development` checkout passes `make -j1 iso` and boots the PID 1 shell under QEMU AHCI; the working checkout also passes the NVMe shell boot |
| Implemented GUI foundation | 🟢 Phases 1–11 of 16 marked complete in [map_to_gui.md](map_to_gui.md) |
| Next feature version | `0.2.0`: Phase 12 accelerated compositor; 4 project items **In Progress**, 4 **Ready**, 3 **Done** |
| Later GUI phases | 🟡 Phase 13 has one graphics performance item In Progress; Phases 14–16 remain in the GUI roadmap alongside application, system, connectivity, security, and release work |
| Current release claim | `0.1.0` is being prepared; its release gate has not been completed |

**Progress estimate:** the implementation is at the **`0.1.0` qualification
gate**; the next feature milestone is **`0.2.0`**. Eleven of sixteen GUI phases
are marked complete (about 69% *by phase count*), but this does not estimate
remaining time, code volume, release quality, or proximity to stable `1.0.0`.
The GUI phases and project versions are different scopes: the project also
tracks work outside graphics. A board item marked Ready is planned work, not
implemented work.

The next `0.1.0` release task is the full foundation QEMU matrix with archived
results. The remaining gates also include supported-platform and limitation
documentation, version-identity wiring, a frozen baseline, and checksum/tag
verification of candidate artifacts. The clean ISO and PID 1 boot checks do
not by themselves qualify a release.

Phase 12's VirGL render-target probe now verifies source-alpha blending in a
live boot. Window textures are still composed into a software frame, so the
accelerated compositor item remains In Progress and the `0.2.0` gate is open.
The live retained compositor now follows window move and resize changes without
dropping to the older software fallback; maximized-window synchronization is
still disabled pending a kernel-panic investigation.

VirtIO-GPU 2D drag response improved from about **1.9 to 3.2 visible updates
per second** in the same 1280×800 QEMU TCG screenshot probe after reducing
software copies and batching nearby damage flushes. The probe includes QEMU
monitor screenshot overhead, so it is a comparative latency measurement, not
an FPS certification. Interactive `make run` now tries KVM before TCG; KVM
performance remains unmeasured on this host. The Phase 13 synchronization and
60 FPS qualification gates remain open.

For the latest implementation details and completion criteria, use
[map_to_gui.md](map_to_gui.md). [ROADMAP.md](ROADMAP.md) is a broader, older
milestone overview; some of its “current position” text lags the GUI roadmap.

## What each number means

| You see | Meaning | Use to describe current OS progress? |
| --- | --- | --- |
| Project **Target version** and **Status** | Planned version scope and completion of its gate items | 🟢 Primary version-progress tracker |
| [map_to_gui.md](map_to_gui.md) phase status | Implemented GUI features and next phase | 🟢 Implementation evidence; phases are not version numbers |
| `version = "0.1.0"` in `src/australis.hyproj` | OS project/build metadata aligned with the current development line | 🟡 Useful context, but not proof of release readiness |
| Git tag `0.0.6` | Latest tagged historical source reference on `Release` | 🟡 Identifies that snapshot, not today's development version |
| `version` app or KMon output `0.0.1` | Hard-coded runtime text awaiting automatic version wiring | 🔴 Stale; it does not identify the current checkout |
| `dev-<commit>` from `make release-candidate` | Default build-artifact label and commit identifier | 🟡 Identifies that candidate build |
| `AUKR`, `AUEX`, `AUN1`, HyFS, or boot-info ABI versions | Independent format/interface versions | 🔴 They can change separately from the OS version |

The `0.0.6` tag is not an ancestor of the current `Development` head. It has
no bearing on whether the current development line is `0.1.0` or how far its
release gate has progressed.

## Version plan from the development project

The project board assigns these targets. They describe intended scope, not
versions already released or promised dates. Statuses below are the board's
snapshot on 26 October 2026.

| Target | Main scope | Board position |
| --- | --- | --- |
| Baseline | Historical boot, kernel, storage, userland, graphics foundation | 🟢 64 Done |
| `0.1.0` | Qualify and package the existing foundation; unify version identity | 🟡 5 Ready, 3 Done |
| `0.2.0` | Accelerated compositor and GPU-backed windows (GUI Phase 12) | 🟡 4 In Progress, 4 Ready, 3 Done |
| `0.3.0` | Frame pacing, performance, and effects (GUI Phase 13) | 🟡 1 In Progress, 10 Backlog |
| `0.4.0` | Native application platform and packaging | 🔴 8 Backlog |
| `0.5.0` | Usable desktop and graphical applications | 🔴 9 Backlog |
| `0.6.0` | Sessions, users, permissions, services, and management | 🔴 8 Backlog |
| `0.7.0` | Networking and audio support | 🔴 8 Backlog |
| `0.8.0` | Security hardening, installer, signed packages, recovery | 🔴 7 Backlog |
| `0.9.0` | Beta qualification, soak/fault tests, physical hardware | 🔴 9 Backlog |
| `1.0.0` | Stable release gate: end-to-end apps, graphics, files, recovery, support evidence | 🔴 7 Backlog |

Before `1.0.0`, a **minor** number (`0.1.0` to `0.2.0`) can mark a new
capability milestone and may include incompatible interfaces if documented.
A **patch** number (`0.1.0` to `0.1.1`) is for fixes within the same milestone.
`1.0.0` should mark the first release whose supported behavior and interfaces
have an explicit compatibility policy. Roadmap phase numbers are never OS
version numbers: completing Phase 12 does not automatically complete every
`0.2.0` gate.

## How to identify a build

To check the *current development version*, inspect the project board's
**Target version** and **Status** fields, then compare the current source to
the relevant [GUI roadmap](map_to_gui.md) criteria. With GitHub CLI access:

```bash
gh project item-list 3 --owner Aurora-softwares --limit 200 --format json
```

To identify the exact source build independently of its development version:

```bash
git branch --show-current
git rev-parse --short HEAD
git status --short                      # Any output means uncommitted changes
```

For the current tree, report **“Australis OS `0.1.0` pre-release, Phase 11
foundation complete, `0.1.0` release gate pending, commit `<short-sha>`”**.
Append “plus local changes” if `git status --short` has output. For a packaged candidate,
use the `Version` and `Commit` fields in its `BUILD-INFO.txt`; the default
`dev-<commit>` label still means development. For a formal release, use the
matching Git tag and its release notes.

## When to promote a version

1. Update the project's Target version and Status fields, and
   [map_to_gui.md](map_to_gui.md) when GUI phase completion changes. Refresh
   this guide's current-position table and board counts after each requested
   project change.
2. Run the documented tests for that milestone on the stated QEMU configurations;
   record physical-hardware results if the release claims hardware support.
3. Build a candidate with `make release-candidate`, verify its ISO/checksum,
   and write release notes that name supported hardware and known limitations.
4. Set one intended OS version across the tag, project metadata, runtime
   `version` output, KMon, candidate label, and release notes. The runtime
   values currently need manual code changes until version wiring is added.
5. Tag the exact tested commit and publish the release from that commit. Then
   update this guide's current-position table and target statuses.

`make release-candidate` packages and checksums an image; its successful exit
alone does not certify that a version is ready to publish.
