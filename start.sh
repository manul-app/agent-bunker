#!/bin/bash

# Ensure persistent cache directories exist on host
mkdir -p ~/.claude-cache/.claude-docker-state
mkdir -p ~/.claude-cache/.npm-docker-cache
mkdir -p ~/.claude-cache/.gopath-docker-cache
mkdir -p ~/.claude-cache/.composer-docker-cache
mkdir -p ~/.claude-cache/.playwright-docker-cache

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve comma-separated PROJECTS_DIRS from .env or fallback to $HOME/projects
resolve_project_dirs() {
    local env_override="$PROJECTS_DIRS"
    if [ -f "$SCRIPT_DIR/.env" ]; then
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
    fi
    if [ -n "$env_override" ]; then
        PROJECTS_DIRS="$env_override"
    fi

    local raw_dirs="${PROJECTS_DIRS:-$HOME/projects}"
    IFS=',' read -ra DIRS_ARRAY <<< "$raw_dirs"

    PROJECT_MOUNTS=()
    PROJECT_MAPPINGS=()
    local used_mounts=()

    for raw_dir in "${DIRS_ARRAY[@]}"; do
        # Trim whitespace and expand ~ to $HOME
        local dir="$(echo "$raw_dir" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        dir="${dir/#\~/$HOME}"

        if [ -n "$dir" ]; then
            mkdir -p "$dir"
            local abs_host="$(cd "$dir" 2>/dev/null && pwd || echo "$dir")"
            local bname="$(basename "$abs_host")"
            local c_mount="/$bname"

            # Avoid container mount point collisions
            local idx=1
            while [[ " ${used_mounts[*]} " =~ " ${c_mount} " ]]; do
                c_mount="/${bname}-${idx}"
                idx=$((idx + 1))
            done

            used_mounts+=("$c_mount")
            PROJECT_MOUNTS+=("-v" "$abs_host:$c_mount")
            PROJECT_MAPPINGS+=("$abs_host|$c_mount")
        fi
    done
}

# Resolve target directory inside the container based on user input or $PWD
resolve_target_dir() {
    local input_path="$1"
    resolve_project_dirs

    local default_container_mount="/projects"
    if [ ${#PROJECT_MAPPINGS[@]} -gt 0 ]; then
        default_container_mount="${PROJECT_MAPPINGS[0]##*|}"
    fi

    # 1. If user provided a specific folder name or path
    if [ -n "$input_path" ]; then
        # Check if input_path is a path on the host system
        if [ -d "$input_path" ]; then
            local abs_input="$(cd "$input_path" 2>/dev/null && pwd)"
            for mapping in "${PROJECT_MAPPINGS[@]}"; do
                local h_dir="${mapping%%|*}"
                local c_dir="${mapping##*|}"
                if [[ "$abs_input" == "$h_dir"* ]]; then
                    local rel="${abs_input#$h_dir}"
                    echo "${c_dir}${rel}"
                    return 0
                fi
            done
        fi

        # Check if input_path is a subfolder inside any of the mapped host project directories
        for mapping in "${PROJECT_MAPPINGS[@]}"; do
            local h_dir="${mapping%%|*}"
            local c_dir="${mapping##*|}"
            if [ -d "$h_dir/$input_path" ]; then
                echo "$c_dir/$input_path"
                return 0
            fi
        done

        # Fallback to default mount point + subpath
        echo "$default_container_mount/$input_path"
        return 0
    fi

    # 2. If no argument provided, check if current working directory ($PWD) is inside a mapped directory
    for mapping in "${PROJECT_MAPPINGS[@]}"; do
        local h_dir="${mapping%%|*}"
        local c_dir="${mapping##*|}"
        if [[ "$PWD" == "$h_dir"* ]]; then
            local rel="${PWD#$h_dir}"
            echo "${c_dir}${rel}"
            return 0
        fi
    done

    # 3. Fallback to the first project mount
    echo "$default_container_mount"
}

# Build docker image
build-claude-env() {
    docker build -t claude-env "$SCRIPT_DIR"
}

# Start workspace container
start-claude-env() {
    resolve_project_dirs

    # Check if container is already running
    if docker ps --format '{{.Names}}' | grep -q "^claude-workspace$"; then
        return 0
    fi

    echo "Starting claude-workspace container with mapped project directories:"
    for mapping in "${PROJECT_MAPPINGS[@]}"; do
        echo "  - Host: ${mapping%%|*} -> Container: ${mapping##*|}"
    done

    docker run -d --rm \
        --name claude-workspace \
        --memory="8g" \
        --cpus="4" \
        --cap-add=NET_ADMIN \
        --add-host=host.docker.internal:host-gateway \
        -e DB_HOST=host.docker.internal \
        -e DB_PORT=5432 \
        -e GITLAB_TOKEN="$GITLAB_TOKEN" \
        -e GITLAB_USER="$GITLAB_USER" \
        -e ALLOW_LOCAL_DB_ACCESS="${ALLOW_LOCAL_DB_ACCESS:-true}" \
        -p 3000:3000 \
        -p 5173:5173 \
        -p 8000:8000 \
        -p 8080:8080 \
        -p 8025:8025 \
        -p 1025:1025 \
        "${PROJECT_MOUNTS[@]}" \
        -v ~/.claude-cache/.claude-docker-state:/home/devuser/.claude \
        -v ~/.claude-cache/.npm-docker-cache:/home/devuser/.npm \
        -v ~/.claude-cache/.gopath-docker-cache:/home/devuser/go \
        -v ~/.claude-cache/.composer-docker-cache:/home/devuser/.cache/composer \
        -v ~/.claude-cache/.playwright-docker-cache:/home/devuser/.cache/ms-playwright \
        claude-env tail -f /dev/null
}

# Stop workspace container
stop-claude-env() {
    echo "Stopping claude-workspace container..."
    docker stop claude-workspace 2>/dev/null || true
}

# Open bash shell inside container in target project directory
cclaude-shell() {
    local target_dir
    target_dir="$(resolve_target_dir "$1")"
    start-claude-env
    echo "Opening bash shell in: $target_dir"
    docker exec -it -w "$target_dir" claude-workspace /bin/bash
}

# Launch Claude Code inside container with full autonomy in target directory
cclaude() {
    local target_input=""
    local claude_args=()

    # If first argument is not a flag, treat it as project name/subpath
    if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
        target_input="$1"
        shift
    fi

    claude_args=("$@")

    local target_dir
    target_dir="$(resolve_target_dir "$target_input")"

    start-claude-env
    echo "Launching Claude Code in: $target_dir"
    docker exec -it -w "$target_dir" claude-workspace claude --dangerously-skip-permissions "${claude_args[@]}"
}

# If script is executed directly (not sourced), execute start-claude-env by default
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        build)
            build-claude-env
            ;;
        stop)
            stop-claude-env
            ;;
        shell)
            shift
            cclaude-shell "$@"
            ;;
        claude)
            shift
            cclaude "$@"
            ;;
        *)
            start-claude-env
            ;;
    esac
fi
