# WP Kate's Site

## Requirements
Linux (or WSL), Docker Compose, Make

## Notice
Call all scripts from root project directory.

## E2E tests
Install test dependencies:

```sh
npm ci
npm run test:e2e:install
```

Run against local Docker WordPress at `http://cate.loc/`:

```sh
npm run test:e2e:local
```

Run during deployment against a deployed URL:

```sh
E2E_BASE_URL=https://example.com/ npm run test:e2e:deploy
```

The GitHub Actions workflow `.github/workflows/e2e.yml` accepts a `base_url`
input through `workflow_dispatch` or `workflow_call`, so it can be run manually
or called after a deployment job.
