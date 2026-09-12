FROM node:20-slim

# 1. Install system utilities, build tools, fast search utilities, and language runtimes
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
    # High-performance search tools used by Claude Code for quick codebase inspection
    ripgrep \
    fd-find \
    # Language runtimes and tools (Go, PHP, PostgreSQL client)
    golang-go \
    php-cli \
    php-curl \
    php-mbstring \
    php-xml \
    php-zip \
    php-pgsql \
    php-sqlite3 \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# 2. Configure UTF-8 locale to prevent encoding issues in Git logs and CLI output
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# 3. Install PHP Composer and Claude Code CLI globally
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN npm install -g @anthropic-ai/claude-code

# 4. Create a non-root devuser with passwordless sudo rights inside the container
RUN useradd -m -s /bin/bash devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER devuser
WORKDIR /projects

# 5. Set up Go environment paths for installed binaries and modules
ENV GOPATH=/home/devuser/go
ENV PATH=$PATH:$GOPATH/bin

# 6. Global Git setup: GitLab HTTPS rewrite, agent identity, safe directory, and local ignore rules
RUN git config --global url."https://<username>:<token>@gitlab.com/".insteadOf "git@gitlab.com:" && \
    git config --global user.name "Claude Agent" && \
    git config --global user.email "claude-agent@local.sandbox" && \
    git config --global safe.directory '*' && \
    git config --global core.excludesfile ~/.gitignore_global && \
    echo ".claude/settings.local.json" > /home/devuser/.gitignore_global

ENTRYPOINT ["/bin/bash"]
