# 🛡️ AgentBunker

> **The heavy-duty, batteries-included sandbox for autonomous AI coding agents.**  
> Run Claude Code, Antigravity (`agy`), and OpenAI Codex in full autonomous mode (`--dangerously-skip-permissions`) without risking your host machine, SSH keys, or private networks.

---

## Why AgentBunker?

Running AI coding agents on full auto-pilot is a massive productivity boost — no more clicking `y` to approve every file edit or bash command. However, running autonomous agents directly on your host machine is a critical security hazard:
- Agents have access to `~/.ssh/id_rsa`, `~/.aws/credentials`, `~/.config/gcloud`, and macOS Keychain.
- Malicious packages or prompt injections can exfiltrate credentials or connect to production databases.
- Rogue commands can run `rm -rf` or mutate host system files.

**AgentBunker** provides an isolated, hardened Linux environment where agents can run with full autonomy. It is **monstrous and batteries-included by design**: all major runtimes, package managers, local email testing, headless browsers, and database clients are pre-installed.

---

## Features

- **Physical Host Isolation:** `~/.ssh`, macOS Keychain, host credentials, and system files are never mounted.
- **Full Autonomy:** Pre-configured for `--dangerously-skip-permissions` so agents can work autonomously and uninterrupted.
- **Strict Egress Firewall (`iptables`):**
  - **SSH Outbound (Port 22):** Permanently blocked (agents cannot jump to remote servers).
  - **External Cloud Databases:** Blocks outgoing public connections on ports `5432`, `3306`, `27017`, `6379`.
  - **Self-Defense:** The agent user (`devuser`) has sudo rights for dev packages, but is explicitly restricted from modifying `iptables` or firewall rules.
- **Monstrous Tooling Stack (Pre-installed):**
  - **Runtimes:** Node.js 20, Python 3 + `venv` & `pip`, Go, PHP-CLI (with pgsql, sqlite3, curl, mbstring extensions).
  - **Package Managers:** `npm`, `composer`, `pip`, Go modules.
  - **Testing & Quality:** Headless Playwright (with all Chromium OS libraries), Mailpit (local SMTP & Web UI).
  - **Search & DB:** `ripgrep`, `fd`, PostgreSQL client (`psql`).
- **Native CLI Developer Experience:**
  - Auto-detects your current directory: run `bunker` from `~/projects/my-app` on macOS, and the container automatically starts and mounts you inside `/projects/my-app`.
  - Multiple root project folders supported (e.g., `~/projects`, `~/work`).
- **Persistent State & Caches:** Claude login tokens, npm cache, Go modules, Composer cache, and Playwright browser binaries persist across restarts in `~/.claude-cache/`.
- 🔌 **Host & Container Database Bridging:** Pre-configured to reach databases on macOS host (`host.docker.internal`) or across Docker networks.

---

## Supported Agents & Roadmap

- [x] **Claude Code CLI** (`@anthropic-ai/claude-code`) — fully supported out of the box.
- [ ] **Google Antigravity** (`agy`) — upcoming.
- [ ] **OpenAI Codex CLI** — upcoming.
- [ ] Multi-flavor minimal image builds.

---

## Security Model & Firewall

| Resource | Access Policy | Implementation |
| :--- | :--- | :--- |
| **Host SSH Keys (`~/.ssh`)** | **Physically Isolated** | Not mounted into container |
| **Host Keychain & OS Files** | **Physically Isolated** | Runs in isolated Docker Linux VM |
| **Remote SSH Servers (Port 22)** | **BLOCKED** | Rejected by container `iptables` |
| **External Cloud Databases** | **BLOCKED** | Public IP ports `5432`, `3306`, `27017`, `6379` rejected |
| **Local Databases & Host** | **Configurable** | Controlled via `ALLOW_LOCAL_DB_ACCESS` (default: allowed) |
| **Package Managers & Web** | **ALLOWED** | Outbound ports `80`, `443` (HTTPS/HTTP), `53` (DNS) |
| **Firewall Tampering** | **PREVENTED** | `devuser` sudo policy forbids running `iptables` / `nft` |

---

## 🚀 Getting Started

### 1. Configure Environment (`.env`)

Copy `.env.template` to `.env`:
```bash
cp .env.template .env
```

Configure your project directories, firewall policies, and optional Git tokens:
```env
# Comma-separated list of project directories to mount into the container
# Supports multiple directories, tilde expansion (~), and absolute paths.
PROJECTS_DIRS=~/projects, ~/work

# Allow or block access to host machine and local databases (true/false)
ALLOW_LOCAL_DB_ACCESS=true

# GitLab credentials (optional)
GITLAB_USER=oauth2
GITLAB_TOKEN=your_token_here
```

Each folder is mounted under its basename (e.g. `~/projects` -> `/projects`, `~/work` -> `/work`).

### 2. Build the Bunker Image

```bash
./start.sh build
```

### 3. Add Shell Helpers

Add this line to your `~/.zshrc` if you use macOS (or `~/.bashrc` for Linux):
```bash
source <path-to-agent-bunker>/start.sh
```

Reload your shell:
```bash
source ~/.zshrc
```

---

## Usage

### Launching Autonomous Agent (`bunker`)

Navigate to any project directory inside your configured `PROJECTS_DIRS` and run `bunker`:

```bash
cd ~/projects/my-cool-app
bunker
```

- Automatically starts the `agent-bunker` container in the background if not already running.
- Automatically maps your current host directory to the container path (`/projects/my-cool-app`).
- Executes Claude Code with `--dangerously-skip-permissions` for seamless autonomous operation.

You can also target specific subdirectories from anywhere:
```bash
bunker my-cool-app
bunker my-cool-app/backend
```

### Interactive Shell (`bunker-shell`)

To jump into a bash terminal inside the container:
```bash
bunker-shell [project_subpath]
```

### Container Lifecycle

```bash
# Start container in background
./start.sh

# Stop container
./start.sh stop
```

---

## Connecting to Local Databases

### Option A: PostgreSQL on macOS Host (Homebrew)

If PostgreSQL runs directly on macOS:

1. **`postgresql.conf`** (usually in `/opt/homebrew/var/postgresql@16/`):
   ```ini
   listen_addresses = '*'
   ```

2. **`pg_hba.conf`**:
   Docker Desktop for macOS routes connections through the host gateway (`192.168.65.0/24` or Docker bridge subnets):
   ```text
   host    all             all             192.168.65.0/24         trust
   host    all             all             172.16.0.0/12           trust
   ```
   > **Security Tip:** Rather than connecting with the `postgres` superuser, create a dedicated development user (e.g., `agent_dev`) with permissions granted only to the specific databases needed for your projects.

3. Restart PostgreSQL:
   ```bash
   brew services restart postgresql@16
   ```

### Option B: Database in Another Docker Container

If your database runs in a separate Docker container:
- **Published Port:** If it publishes `-p 5432:5432`, connect via `host.docker.internal:5432`.
- **Shared Network:** Connect both containers to the same Docker network:
  ```bash
  docker network create dev-net
  docker network connect dev-net db-postgres-1
  docker network connect dev-net agent-bunker
  ```
  The agent can now reach `db-postgres-1:5432` directly.

---

## Pre-installed Tooling & Ports

- **Mailpit:** Pre-installed binary at `/usr/local/bin/mailpit`.
  - Web UI: [http://localhost:18025](http://localhost:18025)
  - SMTP: `localhost:11025`
- **Playwright:** System dependencies installed; browser binaries are stored persistently in `~/.claude-cache/.playwright-docker-cache`.
- **Forwarded Dev Ports:**
  - `13000`: React / Next.js
  - `15173`: Vite
  - `18000`: Laravel / PHP / Python
  - `18080`: Go / APIs
  - `18025` / `11025`: Mailpit Web & SMTP
- **Runtimes & CLI Tools:** Node 20, Python 3 + venv, Go, PHP + Composer, PostgreSQL client (`psql`), `ripgrep`, `fd`.

---

## License

[MIT License](LICENSE) © 2026 Nick
