# OIDC Pages Direct Upload Design

## Purpose

Replace the OIDC companion repo's dependency on Cloudflare Pages Git integration with GitHub Actions driven direct upload deployment.

This makes the companion site deployable even when Cloudflare's GitHub connection is missing, stale, or disconnected.

## Problem

The current bootstrap flow creates a Cloudflare Pages project that points at the generated OIDC companion repository. That project can exist and have a custom domain, but still never serve content if Cloudflare cannot access the GitHub repo.

Observed failure mode in `iceboundrock/ltbase-private-deployment-demo01-oidc-discovery`:

- Cloudflare Pages project exists
- custom domain exists
- DNS CNAME can exist
- discovery files are committed in GitHub
- but `latest_deployment` and `canonical_deployment` are `null`
- Cloudflare UI warns: `This project is disconnected from your Git account. This may cause deployments to fail.`

That means the custom OIDC issuer URL can still fail AWS API Gateway validation because nothing is actually deployed at the Pages hostname.

## Goals

- Make GitHub Actions the source of truth for OIDC companion site deployment.
- Keep the existing companion repo model and custom domain model.
- Remove operational dependence on Cloudflare's GitHub app connection.
- Preserve the existing discovery document generation logic.
- Keep the bootstrap flow idempotent.

## Non-Goals

- Do not redesign the OIDC discovery document format.
- Do not replace Cloudflare Pages hosting.
- Do not add a separate deployment service.
- Do not require customers to manually reconnect GitHub in Cloudflare for normal operation.

## Repositories Affected

### `ltbase-oidc-discovery-template`

Owns the companion repo workflow. This repo will change so the publish workflow deploys static files to Cloudflare Pages directly.

### `ltbase-private-deployment`

Owns the reusable bootstrap flow. This repo will change so bootstrap provisions the companion repo with the Cloudflare credentials and readiness expectations needed for direct upload.

### `ltbase-private-deployment-demo01`

Customer deployment repo used to validate the change immediately. This repo will receive the same bootstrap and readiness updates so the current blocked rollout can be unblocked.

## Proposed Design

### Deployment Model

The OIDC companion repo keeps generating discovery documents in GitHub Actions, but it no longer relies on Cloudflare auto-deploying from the Git repository.

Instead, the workflow will:

1. Check out the repo.
2. Generate `openid-configuration` and `jwks.json` files for each stack.
3. Commit and push any generated file changes back to the companion repo.
4. Deploy the repository contents to the Cloudflare Pages project using direct upload.

Cloudflare Pages becomes a static hosting target only.

### Workflow Changes

File: `ltbase-oidc-discovery-template/.github/workflows/publish-discovery.yml`

Add a final deploy phase after the existing commit step:

- install Wrangler in the workflow runner
- authenticate using companion repo secrets
- run Pages direct upload against the companion Pages project

Required companion repo secrets/variables:

- secret: `CLOUDFLARE_API_TOKEN`
- variable or secret: `CLOUDFLARE_ACCOUNT_ID`
- variable: `OIDC_DISCOVERY_PAGES_PROJECT`

The deploy command should target the repository root so stack folders like `devo/.well-known/...` and `prod/.well-known/...` are published exactly as generated.

### Bootstrap Changes

File: `scripts/bootstrap-oidc-discovery-companion.sh`

Bootstrap continues to:

- create the companion repo if missing
- create the Pages project if missing
- attach the custom domain if missing
- create the DNS CNAME if missing
- configure AWS OIDC read roles for discovery publishing

Bootstrap will additionally configure the companion repo for direct upload deployment:

- `gh secret set CLOUDFLARE_API_TOKEN --repo <companion repo>`
- `gh variable set CLOUDFLARE_ACCOUNT_ID --repo <companion repo>`
- `gh variable set OIDC_DISCOVERY_PAGES_PROJECT --repo <companion repo>`

Bootstrap no longer needs to assume Cloudflare Git integration is healthy.

### Readiness Checks

File: `scripts/evaluate-and-continue.sh`

Current readiness is too weak because it treats these as sufficient:

- companion repo exists
- repo variables exist
- Pages project exists
- Pages domain exists
- IAM roles exist

That misses the real failure mode: no successful site deployment.

Readiness should be updated so OIDC companion is only `complete` when:

- companion repo exists
- repo config is present, including direct-upload deployment config
- Pages project exists
- Pages custom domain exists
- DNS record exists for the custom domain
- IAM roles exist
- at least one successful Pages deployment exists, or the companion publish workflow has successfully run after direct-upload secrets were configured

The exact implementation can choose one of two checks:

1. preferred: query Cloudflare Pages project and require non-null `latest_deployment`
2. fallback: inspect a successful companion workflow run after direct-upload configuration

Preferred is Cloudflare state because it checks the real serving layer.

### Error Handling

Cloudflare API responses must no longer be treated as successful only because HTTP returned 200.

Bootstrap should parse Cloudflare JSON responses and fail if `success` is not `true`.

This applies to:

- Pages project creation
- custom domain creation
- DNS record creation

This avoids silent partial bootstrap.

## Testing Strategy

### Template Repo

- extend workflow validation as needed for new deployment env vars/secrets expectations
- if there are workflow tests, add coverage for required Pages deploy config

### Private Deployment Repos

- extend `test/bootstrap-oidc-discovery-companion-test.sh`
  - assert Cloudflare deployment repo credentials are written to companion repo
  - assert Cloudflare API failures are surfaced
- extend `test/evaluate-and-continue-test.sh`
  - distinguish `Pages project exists` from `Pages deployment exists`
  - ensure disconnected Pages projects are reported as incomplete

### Live Validation

For `ltbase-private-deployment-demo01`:

1. rerun companion bootstrap
2. run companion publish workflow
3. verify Pages project shows a non-null deployment
4. verify `https://ltbase-demo01-oidc.ltbase.dev/devo/.well-known/openid-configuration` resolves publicly
5. rerun rollout and verify API Gateway issuer validation passes

## Migration Notes

- Existing companion repos can be migrated in place.
- The Pages project name and custom domain do not need to change.
- Disconnected Cloudflare Git integration can be ignored after direct upload is working.
- If a Git-integrated project later reconnects, Git integration should still not be the required production path.

## Tradeoffs

### Pros

- removes hidden dependency on Cloudflare account Git installation state
- deployment happens in the same workflow that generated the documents
- easier to debug because generation and publish are one pipeline
- works for private repos without extra Cloudflare UI work

### Cons

- bootstrap must now provision Cloudflare deployment credentials into the companion repo
- workflow becomes slightly longer
- readiness checks need one more layer of verification

## Recommendation

Implement direct upload in the OIDC companion workflow and update bootstrap plus readiness checks to match that model.

This is the smallest durable fix for the current blocker and the right steady-state architecture for customer companion repos.
