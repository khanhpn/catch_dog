# Unified Release Pipeline Design

## Goal

Every push to `main` runs one ordered delivery pipeline: validate and build the
Godot project, publish the next patch GitHub Release, then deploy `site/` to
GitHub Pages.

## Design

`.github/workflows/release.yml` is the sole `main` delivery workflow. Its
`release` job atomically reserves a SemVer patch tag, stamps the export version,
imports Godot resources, validates, tests, performs the soak test, exports both
platform archives, checksums them, and publishes the release. `deploy-pages`
depends on `release`, so a failed build or release cannot deploy the site.

The separate Pages workflow is removed to prevent duplicate or out-of-order
deployments. Pull requests continue using `validate-build.yml` without creating
tags, releases, or Pages deployments.

Universal macOS export requires ETC2/ASTC texture imports for its arm64 slice.
The project enables `rendering/textures/vram_compression/import_etc2_astc`, and
the export preset includes ETC2/ASTC textures.

## Failure handling

An unpublished tag reserved by a failed release job is removed only when it
still points at that job's SHA. Published releases remain immutable. Pages runs
only after a successful release and can be retried independently for the same
workflow run.

## Verification

The release configuration validator enforces the ETC2/ASTC setting, the
release-to-Pages dependency, required Pages actions and permissions, and the
absence of a second Pages workflow. Godot validation, tests, soak test, and a
real macOS export are the completion gates.
