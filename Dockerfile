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

# Download and install Claude Code CLI and VSIX extension
RUN GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases" && \
    VERSION=$(curl -fsSL "${GCS_BUCKET}/latest") && \
    # Detect architecture for CLI binary
    case "$(uname -m)" in \
        x86_64) PLATFORM="linux-x64" ;; \
        aarch64) PLATFORM="linux-arm64" ;; \
        *) echo "Unsupported arch: $(uname -m)" && exit 1 ;; \
    esac && \
    echo "Installing Claude Code ${VERSION} for ${PLATFORM}..." && \
    # Download CLI binary
    curl -fsSL "${GCS_BUCKET}/${VERSION}/${PLATFORM}/claude" -o /usr/local/bin/claude && \
    chmod +x /usr/local/bin/claude && \
    # Download VSIX extension (platform-independent)
    mkdir -p /opt/claude-code && \
    curl -fsSL "${GCS_BUCKET}/${VERSION}/vscode/claude-code.vsix" -o /opt/claude-code/claude-code.vsix && \
    echo "Claude Code CLI and VSIX version ${VERSION} installed successfully"

# Set up working directory
WORKDIR /workspace

# Run Claude Code
ENTRYPOINT ["/usr/local/bin/claude"]
CMD ["--help"]
