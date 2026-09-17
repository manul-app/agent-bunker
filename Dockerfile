FROM node:20-bookworm-slim

# 1. Install system utilities, build tools, runtimes, firewall utilities, and playwright dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    jq \
    unzip \
    zip \
    ca-certificates \
    locales \
    build-essential \
    sudo \
    iptables \
    # High-performance search tools
    ripgrep \
    fd-find \
    # Language runtimes and tools (Python, PHP, PostgreSQL client; Go is installed in step 2)
    python3 \
    python3-pip \
    python3-venv \
    php-cli \
    php-curl \
    php-mbstring \
    php-xml \
    php-zip \
    php-pgsql \
    php-sqlite3 \
    postgresql-client \
    # Headless browser dependencies for Playwright / Chromium
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxext6 \
    fonts-liberation \
    && ln -s $(which fdfind) /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# 2. Install the official Go toolchain (Debian bookworm's golang-go is stuck on 1.19)
ARG GO_VERSION=1.27.1
ARG GO_SHA256_AMD64=63d339f0da5ab53635a56f2490a7984dfe12dfcff22ad749f63edaf590168445
ARG GO_SHA256_ARM64=3450b45a3f9ee8568792736a5c5e70a1f2e9b36c35a8f74958c03e51d7d92bec
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) sha="$GO_SHA256_AMD64" ;; \
        arm64) sha="$GO_SHA256_ARM64" ;; \
        *) echo "ERROR: unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    tarball="go${GO_VERSION}.linux-${arch}.tar.gz"; \
    curl -fsSL -o "/tmp/$tarball" "https://go.dev/dl/$tarball"; \
    echo "$sha  /tmp/$tarball" | sha256sum -c -; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf "/tmp/$tarball"; \
    rm "/tmp/$tarball"; \
    /usr/local/go/bin/go version
ENV PATH="/usr/local/go/bin:$PATH"

# 3. Install Mailpit binary
RUN curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | bash

# 4. Configure UTF-8 locale to prevent encoding issues
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# 5. Install PHP Composer, Playwright
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN npm install -g playwright

# 6. Create non-root devuser and configure sudo rights
RUN useradd -m -s /bin/bash devuser && \
    echo "devuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/devuser && \
    echo "devuser ALL=(ALL) !/sbin/iptables, !/sbin/iptables-*, !/usr/sbin/iptables, !/usr/sbin/iptables-*, !/sbin/nft, !/usr/sbin/nft" >> /etc/sudoers.d/devuser && \
    echo "devuser ALL=(ALL) NOPASSWD: /usr/local/bin/setup-firewall.sh" >> /etc/sudoers.d/devuser && \
    chmod 0440 /etc/sudoers.d/devuser

# 7. Copy firewall setup and entrypoint scripts
COPY setup-firewall.sh /usr/local/bin/setup-firewall.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/setup-firewall.sh /usr/local/bin/entrypoint.sh

USER devuser
WORKDIR /projects

# 8. Set Go, Playwright, and local bin PATHs
ENV GOPATH=/home/devuser/go
ENV PLAYWRIGHT_BROWSERS_PATH=/home/devuser/.cache/ms-playwright
ENV PATH="/home/devuser/.local/bin:/home/devuser/.grok/bin:$GOPATH/bin:$PATH"

# 9. Install user-level CLI tools (as devuser) & configure Git
RUN curl -fsSL https://claude.ai/install.sh | bash
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash
RUN curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh | bash
RUN curl -fsSL https://chatgpt.com/codex/install.sh | sh
USER root
RUN CODEX_BIN="$(find /home/devuser/.codex/packages/standalone/releases \
      -type f -name codex -perm -111 2>/dev/null | sort -V | tail -1)" && \
    CODEX_DIR="$(dirname "$CODEX_BIN")" && \
    test -x "$CODEX_DIR/codex" && \
    test -x "$CODEX_DIR/codex-code-mode-host" && \
    cp "$CODEX_DIR/codex" /usr/local/bin/codex && \
    cp "$CODEX_DIR/codex-code-mode-host" /usr/local/bin/codex-code-mode-host && \
    chmod 755 /usr/local/bin/codex /usr/local/bin/codex-code-mode-host
# Grok installs everything under ~/.grok (bin/grok is a symlink into ~/.grok/downloads),
# and that whole tree is hidden by the persistent ~/.grok state mount at runtime, so
# install it under /opt instead. Run as root so the installer also links it into
# /usr/local/bin; the explicit ln keeps that guaranteed if the installer changes.
RUN HOME=/opt/grok bash -c 'curl -fsSL https://x.ai/cli/install.sh | bash' && \
    ln -sf /opt/grok/.grok/bin/grok /usr/local/bin/grok && \
    chown -R devuser:devuser /opt/grok && \
    chmod -R a+rX /opt/grok
USER devuser

# 10. Fail the build early if any agent CLI is missing from PATH
RUN for cli in claude agy qwen codex grok; do \
        command -v "$cli" >/dev/null || { echo "ERROR: $cli not found in PATH"; exit 1; }; \
    done && \
    grok --version

# 11. Configure Git
RUN git config --global user.name "Agent Bunker" && \
    git config --global user.email "agent-bunker@local.sandbox" && \
    git config --global safe.directory '*' && \
    git config --global core.excludesfile ~/.gitignore_global && \
    echo ".claude/settings.local.json" > /home/devuser/.gitignore_global

ENV GITLAB_URL="https://gitlab.com" \
    GITLAB_HOST="gitlab.com"

# 12. Keep Claude Code's config file inside the persisted state directory.
# By default it lives at ~/.claude.json, a sibling of ~/.claude, so it is NOT
# covered by the ~/.claude volume and is lost whenever the container is
# recreated - taking the onboarding flags, the OAuth account record and the
# per-project trust decisions with it. CLAUDE_CONFIG_DIR moves the file to
# $CLAUDE_CONFIG_DIR/.claude.json, i.e. into the mounted directory.
ENV CLAUDE_CONFIG_DIR=/home/devuser/.claude

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]