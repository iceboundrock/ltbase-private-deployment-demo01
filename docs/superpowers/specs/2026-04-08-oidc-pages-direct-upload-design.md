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

Observed follow-up failure mode during live validation:

- the companion publish workflow can succeed
- the discovery URL can return HTTP 200
- but Cloudflare Pages can still serve `/.well-known/openid-configuration` as `application/octet-stream`
- AWS API Gateway JWT authorizer validation rejects that issuer as if discovery were invalid

So deployability is not enough. The served discovery endpoint must also have the expected JSON content type.

## Goals

- Make GitHub Actions the source of truth for OIDC companion site deployment.
- Keep the existing companion repo model and custom domain model.
- Remove operational dependence on Cloudflare's GitHub app connection.
- Preserve the existing discovery document generation logic.
- Ensure the served discovery endpoint is materially acceptable to AWS API Gateway JWT issuer validation.
- Keep the bootstrap flow idempotent.

## Non-Goals

- Do not redesign the OIDC discovery document format beyond what is needed to satisfy AWS validation of the served endpoint.
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
4. Deploy a staged static site directory to the Cloudflare Pages project using direct upload.
5. Publish a Pages `_headers` file so extensionless discovery documents are served with JSON content types.

Cloudflare Pages becomes a static hosting target only.

### Workflow Changes

File: `ltbase-oidc-discovery-template/.github/workflows/publish-discovery.yml`

Add a final deploy phase after the existing commit step:

- install Wrangler in the workflow runner
- authenticate using companion repo secrets
- stage only generated stack directories into a temporary site directory
- generate a `_headers` file for each stack so:
  - `/<stack>/.well-known/openid-configuration` is served as `application/json; charset=utf-8`
  - `/<stack>/.well-known/jwks.json` is served as `application/json; charset=utf-8`
- run Pages direct upload against the companion Pages project

Required companion repo secrets/variables:

- secret: `CLOUDFLARE_API_TOKEN`
- variable or secret: `CLOUDFLARE_ACCOUNT_ID`
- variable: `OIDC_DISCOVERY_PAGES_PROJECT`

The deploy command should target a staged site directory, not the repository root, so only generated stack folders and explicit Pages metadata are published.

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
6. if rollout gets past issuer validation but fails on API Gateway route conflicts, treat that as a separate migration bug, not an OIDC regression

## Migration Notes

- Existing companion repos can be migrated in place.
- The Pages project name and custom domain do not need to change.
- Disconnected Cloudflare Git integration can be ignored after direct upload is working.
- If a Git-integrated project later reconnects, Git integration should still not be the required production path.
- Existing deployment stacks may still hit unrelated Pulumi migration issues after the issuer problem is fixed. In live validation, the next blocker was a control-plane API Gateway route rename that needed resource aliases to preserve route identity during update.

## Tradeoffs

### Pros

- removes hidden dependency on Cloudflare account Git installation state
- deployment happens in the same workflow that generated the documents
- easier to debug because generation and publish are one pipeline
- works for private repos without extra Cloudflare UI work
- lets the workflow control exact serving metadata for extensionless discovery files

### Cons

- bootstrap must now provision Cloudflare deployment credentials into the companion repo
- workflow becomes slightly longer
- readiness checks need one more layer of verification

## Recommendation

Implement direct upload in the OIDC companion workflow and update bootstrap plus readiness checks to match that model.

Live validation confirmed this architecture works, but only after explicitly forcing JSON content types for `openid-configuration`. Once that was fixed, AWS API Gateway accepted the issuer and the remaining rollout blocker was a separate Pulumi route-identity migration issue.
