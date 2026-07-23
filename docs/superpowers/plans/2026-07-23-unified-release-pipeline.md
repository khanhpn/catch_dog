# Unified Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Universal macOS texture compatibility and deliver releases and GitHub Pages through one ordered `main` workflow.

**Architecture:** The existing continuous-release workflow owns delivery. A Pages job depends on its release job; pull-request validation remains isolated.

**Tech Stack:** Godot 4.6.3, Bash, GitHub Actions, GitHub Pages.

## Global Constraints

- Every unique successful `main` push advances the patch version.
- Windows x86_64 and macOS Universal archives must pass validation and checksum verification before release.
- Pages must deploy only after the GitHub Release succeeds.

---

### Task 1: Universal macOS texture compatibility

**Files:**
- Modify: `scripts/ci/validate_release_config.sh`
- Modify: `project.godot`
- Modify: `export_presets.cfg`

- [x] Add a failing configuration assertion for `textures/vram_compression/import_etc2_astc=true`.
- [x] Run `bash scripts/ci/validate_release_config.sh` and observe failure.
- [x] Enable ETC2/ASTC imports and the macOS preset texture format.
- [ ] Run the validator and a real macOS export successfully.

### Task 2: Ordered release and Pages deployment

**Files:**
- Modify: `.github/workflows/release.yml`
- Delete: `.github/workflows/pages.yml`
- Modify: `scripts/ci/validate_release_config.sh`

- [x] Add failing assertions for the Pages dependency, actions, permissions, and single-workflow ownership.
- [x] Add `deploy-pages` with `needs: release`.
- [x] Remove the standalone Pages workflow.
- [ ] Parse workflow YAML and run all repository validators.
- [ ] Commit, push `main`, and confirm the workflow-created tag and release.
