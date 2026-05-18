FROM amazonlinux:2023

# Install dependencies
RUN dnf install -y \
    git \
    nodejs \
    npm \
    file \
    which \
    && dnf clean all

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo | tee /etc/yum.repos.d/gh-cli.repo && \
    dnf install -y gh && \
    dnf clean all

# Install pyright (Python static type checker)
RUN npm install -g pyright

# Download and install Claude Code CLI, VSIX extension, and Windows binaries
ARG CLAUDE_VERSION=latest
RUN set -eu; \
    GCS_BUCKET="https://downloads.claude.ai/claude-code-releases"; \
    if [ "$CLAUDE_VERSION" = "latest" ]; then \
        VERSION=$(curl -fsSL "${GCS_BUCKET}/latest"); \
    else \
        VERSION="$CLAUDE_VERSION"; \
    fi; \
    # Detect architecture for Linux CLI binary
    case "$(uname -m)" in \
        x86_64) PLATFORM="linux-x64" ;; \
        aarch64) PLATFORM="linux-arm64" ;; \
        *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    echo "Installing Claude Code ${VERSION} for ${PLATFORM}..."; \
    # Required: Linux CLI binary (hard failure if missing)
    curl -fsSL "${GCS_BUCKET}/${VERSION}/${PLATFORM}/claude" -o /usr/local/bin/claude; \
    chmod +x /usr/local/bin/claude; \
    # Optional: VSIX extension (platform-independent) -- warn, do not fail
    mkdir -p /opt/claude-code; \
    if ! curl -fsSL "${GCS_BUCKET}/${VERSION}/vscode/claude-code.vsix" -o /opt/claude-code/claude-code.vsix; then \
        echo "WARNING: VSIX not available for ${VERSION}; skipping" >&2; \
        rm -f /opt/claude-code/claude-code.vsix; \
    fi; \
    # Optional: Windows x64 binary -- warn, do not fail
    mkdir -p /opt/claude-code/win32-x64; \
    if ! curl -fsSL "${GCS_BUCKET}/${VERSION}/win32-x64/claude.exe" -o /opt/claude-code/win32-x64/claude.exe; then \
        echo "WARNING: Windows binary not available for ${VERSION}; skipping" >&2; \
        rm -f /opt/claude-code/win32-x64/claude.exe; \
    fi; \
    echo "Claude Code ${VERSION} installed (linux=${PLATFORM};" \
         "vsix=$( [ -f /opt/claude-code/claude-code.vsix ] && echo yes || echo no );" \
         "win32=$( [ -f /opt/claude-code/win32-x64/claude.exe ] && echo yes || echo no ))"

# Set up working directory
WORKDIR /workspace

# Run Claude Code
ENTRYPOINT ["/usr/local/bin/claude"]
CMD ["--help"]
