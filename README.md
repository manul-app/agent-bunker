# Environment isolation for Claude CLI

## What to setup

### Gitlab

Create Personal access token with read access for project group.

### Host machine

Edit `.env`:
- Set `GITLAB_TOKEN`.

Edit `postgresql.conf`:
- Set `listen_addresses = '*'`

Edit `pg_hba.conf`, add the following line to let decker containers to work with local DB:

```
host    all             all             172.17.0.0/16           trust
```

Restart Postgres.
