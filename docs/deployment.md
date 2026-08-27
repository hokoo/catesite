# Production Deployment

Production deployment is handled by GitHub Actions.

## Workflows

- `Production Deploy` runs automatically on every push to `master`.
- `Production Rollback` runs manually from GitHub Actions.

The deploy workflow runs the existing Playwright e2e tests before publishing a release. If tests fail, deployment does not start.

## Required Secrets

The workflows SSH to `kate-tron.com` as `kate_deploy` and use this GitHub Actions secret:

- `SSH_KEY`: private SSH key for the deploy user.

The server host key is pinned in the workflow with this expected ECDSA fingerprint:

```text
SHA256:UZLkwkrHKjpLXEmCXjCy9/yDHsqH4+US5Y4TvOqb/nw
```

The workflow still runs `ssh-keyscan`, but it fails unless the scanned fingerprint matches this pinned value. Do not replace this with `StrictHostKeyChecking no`.

## Server Layout

The first deploy converts the current live root into a release-based layout:

```text
/srv/web/kate-tron.com -> /srv/web/kate-tron/current
/srv/web/kate-tron/current -> /srv/web/kate-tron/releases/<github-run-id>
/srv/web/kate-tron/releases/<github-run-id>
/srv/web/kate-tron/shared
/srv/web/kate-tron/backups
```

Runtime files are copied from the current live root into shared storage during the first deploy:

- `/srv/web/kate-tron/shared/wp-config.php`
- `/srv/web/kate-tron/shared/.env`, when present
- `/srv/web/kate-tron/shared/wp-content/uploads`

Each release receives its own copy of `wp-config.php` so that the existing `CS_ROOT` and `ABSPATH` definitions resolve to the active release directory. Uploads stay shared through a symlink.

## Release Id

The release id is the GitHub Actions `run_id`. The deploy summary prints it after each successful deployment.

The same id is used by rollback when a specific release should be activated.

## Rollback

Open `Production Rollback` in GitHub Actions.

Inputs:

- `run_id`: optional. Leave empty to roll back one release behind the current release.
- `restore_db`: optional, default `false`. Set to `true` only when the rollback also needs the database snapshot for the target release.

Repeated rollback without `run_id` moves one numeric release id backward each time:

```text
105 -> 104 -> 103
```

Rollback always creates a database snapshot before switching releases. Database restore is explicit because it can remove production content created after the target release.

If a normal deployment fails after switching the active release, the deploy script switches code back automatically and restores the pre-deploy database backup. If manual rollback fails after switching, it switches code back to the release that was active before rollback and restores the pre-rollback database snapshot.

## Deployment Safety

Deploy does not write directly into the live root. It uploads files into a release directory, then switches the active symlink after preflight checks.

The deploy excludes mutable/runtime paths:

- `.env`
- `wp-config.php`
- `wp-content/uploads`
- `node_modules`
- `var`
- tests and Playwright output
- Docker-only runtime files
- database dumps

After switching, deployment runs:

```bash
wp core update-db
wp rewrite flush
wp cache flush
```

Health checks hit the origin directly with `curl --resolve kate-tron.com:443:127.0.0.1` to avoid accepting a cached CDN response as proof that production is healthy.

At least five release directories and five before/after database backup pairs are retained by default.
