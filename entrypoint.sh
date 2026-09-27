#!/bin/bash
set -e

# Apply firewall rules if script exists (requires --cap-add=NET_ADMIN)
if [ -x /usr/local/bin/setup-firewall.sh ]; then
    ALLOW_LOCAL_DB_ACCESS="${ALLOW_LOCAL_DB_ACCESS:-true}"
    sudo /usr/local/bin/setup-firewall.sh "$ALLOW_LOCAL_DB_ACCESS" || echo "Warning: Firewall setup skipped (container requires --cap-add=NET_ADMIN)"
fi

# Git identity for agent commits. Defaults match the ones baked into the image,
# so an empty GIT_USER_NAME / GIT_USER_EMAIL in .env keeps "Agent Bunker".
git config --global user.name "${GIT_USER_NAME:-Agent Bunker}"
git config --global user.email "${GIT_USER_EMAIL:-agent-bunker@local.sandbox}"

# Dynamically configure GitLab token rewrite if provided via environment variable
if [ -n "$GITLAB_TOKEN" ] && [ -n "$GITLAB_URL" ]; then
    git config --global url."https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/".insteadOf "https://${GITLAB_HOST}/"
    git config --global url."https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/".insteadOf "git@${GITLAB_HOST}:"
fi

# Execute CMD passed to container
exec "$@"
