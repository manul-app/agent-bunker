#!/bin/bash
set -e

# Apply firewall rules if script exists (requires --cap-add=NET_ADMIN)
if [ -x /usr/local/bin/setup-firewall.sh ]; then
    ALLOW_LOCAL_DB_ACCESS="${ALLOW_LOCAL_DB_ACCESS:-true}"
    sudo /usr/local/bin/setup-firewall.sh "$ALLOW_LOCAL_DB_ACCESS" || echo "Warning: Firewall setup skipped (container requires --cap-add=NET_ADMIN)"
fi

# Dynamically configure GitLab token rewrite if provided via environment variable
if [ -n "$GITLAB_TOKEN" ]; then
    GITLAB_USER="${GITLAB_USER:-oauth2}"
    git config --global url."https://${GITLAB_USER}:${GITLAB_TOKEN}@gitlab.com/".insteadOf "git@gitlab.com:"
fi

# Execute CMD passed to container
exec "$@"
