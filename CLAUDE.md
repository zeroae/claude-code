# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project provides a containerized environment for running Claude Code CLI using Amazon Linux 2023. The container automatically downloads and installs the latest version of Claude Code, making it easy to run in isolated environments.

## Architecture

### Container Design

- **Base Image**: Amazon Linux 2023 (official AWS Linux distribution)
- **Package Manager**: DNF (Dandified YUM)
- **Claude Code CLI**: Downloaded from Google Cloud Storage bucket at build time
- **Platform Detection**: Automatically detects x64 or ARM64 architecture

### Build Process

1. Base image with Amazon Linux 2023
2. Install dependencies (git, nodejs, npm)
3. Download Claude Code binary for the detected platform
4. Download Claude Code VSIX extension (platform-independent)
5. Install CLI to `/usr/local/bin/claude` and VSIX to `/opt/claude-code/claude-code.vsix`
6. Set `/workspace` as working directory
7. Configure entrypoint to run `claude` command

### Runtime Configuration

The Docker Compose setup mounts:
- Current directory to `/workspace` (your code)
- `~/.claude` to `/root/.claude` (Claude Code settings)
- Passes through `ANTHROPIC_API_KEY` environment variable

## Common Commands

### Using Pre-built Images

```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/zeroae/claude-code:latest

# Run with pre-built image
docker run --rm -v "$(pwd):/workspace" -e ANTHROPIC_API_KEY ghcr.io/zeroae/claude-code:latest --version

# Interactive mode with pre-built image
docker run --rm -it -v "$(pwd):/workspace" -v ~/.claude:/root/.claude -e ANTHROPIC_API_KEY ghcr.io/zeroae/claude-code:latest
```

### Building and Running Locally

```bash
# Build the container
docker compose build

# Run Claude Code
docker compose run --rm claude [arguments]

# Examples:
docker compose run --rm claude --version
docker compose run --rm claude --help
docker compose run --rm claude  # Interactive mode
```

### Development

```bash
# Get a shell inside the container
docker compose run --rm --entrypoint bash claude

# Test Claude Code installation
docker run --rm claude-code:latest --version

# Rebuild from scratch
docker compose build --no-cache
```

### Customization

To modify the Dockerfile:
- Change base image in `FROM` line (currently `amazonlinux:2023`)
- Adjust dependencies in the `dnf install` command
- Platform detection is in the Claude Code download RUN step

## Key Implementation Notes

### Claude Code Binary Distribution

Claude Code is distributed via Google Cloud Storage:
- Base URL: `https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases`
- Version endpoint: `${BASE_URL}/latest` (returns version string like "2.1.17")
- Binary endpoint: `${BASE_URL}/${VERSION}/${PLATFORM}/claude`

**Source Discovery**: The GCS bucket URL is extracted from the official install script at `https://claude.ai/install.sh`. This is documented and automated in the Claude Code skill:
- `.claude/skills/verifying-claude-source/` - Self-contained skill with bundled verification script

To verify the URL is still current:
```bash
# Run the bundled script
.claude/skills/verifying-claude-source/scripts/verify-source.sh

# Or use the Claude Code skill
/verifying-claude-source
```

Supported platforms for Linux:
- `linux-x64` - Standard glibc x86_64
- `linux-arm64` - Standard glibc ARM64
- `linux-x64-musl` - Alpine/musl x86_64
- `linux-arm64-musl` - Alpine/musl ARM64

This project uses the standard glibc builds since Amazon Linux uses glibc.

### Claude Code VSIX Extension

The container includes the Claude Code VS Code extension (VSIX) at `/opt/claude-code/claude-code.vsix`.

**VSIX Distribution:**
- Location in GCS: `${BASE_URL}/${VERSION}/vscode/claude-code.vsix`
- Size: ~29MB (29,189,479 bytes)
- Platform: Universal (works on all architectures)
- Version: Matches CLI binary version (both use `/latest` endpoint)

**Extract VSIX from container:**
```bash
# Using docker run with pre-built image
docker run --rm -v "$(pwd):/output" --entrypoint cp \
  ghcr.io/zeroae/claude-code:latest \
  /opt/claude-code/claude-code.vsix /output/claude-code.vsix

# Using docker compose
docker compose run --rm -v "$(pwd):/output" --entrypoint cp claude \
  /opt/claude-code/claude-code.vsix /output/claude-code.vsix
```

**Install in VS Code:**
```bash
# Install the extracted VSIX
code --install-extension ./claude-code.vsix

# Or install directly from VS Code
# Extensions: Install from VSIX... (Cmd+Shift+P)
```

**Verify VSIX in container:**
```bash
# Check VSIX exists and size
docker compose run --rm --entrypoint ls claude -lh /opt/claude-code/claude-code.vsix

# Verify it's a valid zip archive
docker compose run --rm --entrypoint file claude /opt/claude-code/claude-code.vsix
```

### Amazon Linux Package Management

Amazon Linux 2023 includes these packages by default:
- `bash`
- `curl` (as curl-minimal)
- `ca-certificates`

We only need to install:
- `git` - For repository operations
- `nodejs` - Runtime dependency for Claude Code
- `npm` - Package manager (comes with nodejs)

### API Key Configuration

Claude Code requires an Anthropic API key. This can be provided via:
1. Environment variable: `ANTHROPIC_API_KEY`
2. Config file: `~/.claude/config.json`
3. Interactive login: `claude login`

The Docker Compose setup handles option 1 automatically by passing through the environment variable.

## Dependencies

### Build Time
- Docker 20.10+
- Internet connection (to download Claude Code binary)

### Runtime
- Docker 20.10+
- Docker Compose 2.0+
- Anthropic API key

## Troubleshooting

### Build Issues

**Problem**: DNF package conflicts
**Solution**: Amazon Linux pre-installs curl-minimal which conflicts with curl. Remove curl from the dependency list or use `dnf install -y --allowerasing curl`.

**Problem**: Architecture detection fails
**Solution**: The Dockerfile only supports x86_64 and aarch64. Other architectures need manual platform specification.

### Runtime Issues

**Problem**: API key not found
**Solution**: Set `ANTHROPIC_API_KEY` environment variable or mount `~/.claude` with your configuration.

**Problem**: Permission denied on workspace files
**Solution**: The container runs as root. Files created will be owned by root. Consider adding a user or using `--user` flag.

### Version Updates

To update to the latest Claude Code version:
```bash
docker compose build --no-cache
```

The build process fetches the latest version automatically from the `/latest` endpoint.

## CI/CD

### Automated Releases

The container images are automatically built and published when new Claude Code versions are released.

**Process:**
1. GitHub Actions checks daily for new Claude Code versions
2. When a new version is detected (e.g., `2.1.17`):
   - Creates a git tag with the version number (e.g., `v2.1.17`)
   - Triggers container build for both amd64 and arm64
   - Publishes images with multiple tags:
     - `v2.1.17` (exact version)
     - `v2.1` (minor version)
     - `v2` (major version)
     - `latest` (always points to latest release)

**Image Tags:**
```bash
# Use specific version
docker pull ghcr.io/zeroae/claude-code:v2.1.17

# Use minor version (receives patch updates)
docker pull ghcr.io/zeroae/claude-code:v2.1

# Use major version (receives minor and patch updates)
docker pull ghcr.io/zeroae/claude-code:v2

# Use latest (always latest stable release)
docker pull ghcr.io/zeroae/claude-code:latest
```

**Manual Version Check:**
To manually trigger a version check without waiting for the daily schedule:
1. Go to Actions → Check Claude Code Version
2. Click "Run workflow"
3. If a new version exists, a git tag will be created and build will trigger

### GitHub Actions Workflows

The project includes two GitHub Actions workflows:

#### Version Detection ([.github/workflows/check-claude-version.yml](.github/workflows/check-claude-version.yml))

Automatically detects new Claude Code versions and creates git tags:

- **Schedule**: Runs daily at midnight UTC
- **Manual Trigger**: Can be manually triggered via workflow_dispatch
- **Process**: Fetches latest version from GCS bucket, compares against existing tags, creates new tag if needed

#### Build and Publish ([.github/workflows/publish-container.yml](.github/workflows/publish-container.yml))

Builds and publishes container images:

1. **Verifies Claude Code source URL** - Runs the bundled verification script to ensure the Dockerfile uses the current GCS bucket URL
2. **Builds multi-platform images** - Creates images for both `linux/amd64` and `linux/arm64`
3. **Publishes to GitHub Container Registry** - Pushes images to `ghcr.io/zeroae/claude-code`
4. **Generates attestations** - Creates build provenance attestations for security

**Triggers:**
- Push to `main` branch → publishes as `main` tag
- Push version tags (e.g., `v2.1.17`) → publishes as `v2.1.17`, `v2.1`, `v2`, and `latest` tags
- Pull requests → builds but doesn't publish (for testing)
- Manual workflow dispatch → can be triggered manually

**Published tags:**
- `vX.Y.Z` - Specific Claude Code version (e.g., `v2.1.17`)
- `vX.Y` - Minor version (e.g., `v2.1`)
- `vX` - Major version (e.g., `v2`)
- `latest` - Latest stable release
- `main` - Latest commit on main branch

**Permissions required:**
- `contents: read` - Read repository contents
- `packages: write` - Publish to GitHub Container Registry

The workflow uses `GITHUB_TOKEN` for authentication, which is automatically provided by GitHub Actions.
