ARG T3CODE_VERSION=0.1.9
ARG CODEX_VERSION=0.169.0

# Unpack the desktop package on the builder's architecture. Executing a target
# AppImage extractor fails under QEMU, even when ordinary target binaries work.
FROM --platform=$BUILDPLATFORM amazonlinux:2023 AS t3-desktop
ARG T3CODE_VERSION
ARG TARGETARCH
RUN dnf install -y binutils tar xz && dnf clean all
WORKDIR /tmp
RUN set -eu; \
    case "$TARGETARCH" in amd64|arm64) ;; *) echo "Unsupported architecture" >&2; exit 1 ;; esac; \
    curl -fsSL "https://github.com/pingdotgg/t3code/releases/download/v${T3CODE_VERSION}/T3-Code-${T3CODE_VERSION}-${TARGETARCH}.deb" -o /tmp/t3.deb; \
    ar p /tmp/t3.deb data.tar.xz > /tmp/data.tar.xz; \
    mkdir -p /tmp/desktop; \
    tar -xJf /tmp/data.tar.xz -C /tmp/desktop ./opt; \
    set -- /tmp/desktop/opt/*; \
    test "$#" -eq 1; \
    mv "$1" /tmp/t3-desktop; \
    test -x /tmp/t3-desktop/t3code; \
    test -s /tmp/t3-desktop/resources/app.asar; \
    rm /tmp/t3.deb /tmp/data.tar.xz

FROM amazonlinux:2023 AS base
# Install dependencies
RUN dnf install -y \
    git \
    nodejs \
    npm \
    file \
    which \
    tar \
    gzip \
    unzip \
    && dnf clean all

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo | tee /etc/yum.repos.d/gh-cli.repo && \
    dnf install -y gh && \
    dnf clean all

# Install pyright (Python static type checker)
RUN npm install -g pyright

WORKDIR /workspace

FROM base AS claude
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
    # Optional: VSIX extension from Open VSX (platform-independent) -- warn, do not fail
    mkdir -p /opt/claude-code; \
    VSIX_URL=$(curl -fsSL "https://open-vsx.org/api/anthropic/claude-code/latest" \
        | node -p 'JSON.parse(require("fs").readFileSync(0, "utf8")).files.download' 2>/dev/null) \
        || VSIX_URL=""; \
    if [ -z "$VSIX_URL" ] || ! curl -fsSL "$VSIX_URL" -o /opt/claude-code/claude-code.vsix; then \
        echo "WARNING: VSIX not available from Open VSX; skipping" >&2; \
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

RUN /usr/local/bin/claude --version | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>require("fs").writeFileSync("/opt/image-versions.json",JSON.stringify({claude:s.trim().split(/\s+/)[0]})))'
ENTRYPOINT ["/usr/local/bin/claude"]
CMD ["--help"]

# Keep the complete Windows package, including helper executables/resources.
FROM base AS codex-windows
ARG CODEX_VERSION
RUN set -eu; \
    mkdir -p /opt/codex/win32-x64 /tmp/codex-windows; \
    cd /tmp/codex-windows; \
    ARCHIVE=$(npm pack --quiet "@openai/codex@${CODEX_VERSION}-win32-x64"); \
    tar -xzf "$ARCHIVE"; \
    cp -a package/vendor/x86_64-pc-windows-msvc/. /opt/codex/win32-x64/; \
    test -s /opt/codex/win32-x64/bin/codex.exe

FROM base AS t3-windows
ARG T3CODE_VERSION
RUN set -eu; \
    RELEASE_URL="https://github.com/pingdotgg/t3code/releases/download/v${T3CODE_VERSION}"; \
    ARCHIVE="t3-${T3CODE_VERSION}-win32-x64.zip"; \
    mkdir -p /opt/t3-code/win32-x64; \
    cd /tmp; \
    curl -fsSL "${RELEASE_URL}/SHA256SUMS" -o SHA256SUMS; \
    curl -fsSL "${RELEASE_URL}/${ARCHIVE}" -o "$ARCHIVE"; \
    grep " ${ARCHIVE}$" SHA256SUMS | sha256sum -c -; \
    unzip -tq "$ARCHIVE"; \
    unzip -q "$ARCHIVE" -d /opt/t3-code/win32-x64; \
    curl -fsSL "${RELEASE_URL}/latest.yml" -o desktop-release.yml; \
    curl -fsSL "${RELEASE_URL}/T3-Code-${T3CODE_VERSION}-x64.exe" -o /opt/t3-code/win32-x64/T3-Code-Setup.exe; \
    node -e 'const fs=require("fs"),crypto=require("crypto");const metadata=fs.readFileSync("desktop-release.yml","utf8");const expected=metadata.match(/url: T3-Code-[^\n]+-x64\.exe\s+sha512: (\S+)/)?.[1];const actual=crypto.createHash("sha512").update(fs.readFileSync("/opt/t3-code/win32-x64/T3-Code-Setup.exe")).digest("base64");if(!expected||actual!==expected)throw Error("T3 desktop checksum mismatch");console.log("Windows T3 desktop checksum verified")'

FROM base AS codex-runtime
ARG CODEX_VERSION
RUN npm install -g "@openai/codex@${CODEX_VERSION}" && codex --version

FROM codex-runtime AS codex
# The Codex extension ships native binaries, so select the image architecture.
ARG CODEX_VSIX_VERSION=26.51111.21308
RUN set -eu; \
    case "$(uname -m)" in \
        x86_64) VSIX_PLATFORM=linux-x64 ;; \
        aarch64) VSIX_PLATFORM=linux-arm64 ;; \
        *) echo "Unsupported architecture" >&2; exit 1 ;; \
    esac; \
    mkdir -p /opt/codex; \
    VSIX_URL=$(curl -fsSL "https://open-vsx.org/api/openai/chatgpt/${VSIX_PLATFORM}/${CODEX_VSIX_VERSION}" \
        | node -p 'JSON.parse(require("fs").readFileSync(0, "utf8")).files.download'); \
    curl -fsSL "$VSIX_URL" -o /opt/codex/codex.vsix; \
    unzip -tq /opt/codex/codex.vsix; \
    unzip -p /opt/codex/codex.vsix extension/package.json \
        | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const p=JSON.parse(s);if(p.publisher!=="openai"||p.name!=="chatgpt")process.exit(1);console.log("Codex VSIX",p.version)})'
COPY --from=codex-windows /opt/codex/win32-x64 /opt/codex/win32-x64
RUN set -eu; \
    VSIX_URL=$(curl -fsSL "https://open-vsx.org/api/openai/chatgpt/win32-x64/${CODEX_VSIX_VERSION}" \
        | node -p 'JSON.parse(require("fs").readFileSync(0, "utf8")).files.download'); \
    curl -fsSL "$VSIX_URL" -o /opt/codex/win32-x64/codex.vsix; \
    unzip -tq /opt/codex/win32-x64/codex.vsix
RUN codex --version > /tmp/codex-version && \
    unzip -p /opt/codex/codex.vsix extension/package.json \
        | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const fs=require("fs");fs.writeFileSync("/opt/image-versions.json",JSON.stringify({codex:fs.readFileSync("/tmp/codex-version","utf8").trim().split(/\s+/)[1],codex_vsix:JSON.parse(s).version}))})' && \
    rm /tmp/codex-version
ENTRYPOINT ["codex"]
CMD []

FROM codex-runtime AS t3
COPY --from=claude /usr/local/bin/claude /usr/local/bin/claude
# Self-contained T3 Code server, including its browser UI. Keep the runtime
# outside /root/.t3 so mounting persistent user data does not hide the install.
ARG T3CODE_VERSION
RUN curl -fsSL https://t3.codes/install.sh -o /tmp/install-t3.sh && \
    T3CODE_HOME=/opt/t3-code T3CODE_INSTALL_BIN_DIR=/usr/local/bin \
    T3CODE_VERSION="${T3CODE_VERSION}" sh /tmp/install-t3.sh && \
    rm /tmp/install-t3.sh && \
    t3 --version

# Electron desktop dependencies (GTK pulls in the X11 and accessibility libs).
RUN dnf install -y gtk3 nss alsa-lib cups-libs mesa-libgbm libxkbcommon \
    libXScrnSaver libXtst dejavu-sans-fonts xdg-utils desktop-file-utils \
    shared-mime-info && dnf clean all
COPY --from=t3-desktop /tmp/t3-desktop /opt/t3-desktop
RUN ln -s /opt/t3-desktop/t3code /usr/local/bin/t3-desktop

# Windows payloads can be extracted for use on a Windows x64 host.
COPY --from=codex /opt/codex/win32-x64 /opt/codex/win32-x64
COPY --from=claude /opt/claude-code/win32-x64 /opt/claude-code/win32-x64
COPY --from=t3-windows /opt/t3-code/win32-x64 /opt/t3-code/win32-x64
COPY --from=claude /opt/image-versions.json /tmp/claude-versions.json
COPY --from=codex /opt/image-versions.json /tmp/codex-versions.json
RUN node -e 'const fs=require("fs"),cp=require("child_process");const versions={...JSON.parse(fs.readFileSync("/tmp/claude-versions.json")),...JSON.parse(fs.readFileSync("/tmp/codex-versions.json")),t3:cp.execFileSync("t3",["--version"],{encoding:"utf8"}).trim().split(/\s+/).pop().replace(/^v/,"")};fs.writeFileSync("/opt/image-versions.json",JSON.stringify(versions))' && \
    rm /tmp/claude-versions.json /tmp/codex-versions.json

EXPOSE 3773
ENTRYPOINT ["t3"]
CMD ["serve", "--host", "0.0.0.0", "--port", "3773"]

# Keep an untargeted docker build compatible with the original Claude image.
FROM claude AS default
