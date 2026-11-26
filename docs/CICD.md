# CI/CD: build, test and publish images (ticket E1-13)

Implements the PRD requirement **IR-8** and acceptance criterion **AC-13** of Epic 1: the
container images the appliance builds (`mta`, `imap`) are built and published **automatically by
GitHub's CI/CD on every push to `main`**, only when the checks pass, and each image is traceable
to its commit.

Design details live in `technical.md` section 12 (Build and publish / CI/CD).

## What triggers a build, and what does not

The workflow file is `.github/workflows/images.yml`, named **Images**, with these triggers:

| Trigger | Behaviour |
|---|---|
| push to `main` | Build, test and **publish** |
| pull request | Build and test only; **never publish** |
| manual run (`workflow_dispatch`) | Behaves like a push to `main` (build, test, publish) |

Concurrency: one group per ref (`images-<ref>`); in-progress runs for a pull request are
cancelled when a newer run starts; runs on `main` are never cancelled mid-publish.

## Pipeline stages

1. **Build** (`build-mta`, `build-imap`): checkout, Docker Buildx, login to GitHub Container
   Registry (`ghcr.io`), build from the component Dockerfile, push under temporary tag
   `e1-13-tmp-<full-commit-hash>`. Image labels are set: source repository, commit hash, build
   time.
2. **Test** (`needs: build`): pull both temporary-tagged images, start the Compose stack from
   them (`CONTINGENCY_TAG=e1-13-tmp-<sha> docker compose -f compose.release.yaml up -d --wait`),
   then run the checks:
   - `postfix check` inside `mta`;
   - Dovecot configuration check inside `imap`;
   - both containers reach the healthy state (within timeout);
   - scenario suite `prototype/tests/run-all.sh` (ticket E1-11).
   
   On failure: collect container logs and upload as workflow artifact
   (`e1-13-failure-artifacts`).
3. **Publish** (`needs: [build, test]`): runs only for `push` to `main` or `workflow_dispatch`; only
   if build and test passed. Retags the temporary-tagged images to the **full commit hash** and to
   `latest`, and pushes both to GitHub Container Registry.

The same image flows from build to test to publish; it is never rebuilt between testing and
publishing (temporary tag → retag).

## Images: names, tags and labels

- Registry: GitHub Container Registry (`ghcr.io`).
- Image names: one per component, named after the repository, e.g.
  `ghcr.io/<owner>/<repo>/mta` and `ghcr.io/<owner>/<repo>/imap`.
- Published tags (every publish): the **full commit hash** (immutable; what installs should pin)
  and `latest` (moving; convenience only, not for installs).
- Image labels (every build): source repository, commit hash, build time — so a running container
  can be traced to its commit.

Currently built and published: `mta` (Debian + Postfix) and `imap` (Debian + Dovecot). The
`webmail` image is the upstream Roundcube image and is not built by this pipeline; it is pinned in
the Compose files instead (placeholder until Epic 3).

## How to find which commit a running container was built from

```sh
docker inspect --format '{{ json .Config.Labels }}' <image>:<tag> | jq .
# or, for a running container:
docker inspect --format '{{ json .Config.Labels }}' <container>
# expected labels: org.opencontainers.image.source, org.opencontainers.image.revision, org.opencontainers.image.created
```

The release install pins by tag; use the full commit hash.

## How to pin an install to a commit hash

```sh
CONTINGENCY_TAG=<full-commit-hash> docker compose -f compose.release.yaml up -d
```

## How to re-run a failed build

Re-run the workflow run from the GitHub Actions UI (or `gh run rerun <run-id>`).

## How to add a new image to the pipeline

Add one line to the `build` job matrix in `.github/workflows/images.yml`:

```yaml
        include:
          - image: mta
            dockerfile: mta/Dockerfile
          - image: imap
            dockerfile: imap/Dockerfile
          - image: dkim
            dockerfile: dkim/Dockerfile   # future epic
```

Then add the pull + test + publish steps for the new image (or extend the matrix-driven steps).

## Security of the pipeline

- Workflow permissions: read access to the repository by default; write access to packages only
  where needed (build temporary tags, publish).
- No secrets are baked into images; configuration reaches containers only via volumes/environment
  at run time.
- Third-party actions are pinned to a specific commit (with human-readable version comment):
  `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683` (v4.2.2),
  `docker/setup-buildx-action@18ce135bb5112fa8ce4ed6c17ab05699d7f3a5e0` (v3.11.0),
  `docker/login-action@74a5d142397b4f367a81961eba4e8cd7edddf772` (v3.4.0),
  `docker/build-push-action@4f58ea79222b3b9dc2c8bbdd6debcef730109a75` (v6.9.0),
  `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` (v4.6.2).
- Images contain no build tools, source code, or Docker socket.

## Notes and pitfalls

- The first publish creates the package in the registry with default settings that may not match
  what you want; check the package visibility and repository link after the first run, and adjust
  package settings.
- Pull requests from forks do not get write access by design; the pipeline only publishes from
  `main`.
- The test gate runs the full scenario suite on the runner; the suite already waits on conditions
  with timeouts (E1-11). No fixed sleeps are added to work around flakiness.
- Timing issues are the most common cause of flaky CI; keep the gate as designed.
