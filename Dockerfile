FROM amazonlinux:2023

# Install dependencies
RUN dnf install -y \
    git \
    nodejs \
    npm \
    && dnf clean all

# Download and install Claude Code CLI
RUN GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases" && \
    VERSION=$(curl -fsSL "${GCS_BUCKET}/latest") && \
    # Detect architecture
    case "$(uname -m)" in \
        x86_64) PLATFORM="linux-x64" ;; \
        aarch64) PLATFORM="linux-arm64" ;; \
        *) echo "Unsupported arch: $(uname -m)" && exit 1 ;; \
    esac && \
    echo "Installing Claude Code ${VERSION} for ${PLATFORM}..." && \
    curl -fsSL "${GCS_BUCKET}/${VERSION}/${PLATFORM}/claude" -o /usr/local/bin/claude && \
    chmod +x /usr/local/bin/claude

# Set up working directory
WORKDIR /workspace

# Run Claude Code
ENTRYPOINT ["/usr/local/bin/claude"]
CMD ["--help"]
