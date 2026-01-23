# Claude Code Container

Run Claude Code in a containerized environment using Amazon Linux 2023.

## Quick Start

### Using pre-built images from GitHub Container Registry

Pre-built multi-architecture images are available from GitHub Container Registry. Images are automatically built daily when new Claude Code versions are released.

```bash
# Pull specific version
docker pull ghcr.io/zeroae/claude-code:v2.1.17

# Pull latest stable release
docker pull ghcr.io/zeroae/claude-code:latest

# Run with specific version
docker run --rm -v "$(pwd):/workspace" -e ANTHROPIC_API_KEY \
  ghcr.io/zeroae/claude-code:v2.1.17 --version

# Start an interactive session with latest
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -v ~/.claude:/root/.claude \
  -e ANTHROPIC_API_KEY \
  ghcr.io/zeroae/claude-code:latest
```

**Available Tags:**
- `vX.Y.Z` - Specific version (e.g., `v2.1.17`)
- `vX.Y` - Minor version, receives patch updates (e.g., `v2.1`)
- `vX` - Major version, receives minor and patch updates (e.g., `v2`)
- `latest` - Latest stable release
- `main` - Latest commit on main branch (development)

### Building locally

```bash
# Build the container
docker compose build

# Run Claude Code (with your workspace mounted)
docker compose run --rm claude --version

# Start an interactive session
docker compose run --rm claude
```

## Requirements

- Docker 20.10+
- Docker Compose 2.0+
- Anthropic API key (set as environment variable)

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
- **Claude Code Version**: 2.1.17 (automatically fetches latest)
- **Platform**: Linux x64/arm64 (auto-detected)
- **Source**: Google Cloud Storage (verified against official install script)

## Maintenance

### Verify Claude Code Source URL

The Dockerfile downloads Claude Code from a Google Cloud Storage bucket. To verify the URL is still current:

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

## Container Registry

Published images are available at:
- **Registry**: `ghcr.io/zeroae/claude-code`
- **Automated Releases**: New images are automatically built daily when Claude Code releases new versions
- **Version Tags**: Container image tags match Claude Code versions (e.g., `v2.1.17`)
- **Flexible Versioning**: Pin to specific versions (`v2.1.17`), minor versions (`v2.1`), major versions (`v2`), or latest

**Automated Process:**
1. GitHub Actions checks daily for new Claude Code versions
2. When detected, creates a git tag matching the version (e.g., `v2.1.17`)
3. Triggers multi-platform build (amd64 and arm64)
4. Publishes with multiple tags for version flexibility

**Workflows:**
- [check-claude-version.yml](.github/workflows/check-claude-version.yml) - Daily version detection
- [publish-container.yml](.github/workflows/publish-container.yml) - Build and publish

## Files

- [Dockerfile](Dockerfile) - Container definition
- [docker-compose.yml](docker-compose.yml) - Docker Compose configuration
- [.github/workflows/publish-container.yml](.github/workflows/publish-container.yml) - CI/CD workflow
- [CLAUDE.md](CLAUDE.md) - Project documentation for Claude Code

## License

MIT
