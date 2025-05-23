# Fedora CoreOS Config

[![next-devel status](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/coreos/fedora-coreos-pipeline/main/next-devel/badge.json)](https://github.com/coreos/fedora-coreos-pipeline/blob/main/next-devel/README.md)

Base manifest configuration for
[Fedora CoreOS](https://coreos.fedoraproject.org/).

Use https://github.com/coreos/coreos-assembler to build it.

Discussions in
https://discussion.fedoraproject.org/c/server/coreos. Bug
tracking and feature requests at
https://github.com/coreos/fedora-coreos-tracker.

## About this repo

There is one branch for each stream. The default branch is
[`testing-devel`](https://github.com/coreos/fedora-coreos-config/commits/testing-devel),
on which all development happens. See
[the design](https://github.com/coreos/fedora-coreos-tracker/blob/main/Design.md#release-streams)
and [tooling](https://github.com/coreos/fedora-coreos-tracker/blob/main/stream-tooling.md)
docs for more information about streams.

All file changes in `testing-devel` are propagated to other
branches (to `next-devel`, `branched`, and `rawhide` through
[config-bot](https://github.com/coreos/fedora-coreos-releng-automation/tree/main/config-bot),
and to `testing` and eventually `stable` through usual
promotion), with the following exceptions:
- `manifest.yaml`: contains the stream's name, yum repos
  used during composes, and the `releasever`.
- lockfiles (`manifest-lock.*` files): on `testing-devel`
  and `next-devel`, lockfiles are pushed by
  [the `bump-lockfile` job](https://github.com/coreos/fedora-coreos-pipeline/blob/main/jobs/bump-lockfile.Jenkinsfile).
  Production streams receive them as part of usual
  promotion. Overrides (`manifest-lock.overrides.*`) are
  managed independently with the help of some GitHub Actions
  (see sections below).

## Layout

We intend for Fedora CoreOS to be used directly for a wide variety
of use cases.  However, we also want to support "custom" derivatives
such as Fedora Silverblue, etc.  Hence the configuration in this
repository is split up into reusable "layers" and components on
the rpm-ostree side.

To derive from this repository, the recommendation is to add it
as a git submodule.  Then create your own `manifest.yaml` which does
`include: fedora-coreos-config/ignition-and-ostree.yaml` for example.
You will also want to create an `overlay.d` and symlink in components
in this repository's `overlay.d`.

## Overriding packages

By default, all packages for FCOS come from the stable
Fedora repos. However, it is sometimes necessary to either
hold back some packages, or pull in fixes ahead of Bodhi. To
add such overrides, one needs to add the packages to
`manifest-lock.overrides.yaml` (there are also arch-specific
variants of these files for the rare occasions the override
should only apply to a specific arch). There is a
[tool](ci/overrides.py) to help with this, and for simple
cases, an [automated workflow](https://github.com/coreos/fedora-coreos-config/actions/workflows/add-override.yml)
that runs the tool and submits a PR.

Note that comments are not preserved in these files. The
lockfile supports arbitrary keys under the `metadata` key to
carry information. Some keys are semantically meaningful to
humans or other tools.

### Fast-tracking

Example:

```yaml
packages:
  selinux-policy:
    evra: 34.10-1.fc34.noarch
    metadata:
      type: fast-track
      bodhi: https://bodhi.fedoraproject.org/updates/FEDORA-2021-f014ca8326
      reason: https://github.com/coreos/fedora-coreos-tracker/issues/850
  selinux-policy-targeted:
    evra: 34.10-1.fc34.noarch
    metadata:
      type: fast-track
      # you don't have to repeat the other keys for related packages
```

Whenever possible, it is important that the package be
submitted as an update to Bodhi so that we don't have to
carry the override for a long time.

Fast-tracked packages will automatically be removed by the
`remove-graduated-overrides` GitHub Action in this repo once
they reach the stable Fedora repos (or newer versions). They
are detected by the `type: fast-track` key.

### Pinning

Example:

```
packages:
  dracut:
      evr: 053-5.fc34
      metadata:
        type: pin
        reason: https://github.com/coreos/fedora-coreos-tracker/issues/842
  dracut-network:
      evr: 053-5.fc34
      metadata:
        type: pin
        reason: https://github.com/coreos/fedora-coreos-tracker/issues/842
```

All pinned packages *must* have a `reason` key containing
more information about why the pin is necessary.

Once an override PR is merged,
[`coreos-koji-tagger`](https://github.com/coreos/fedora-coreos-releng-automation/tree/main/coreos-koji-tagger)
will automatically tag overridden packages into the pool.

## Adding packages to the OS

Since `testing-devel` is directly promoted to `testing`, it
must always be in a known state. The way we enforce this is
by requiring all packages to have a corresponding entry in
the lockfile.

Therefore, to add new packages to the OS, one must also add
the corresponding entries in the lockfiles:
- for packages which should follow Bodhi updates, place them
  in `manifest-lock.$basearch.json`
- for packages which should remain pinned, place them
  in `manifest-lock.overrides.$basearch.yaml`

There will be better tooling to come to enable this, though
one easy way to do this is for now:
- add packages to the correct YAML manifest
- run `cosa fetch --update-lockfile` (this will only update the lockfile for
  the current architecture, most likely `x86_64`)
- copy the new lines to the lockfiles for other architectures (i.e. `aarch64`)
- commit only the new package entries (skip the timestamped changes to avoid
  merge conflicts with the lockfile updates made by the bot)

## Moving to a new major version (N) of Fedora

[Create a rebase checklist](https://github.com/coreos/fedora-coreos-tracker/issues/new?labels=kind/enhancement&template=rebase.md&title=Rebase+onto+Fedora+N) in fedora-coreos-tracker.

## CoreOS CI

Pull requests submitted to this repo are tested by
[CoreOS CI](https://github.com/coreos/coreos-ci). You can see the pipeline
executed in `.cci.jenkinsfile`. For more information, including interacting with
CI, see the [CoreOS CI documentation](https://github.com/coreos/coreos-ci/blob/main/README-upstream-ci.md).

## Tests layout
Tests should follow the following format:

```bash
#!/bin/bash
## kola:
##   exclusive: false
##   platforms: aws gcp
##   # See all options in https://coreos.github.io/coreos-assembler/kola/external-tests/#kolajson
#
# Short summary of what the test does, why we need it, etc.
#
# Recommended: Link to corresponding issue or PR
#
# Explain the reasons behind all the kola options:
# - distros: fcos
#   - This test only runs on FCOS due to ...
# - platforms: qemu
#   - This test should ...
# - etc.

set -euxo pipefail

. $KOLA_EXT_DATA/commonlib.sh

foo_bar() <-- Other function definitions

if ...    <-- Actual test code
          <-- Errors must be raised with `fatal()`
          <-- Does not need to end with a call to `ok()`
```
# fcc
