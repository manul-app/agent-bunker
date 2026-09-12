mkdir -p ~/.claude-cache/.claude-docker-state
mkdir -p ~/.claude-cache/.npm-docker-cache
mkdir -p ~/.claude-cache/.gopath-docker-cache
mkdir -p ~/.claude-cache/.composer-docker-cache

alias start-claude-env='docker run -d --rm \
  --name claude-workspace \
  --memory="8g" \
  --cpus="4" \
  --add-host=host.docker.internal:host-gateway \
  -e DB_HOST=host.docker.internal \
  -e DB_PORT=5432 \
  -e GITLAB_TOKEN="$GITLAB_TOKEN" \
  -v ~/projects:/projects \
  -v ~/.claude-cache/.claude-docker-state:/home/devuser/.claude \
  -v ~/.claude-cache/.npm-docker-cache:/home/devuser/.npm \
  -v ~/.claude-cache/.gopath-docker-cache:/home/devuser/go \
  -v ~/.claude-cache/.composer-docker-cache:/home/devuser/.cache/composer \
  claude-env tail -f /dev/null'
