# Repository guidance

This repository builds separate Amazon Linux 2023 images for Claude, Codex, and T3 Code. For authentication, VSIX extraction, Windows payloads, desktop display setup, or user-facing commands, read [README.md](README.md).

## Image changes

Use the named `claude`, `codex`, and `t3` targets in [Dockerfile](Dockerfile). An untargeted build defaults to Claude for compatibility. Shared development dependencies belong in `base`; desktop libraries belong in the T3 target.

Claude and Codex remain separate CLI images. T3 includes both providers, its web UI/server and native desktop, plus Windows x64 payloads. Keep the complete Codex Windows package and T3 Windows server bundle intact: their helpers, resources, and web assets are required alongside the executables.

For build-time version changes, keep `/opt/image-versions.json` consistent with the installed binaries and extensions. CI resolves current upstream versions and passes explicit build arguments; Dockerfile defaults support local builds.

Amazon Linux includes `curl-minimal`; installing `curl` directly conflicts with it. The supported Linux architectures are x86_64 and aarch64. The image runs as root, so the desktop Compose service explicitly passes Electron's `--no-sandbox` flag.

## Publishing changes

For tag selection, upstream resolution, snapshot naming, or update detection, read [scripts/image_release.py](scripts/image_release.py) and its tests. For execution and promotion order, read [.github/workflows/publish-image.yml](.github/workflows/publish-image.yml).

Each image uses its own product version and registry namespace. T3 also tracks both provider versions and the Codex VSIX version. A provider update rebuilds T3 without changing T3's primary version. Unique snapshot tags record the full combination and workflow run.

Promote aliases only after runtime/artifact checks and provenance succeed, and only for the current upstream combination at the current `main` revision. Record Git success markers after promotion so failed publications remain eligible for retry. Scheduled checks verify registry aliases as well as the marker; stale aliases require repair even if their version was published before. Checks run independently for each target. Marker tags use the `images/` namespace and do not trigger release builds.

## Verification

For release-planning changes:

```bash
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

After rebuilding an affected target:

```bash
scripts/smoke-test-image.sh claude claude-code:latest
scripts/smoke-test-image.sh codex codex:latest
scripts/smoke-test-image.sh t3 t3-code:latest
```

Smoke tests verify Linux startup, image separation, VSIX identity/platform, Windows executable formats, and T3 web assets. Windows binaries require a Windows host for execution tests.

For Claude download-source changes, use `.claude/skills/verifying-claude-source/scripts/verify-source.sh`. It verifies the Dockerfile's `GCS_BUCKET` variable against the official installer; the variable name is retained even though the release host is now `downloads.claude.ai`.
