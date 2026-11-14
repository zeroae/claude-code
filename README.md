# Coding Agent Containers

Three separate Amazon Linux 2023 images share the same development tools:

| Docker target | Local image | Published image | Contents |
| --- | --- | --- | --- |
| `claude` (default) | `claude-code:latest` | `ghcr.io/zeroae/claude-code` | Claude CLI, Claude VSIX, optional Windows CLI |
| `codex` | `codex:latest` | `ghcr.io/zeroae/codex` | Codex CLI, Linux VSIX, Windows x64 CLI bundle and VSIX |
| `t3` | `t3-code:latest` | `ghcr.io/zeroae/t3-code` | T3 server, browser UI, native desktop, Codex and Claude CLIs, plus Windows x64 payloads |

The additional registry images become available when these changes are published. Both T3 interfaces use the same T3 image; the desktop service overrides its server entrypoint.

## Quick Start

### Using pre-built images from GitHub Container Registry

Multi-architecture images are published to GitHub Container Registry. Each product has its own version checks and tags; T3 also rebuilds when its bundled providers change.

```bash
# Pull specific version
docker pull ghcr.io/zeroae/claude-code:2.1.17

# Pull latest stable release
docker pull ghcr.io/zeroae/claude-code:latest

# Run with specific version
docker run --rm -v "$(pwd):/workspace" -e ANTHROPIC_API_KEY \
  ghcr.io/zeroae/claude-code:2.1.17 --version

# Start an interactive session with latest
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -v ~/.claude:/root/.claude \
  -e ANTHROPIC_API_KEY \
  ghcr.io/zeroae/claude-code:latest
```

**Available Tags:**
- `X.Y.Z` - Specific product version (e.g., `2.1.325`, `0.169.0`, or `0.1.9`)
- `X.Y` - Minor version alias (e.g., `2.1`, `0.169`, or `0.1`)
- `X` - Major version alias (e.g., `2` or `0`)
- `latest` - Latest stable release
- `main` - Latest commit on main branch (development)

### Building locally

```bash
# Build all three images
docker compose --profile codex --profile t3 build claude codex t3

# Run Claude Code (with your workspace mounted)
docker compose run --rm claude --version

# Start an interactive session
docker compose run --rm claude
```

## Requirements

- Docker 20.10+
- Docker Compose 2.0+
- Provider authentication: Claude or Codex login, or a supported API key

## Configuration

Set your Anthropic API key:

```bash
export ANTHROPIC_API_KEY="your-api-key"
```

Or create a `.env` file:

```bash
echo "ANTHROPIC_API_KEY=your-api-key" > .env
```

## Usage

### Run Claude Code commands

```bash
# Check version
docker compose run --rm claude --version

# Get help
docker compose run --rm claude --help

# Run Claude Code interactively (with current directory as workspace)
docker compose run --rm claude
```

### Interactive mode

```bash
# Start a bash shell in the container
docker compose run --rm --entrypoint bash claude

# Inside the container, you can run claude commands
claude --version
```

## Architecture

- **Base Image**: Amazon Linux 2023
- **Claude Code Version**: latest by default; override `CLAUDE_VERSION` at build time
- **Platform**: Linux x64/arm64 (auto-detected)
- **Claude Source**: `downloads.claude.ai` (verified against official install script)
- **Shared Tools**: git, nodejs, npm, file, which, tar, gzip, unzip, gh (GitHub CLI), pyright
- **Image Targets**: Claude and Codex each contain their own CLI; T3 contains both CLIs and both T3 UIs

## Codex CLI

Build the Codex image, then authenticate once using device login. Compose stores Codex settings and credentials in the `codex-state` volume, shared with T3 Code.

```bash
docker compose build codex
docker compose run --rm codex login --device-auth
docker compose run --rm codex
```

After publishing, run the Codex image directly:

```bash
docker run --rm -it -v "$(pwd):/workspace" -v codex-state:/root/.codex \
  ghcr.io/zeroae/codex:latest
```

### Codex VS Code extension

The official Codex extension is `openai.chatgpt`. Its VSIX is bundled at `/opt/codex/codex.vsix`, fetched from Open VSX for `linux-x64` or `linux-arm64` to match the image. The build verifies its ZIP integrity and extension identity. The extension version is pinned separately from the CLI.

```bash
docker compose run --rm --entrypoint cp codex /opt/codex/codex.vsix /workspace/codex.vsix
code --install-extension ./codex.vsix
```

Install this Linux VSIX in a compatible Linux VS Code environment, such as a remote container. For Windows x64, extract `/opt/codex/win32-x64/codex.vsix` instead. For macOS, install the matching extension from the editor's Marketplace. Bundling the VSIX does not install a VS Code editor in the image.

## Bundled Windows x64 artifacts

All images run on Linux; their Windows payloads are included for extraction and use on a Windows x64 machine, regardless of the Linux image's architecture.

| Image | Path | Windows payload |
| --- | --- | --- |
| Claude | `/opt/claude-code/win32-x64/claude.exe` | Claude CLI (existing optional download) |
| Codex and T3 | `/opt/codex/win32-x64/` | Full Codex package: `bin/codex.exe`, helper executables, package metadata/resources, and `codex.vsix` |
| T3 | `/opt/claude-code/win32-x64/claude.exe` | Claude CLI |
| T3 | `/opt/t3-code/win32-x64/` | Complete T3 server bundle, its web UI, and `T3-Code-Setup.exe` desktop installer |

```bash
# Extract the complete Codex Windows bundle, preserving its directory layout.
docker compose run --rm --entrypoint cp codex -a /opt/codex/win32-x64 /workspace/codex-windows-x64

# Extract T3's Windows server/desktop and its two providers.
docker compose run --rm --entrypoint cp t3 -a /opt/t3-code/win32-x64 /workspace/t3-windows-x64
docker compose run --rm --entrypoint cp t3 -a /opt/codex/win32-x64 /workspace/codex-windows-x64
docker compose run --rm --entrypoint cp t3 -a /opt/claude-code/win32-x64 /workspace/claude-windows-x64
```

On Windows, keep each bundle intact and add the Codex `bin` directory and the Claude directory to `PATH`. Then run the extracted `t3.exe serve` for the server/web UI, or install the desktop app using `T3-Code-Setup.exe`. Install `codex.vsix` with VS Code's **Extensions: Install from VSIX** command.

New Windows downloads are required: a missing artifact fails the build or smoke test. T3's server ZIP and desktop installer are verified against release checksums. Publishing checks verify Windows executable formats, VSIX identity/platform, and the Windows server's web assets. Windows execution itself requires a Windows host.

## T3 Code server and browser UI

The self-contained T3 Code distribution includes the server and web UI; no desktop display is needed in the container.

```bash
docker compose --profile t3 up -d --build t3
docker compose logs t3
```

Open `http://localhost:3773` in your browser. If prompted, open `http://localhost:3773/pair#token=TOKEN` using the token printed in the server logs (the logged URL may use the container's internal IP). The port is published only on the Docker host's loopback interface. T3 settings and history persist in the `t3-state` volume. Codex authentication is shared with the `codex` service; Claude settings use the existing `~/.claude` mount.

```bash
docker compose exec t3 t3 --version
docker compose --profile t3 down
```

### Native desktop app

The T3 image also includes the Linux Electron desktop app as `t3-desktop`, extracted from the official AppImage so it runs without FUSE. The separate `t3` command runs the standalone server.

On a Linux host running X11 or XWayland, pass the display and its Xauthority file:

```bash
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
docker compose run --build --rm t3-desktop
```

The `desktop` Compose profile mounts the host's X11 socket and authentication file, shares Codex credentials, and persists desktop settings in `t3-desktop-state`. It uses `--no-sandbox` because this image runs as root. A host display is required; Docker Desktop on macOS/Windows needs a separately configured X server. The browser UI above works without a host display.

Claude and Codex are installed and available on `PATH` in the T3 image. Select either in **Settings → Providers**. Codex uses the shared login created above. For Claude, set `ANTHROPIC_API_KEY` or sign in using the mounted Claude configuration:

```bash
docker compose run --rm --entrypoint claude t3 auth login
```

Provider login is required; credentials are supplied at runtime and are not baked into an image.

Local builds use the Dockerfile defaults for Codex, its VSIX, and T3. CI resolves current stable upstream versions independently and passes explicit build arguments. Override local build arguments to pin a different combination:

```bash
docker build --target codex --build-arg CODEX_VERSION=0.169.0 \
  --build-arg CODEX_VSIX_VERSION=26.51111.21308 -t codex:latest .
docker build --target t3 --build-arg CODEX_VERSION=0.169.0 \
  --build-arg T3CODE_VERSION=0.1.9 -t t3-code:latest .
```

Installation references: [Codex CLI](https://learn.chatgpt.com/docs/codex/cli), [T3 Code](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md).

## Maintenance

### Verify Claude Code Source URL

The Dockerfile downloads Claude Code from its official release host. To verify the URL is still current:

**Using the verification script:**
```bash
.claude/skills/verifying-claude-source/scripts/verify-source.sh

# Or with auto-update
.claude/skills/verifying-claude-source/scripts/verify-source.sh --update
```

**Using Claude Code (if running Claude in this project):**
```
/verifying-claude-source
```

This compares the Dockerfile URL against the official install script at `https://claude.ai/install.sh`.

## Publishing and independent version checks

| Image | Product version example | Upstream version source |
| --- | --- | --- |
| `ghcr.io/zeroae/claude-code` | `2.1.325` | Claude release host |
| `ghcr.io/zeroae/codex` | `0.169.0` | `@openai/codex` on npm |
| `ghcr.io/zeroae/t3-code` | `0.1.9` | Stable `pingdotgg/t3code` GitHub release |

Each image gets its own product-version tag, major/minor aliases, and `latest`. Pushes to `main` also update `main`. Docker tags have no leading `v`.

**Check Agent Versions** runs twice daily at 06:37 and 18:37 UTC, with independent jobs for each image:

- Claude updates rebuild Claude and T3.
- Codex CLI updates rebuild Codex and T3.
- Codex VSIX updates (tracked through Open VSX) rebuild Codex and T3.
- T3 releases rebuild T3.

The plain version tags represent the current bundle for that product version. For example, `t3-code:0.1.9` can receive updated providers while T3 remains at 0.1.9. Every build also gets a unique snapshot tag containing the dependency versions, source commit, workflow run, and attempt. A T3 snapshot looks like:

```text
0.1.9-claude2.1.325-codex0.169.0-vsix26.51111.21308-rd2a0eecc17d9-b123456789-1
```

Installed versions are recorded in `/opt/image-versions.json` in every image and in `io.zeroae.version.*` OCI labels on published images:

```bash
docker run --rm --entrypoint cat ghcr.io/zeroae/t3-code:latest /opt/image-versions.json
```

The publisher first pushes the unique snapshot, checks the Linux runtime and Windows artifacts, validates installed versions, and generates provenance. It then promotes the verified digest to the product version tag. Major/minor aliases, `latest`, and `main` move only when the bundle matches current upstream versions and the current `main` commit; historical releases cannot move those aliases backward.

A successful alias publication is recorded with an `images/<target>/...` Git marker containing dependency versions and the source revision. Scheduled checks skip only when that marker exists and all product/major/minor/`latest` tags still have the expected versions and revision on both Linux platforms. Missing or stale tags trigger a rebuild and repair even when a success marker exists. Registry access errors fail the check rather than being treated as missing images. Changes to image source also produce new snapshots. Marker tags do not trigger builds.

### Manual publishing

Use **Publish Containers → Run workflow** and choose `claude`, `codex`, `t3`, or `all`. An explicit `version` applies only to the selected product and requires a single target. Use `update_aliases=false` for historical rebuilds that should leave `latest`, major, and minor aliases untouched.

Source release tags select only their product:

- `v2.1.325` → Claude
- `codex-v0.169.0` → Codex
- `t3-v0.1.9` → T3, with current provider versions

The reusable publisher also accepts explicit provider and VSIX version inputs for a pinned T3 rebuild. Pull requests build all targets without publishing.

### Workflows and checks

- [check-agent-versions.yml](.github/workflows/check-agent-versions.yml): independent scheduled update checks.
- [publish-container.yml](.github/workflows/publish-container.yml): select targets for pushes, PRs, and manual builds.
- [publish-image.yml](.github/workflows/publish-image.yml): resolve dependencies, build, verify, attest, and promote one image.
- [image_release.py](scripts/image_release.py): shared version discovery and tag planning.

```bash
python3 -m unittest discover -s scripts -p 'test_*.py' -v
scripts/smoke-test-image.sh claude claude-code:latest
scripts/smoke-test-image.sh codex codex:latest
scripts/smoke-test-image.sh t3 t3-code:latest
```

## Files

- [Dockerfile](Dockerfile) - Container definition
- [docker-compose.yml](docker-compose.yml) - Docker Compose configuration
- [scripts/smoke-test-image.sh](scripts/smoke-test-image.sh) - CLI, extension, and server/UI checks
- [.github/workflows/publish-container.yml](.github/workflows/publish-container.yml) - CI/CD workflow
- [CLAUDE.md](CLAUDE.md) - Project documentation for Claude Code

## License

MIT
