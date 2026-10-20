# Australis OS versioning guide

This guide separates **release versions** from **development progress**. The
release number tells you what has been tagged and shipped; the GUI roadmap
tells you what the current source tree can do. They advance at different times.

## Where the project stands

As of **20 October 2026**:

| Measure | Current position |
| --- | --- |
| Latest OS Git tag | `0.0.6` on the `Release` branch |
| Current `Development` checkout | Untagged development source, with uncommitted work; `Development` and the `0.0.6` tag have diverged |
| GUI roadmap | 🟢 Phases 1–11 of 16 marked complete in [map_to_gui.md](map_to_gui.md); 🔴 Phases 12–16 remain |
| Next implementation phase | Phase 12: hardware-accelerated window composition |
| Current release claim | Development build; there is no tagged `0.1.0` OS release |

**Progress estimate:** 11 of 16 named GUI phases are marked complete (about
69% *by phase count*). This is a navigation aid, not an estimate of remaining
time, code volume, release quality, or proximity to a stable `1.0.0`. The
remaining phases include a full desktop, security hardening, and release
engineering. Phase 11's status describes the current working tree, so it is
not yet a committed or tagged release claim.

For the latest implementation details and completion criteria, use
[map_to_gui.md](map_to_gui.md). [ROADMAP.md](ROADMAP.md) is a broader, older
milestone overview; some of its “current position” text lags the GUI roadmap.

## What each number means

| You see | Meaning | Use as the OS release version? |
| --- | --- | --- |
| Git tag `0.0.6` | Latest tagged release reference, currently on `Release` | 🟢 Yes, for that tagged source only |
| `version = "0.1.0"` in `src/australlis.hyproj` | Project/build metadata already set to a future number | 🔴 No; it does not create a release |
| `version` app or KMon output `0.0.1` | Hard-coded runtime text awaiting automatic version wiring | 🔴 No; it does not identify the current checkout |
| `dev-<commit>` from `make release-candidate` | Default build-artifact label and commit identifier | 🟡 Identify that candidate build, not a published release |
| `AUKR`, `AUEX`, `AUN1`, HyFS, or boot-info ABI versions | Independent format/interface versions | 🔴 No; they can change separately from the OS version |

The `0.0.6` tag is **not an ancestor** of the current `Development` head. Do
not describe the checkout as a linear `0.0.6` update or infer its exact
contents from the tag. Use its commit ID and dirty/clean state when discussing
a development build.

## Suggested release ladder

These are **planning targets**, not versions already earned or promised dates.
Assign a release number only after its gate is met and a matching Git tag is
created. If the roadmap changes, revise the targets before tagging.

| Target | Milestone and release gate | Position today |
| --- | --- | --- |
| `0.0.x` | Experimental tagged snapshots with explicit limitations | 🟢 `0.0.6` is the latest tag |
| `0.1.0` technical preview | Phases 1–11 integrated in a clean commit; documented QEMU test matrix, known limitations, repeatable ISO and release notes | 🟡 Phase work marked complete; release gate and tag still outstanding |
| `0.2.0` graphics preview | Phase 12 accelerated composition and Phase 13 performance/synchronization targets, with software fallback verified | 🔴 Planned |
| `0.3.0` desktop beta | Phase 14 usable graphical session and applications; Phase 15 security boundaries reviewed and tested | 🔴 Planned |
| `1.0.0` stable | Phase 16 release criteria, installation/recovery, prolonged QEMU and physical-hardware testing, published support and security policy | 🔴 Planned |

Before `1.0.0`, a **minor** number (`0.1.0` to `0.2.0`) can mark a new
capability milestone and may include incompatible interfaces if documented.
A **patch** number (`0.1.0` to `0.1.1`) is for fixes within the same milestone.
`1.0.0` should mark the first release whose supported behavior and interfaces
have an explicit compatibility policy. Roadmap phase numbers are never OS
version numbers: completing Phase 12 does not automatically publish `0.2.0`.

## How to identify a build

From the repository root:

```bash
git tag --sort=-version:refname | head -1  # Latest tag, not necessarily on this branch
git branch --show-current
git rev-parse --short HEAD
git status --short                      # Any output means uncommitted changes
```

For the current tree, report **“Australis OS Development, Phase 11 roadmap
complete, commit `<short-sha>` plus local changes”**. For a packaged candidate,
use the `Version` and `Commit` fields in its `BUILD-INFO.txt`; the default
`dev-<commit>` label still means development. For a formal release, use the
matching Git tag and its release notes.

## When to promote a version

1. Commit the milestone implementation and update [map_to_gui.md](map_to_gui.md)
   with evidence for its completion criteria.
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
