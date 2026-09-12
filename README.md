# Environment Isolation for Claude CLI

Docker-based sandboxing for Claude Code CLI on macOS. It isolates host SSH keys, system credentials, and private files, while providing full autonomy (`--dangerously-skip-permissions`) within mounted project directories.

---

## Security Model & Firewall

| Resource | Access Policy | Implementation |
| :--- | :--- | :--- |
| **Host SSH Keys (`~/.ssh`)** | **Physically Isolated** | Not mounted into container |
| **Host Keychain & OS files** | **Physically Isolated** | Container runs in Linux VM |
| **Remote SSH Servers (Port 22)** | **BLOCKED** | Rejected by container `iptables` |
| **External Cloud Databases** | **BLOCKED** | Public IP ports `5432`, `3306`, `27017`, `6379` rejected |
| **Local Databases & Host** | **Configurable** | Controlled via `ALLOW_LOCAL_DB_ACCESS` (allowed by default; blocked when `false`) |
| **Package Managers & Web** | **ALLOWED** | Outbound ports `80`, `443` (HTTPS/HTTP), `53` (DNS) |

---

## Prerequisites & Host Configuration

### 1. Configure Environment (`.env`)

Copy `.env.template` to `.env`:
```bash
cp .env.template .env
```

Edit `.env` to configure your project directories, network policies, and GitLab token:
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

Each listed folder is mounted into the container under its basename (e.g. `~/projects` -> `/projects`, `~/work` -> `/work`). When running `cclaude`, the target working directory is automatically detected from where you run the command.

### 2. GitLab Access Token

Create a Personal Access Token in GitLab with read access (`read_api`, `read_repository`) for your project group, and set `GITLAB_TOKEN` in `.env`.


### 3. Local PostgreSQL on macOS Host (Homebrew)

If PostgreSQL runs directly on macOS:

1. **`postgresql.conf`** (usually in `/opt/homebrew/var/postgresql@16/`):
   ```ini
   listen_addresses = '*'
   ```

2. **`pg_hba.conf`**:
   Docker Desktop for macOS routes connections through the host gateway. Depending on your Docker Desktop networking configuration, requests may originate from `192.168.65.0/24` or Docker bridge subnets. Add:
   ```text
   # Allow Docker Desktop gateway and container bridge subnets
   host    all             all             192.168.65.0/24         trust
   host    all             all             172.16.0.0/12           trust
   ```
   > **Security Tip:** Rather than connecting with the `postgres` superuser, create a dedicated development user (e.g., `claude_dev`) with permissions granted only to the specific databases needed for your projects.

3. Restart PostgreSQL:
   ```bash
   brew services restart postgresql@16
   ```

### 4. Databases Running in Docker Containers

If your database runs in a separate Docker container (e.g., `db-postgres-1`):
- **Option A (Published Port):** If the database container publishes `-p 5432:5432`, Claude connects seamlessly via `host.docker.internal:5432`.
- **Option B (Shared Docker Network):** Connect both containers to the same network:
  ```bash
  docker network create dev-net
  docker network connect dev-net db-postgres-1
  docker network connect dev-net claude-workspace
  ```
  Claude can then connect directly to `db-postgres-1:5432`.

---

## Usage

### 1. Build the Docker Image

```bash
./start.sh build
```

### 2. Add Shell Helpers to `~/.zshrc`

Add this line to your `~/.zshrc`:
```bash
source <path-to-this-repo>/start.sh
```
Reload your shell:
```bash
source ~/.zshrc
```

### 3. Launching Claude Code

Navigate to any project directory under `~/projects` and run `cclaude`:

```bash
cd ~/projects/my-app
cclaude
```
- It automatically starts the container if it's not already running.
- It sets the working directory inside the container to `/projects/my-app`.
- It executes Claude Code with `--dangerously-skip-permissions` for seamless autonomous operation.

You can also specify a project directory explicitly from anywhere:
```bash
cclaude my-app
cclaude my-app/backend
```

### 4. Interactive Bash Shell

To enter the container shell manually:
```bash
cclaude-shell [project_subpath]
```

### 5. Managing the Background Container

```bash
# Start container
./start.sh

# Stop container
./start.sh stop
```

---

## Pre-installed Tooling & Ports

- **Mailpit:** Pre-installed binary at `/usr/local/bin/mailpit`.
  - Web UI: [http://localhost:8025](http://localhost:8025)
  - SMTP: `localhost:1025`
- **Playwright:** System dependencies installed; browser binaries are stored persistently in `~/.claude-cache/.playwright-docker-cache`.
- **Forwarded Dev Ports:**
  - `3000`: React / Next.js
  - `5173`: Vite
  - `8000`: Laravel / PHP / Python
  - `8080`: Go / APIs
  - `8025` / `1025`: Mailpit Web & SMTP
- **Runtimes:** Node 20, Go, Python 3 + venv, PHP (with pgsql & sqlite extensions), PostgreSQL client (`psql`).
