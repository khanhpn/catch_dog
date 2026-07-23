# Release checklist

This checklist is owned by the release owner. A green source test or packaged artifact is not evidence that a build was physically launched, signed, notarized, or performance-tested.

## Source and packaging

- [ ] Use Godot **4.6.3** and confirm `scripts/dev/validate_project.gd` passes.
- [ ] Run `scripts/dev/godot.sh --headless --path . --script tests/test_runner.gd` successfully.
- [ ] Run `scripts/dev/godot.sh --headless --path . --script scripts/dev/soak_test.gd` successfully and retain its count summary.
- [ ] Run `bash scripts/dev/validate_docs.sh`, `bash scripts/dev/validate_site.sh`, and `bash scripts/ci/validate_release_config.sh`.
- [ ] Run `git diff --check` and review the final diff for generated files, secrets, and unintended assets.
- [ ] Confirm the committed export configuration targets only Windows Desktop x86_64 and macOS Universal 2.
- [ ] Build both archives using the repository's release automation; preserve its sorted `SHA256SUMS.txt` with the artifacts.
- [ ] Verify `SHA256SUMS.txt` against both archives and inspect archive listings for repository metadata or credentials.
- [ ] Confirm archive names, version/tag, checksums, and release notes match the candidate.

## Physical smoke gates — owner required

- [ ] On a physical Windows x86_64 machine, launch the exported archive and complete: menu → tutorial/settings → gameplay → pause/resume → replay/result → quit.
- [ ] On a physical Intel Mac with an AMD GPU, launch the exported macOS app and complete the same smoke path.
- [ ] Inspect the macOS executable with `lipo -info` and confirm both `x86_64` and `arm64` slices before calling it Universal 2.
- [ ] On both systems, verify keyboard controls: arrows steer/drive/brake, Space throws a net, Escape pauses/resumes gameplay, and focused menu buttons activate from the keyboard.
- [ ] On both systems, verify a win and each loss path (time expiry, guard contact, and stopping at zero fuel), then replay without restarting the app.
- [ ] Record device/OS/build evidence, launch result, defects, and tester in the release record.

Do not check either physical-smoke item based on headless tests, an editor launch, CI output, or another machine's result.

## Performance gates — owner required

- [ ] Capture the documented busy-loop measurements from [performance.md](performance.md) on physical Windows x86_64 and the target AMD-GPU Mac.
- [ ] Verify 60 FPS at 1080p on Medium for the agreed target system.
- [ ] Verify at least 30 FPS on Low for the target AMD-GPU Mac.
- [ ] Attach device metadata, preset/resolution, run duration, frame-time results, and known limitations to the release record.

## macOS distribution gates — owner required

- [ ] Sign the macOS app with the release distribution identity using protected credentials; never commit certificates, private keys, passwords, or profiles.
- [ ] Notarize the signed archive with Apple and staple the successful notarization ticket to the distributable app/archive.
- [ ] Verify the signed/notarized artifact on a suitable physical Mac, including Gatekeeper behavior.
- [ ] If signing or notarization is unavailable, label the artifact **internal/unsigned testing only** and do not present it as a normal public macOS release.

## Publish decision

- [ ] Confirm downloads, checksums, license, and release notes are visible and correct.
- [ ] Link the release to the project documentation and record all gate evidence.
- [ ] Publish only after every applicable checkbox is complete, or explicitly mark the candidate as non-public/internal with the unmet gates listed.
