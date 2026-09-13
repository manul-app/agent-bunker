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
    # Language runtimes and tools (Go, Python, PHP, PostgreSQL client)
    golang-go \
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

# 2. Install Mailpit binary
RUN curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | bash

# 3. Configure UTF-8 locale to prevent encoding issues
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# 4. Install PHP Composer, Playwright
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN npm install -g playwright

# 5. Create non-root devuser and configure sudo rights
RUN useradd -m -s /bin/bash devuser && \
    echo "devuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/devuser && \
    echo "devuser ALL=(ALL) !/sbin/iptables, !/sbin/iptables-*, !/usr/sbin/iptables, !/usr/sbin/iptables-*, !/sbin/nft, !/usr/sbin/nft" >> /etc/sudoers.d/devuser && \
    echo "devuser ALL=(ALL) NOPASSWD: /usr/local/bin/setup-firewall.sh" >> /etc/sudoers.d/devuser && \
    chmod 0440 /etc/sudoers.d/devuser

# 6. Copy firewall setup and entrypoint scripts
COPY setup-firewall.sh /usr/local/bin/setup-firewall.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/setup-firewall.sh /usr/local/bin/entrypoint.sh

USER devuser
WORKDIR /projects

# 7. Set Go, Playwright, and local bin PATHs
ENV GOPATH=/home/devuser/go
ENV PLAYWRIGHT_BROWSERS_PATH=/home/devuser/.cache/ms-playwright
ENV PATH="/home/devuser/.local/bin:$GOPATH/bin:$PATH"

# 8. Install user-level CLI tools (as devuser) & configure Git
RUN curl -fsSL https://claude.ai/install.sh | bash
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash
RUN curl -fsSL https://chatgpt.com/codex/install.sh | sh
USER root
RUN if [ -f /home/devuser/.codex/bin/codex ]; then \
        cp /home/devuser/.codex/bin/codex /usr/local/bin/codex; \
    elif [ -f /home/devuser/.local/bin/codex ]; then \
        cp /home/devuser/.local/bin/codex /usr/local/bin/codex; \
    fi && chmod +x /usr/local/bin/codex || true
USER devuser

RUN git config --global user.name "Agent Bunker" && \
    git config --global user.email "agent-bunker@local.sandbox" && \
    git config --global safe.directory '*' && \
    git config --global core.excludesfile ~/.gitignore_global && \
    echo ".claude/settings.local.json" > /home/devuser/.gitignore_global

ENV GITLAB_URL="https://gitlab.com" \
    GITLAB_HOST="gitlab.com"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]