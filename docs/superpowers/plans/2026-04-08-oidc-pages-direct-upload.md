# OIDC Pages Direct Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the OIDC companion site from Cloudflare Git-integrated Pages deployment to GitHub Actions driven direct upload so issuer discovery URLs stay deployable without Cloudflare Git account linkage.

**Architecture:** Keep the companion repo and discovery document generation workflow, but make the workflow publish a staged static site directly to the existing Pages project with Wrangler. Update bootstrap to provision the companion repo with the Cloudflare deploy config and update readiness checks so they require a real Pages deployment rather than only project existence. Also ensure Pages serves extensionless `openid-configuration` as JSON, because AWS API Gateway rejects the issuer if Cloudflare serves that endpoint as `application/octet-stream`.

**Tech Stack:** GitHub Actions, Cloudflare Pages, Wrangler, bash shell tests, curl JSON API checks

---

## File Map

- Modify: `ltbase-oidc-discovery-template/.github/workflows/publish-discovery.yml`
  - Add direct-upload deployment using Cloudflare credentials after document generation.
  - Stage only generated stack content and publish a `_headers` file for JSON content types.
- Modify: `ltbase-private-deployment/scripts/bootstrap-oidc-discovery-companion.sh`
  - Provision companion repo secrets/variables for direct upload and fail on Cloudflare API JSON errors.
- Modify: `ltbase-private-deployment/test/bootstrap-oidc-discovery-companion-test.sh`
  - Cover the new companion repo config and Cloudflare API failure behavior.
- Modify: `ltbase-private-deployment-demo01/scripts/bootstrap-oidc-discovery-companion.sh`
  - Same bootstrap change for immediate customer unblock.
- Modify: `ltbase-private-deployment-demo01/test/bootstrap-oidc-discovery-companion-test.sh`
  - Same test coverage in the demo repo.
- Modify: `ltbase-private-deployment-demo01/scripts/evaluate-and-continue.sh`
  - Require a real Pages deployment signal, not just project/domain existence.
- Modify: `ltbase-private-deployment-demo01/test/evaluate-and-continue-test.sh`
  - Cover disconnected Pages projects and direct-upload config expectations.

### Task 1: Add Direct Upload Deployment To The Template Workflow

**Files:**
- Modify: `ltbase-oidc-discovery-template/.github/workflows/publish-discovery.yml`

- [ ] **Step 1: Write the failing workflow assertions by reading the workflow and identifying missing deploy inputs**

Use this checklist as the failing expectation:

```text
Expected workflow requirements after this task:
- reads CLOUDFLARE_ACCOUNT_ID from repo config
- reads OIDC_DISCOVERY_PAGES_PROJECT from repo config
- reads CLOUDFLARE_API_TOKEN from repo secrets
- installs wrangler or uses wrangler action
- deploys repository root to Cloudflare Pages after commit step
```

- [ ] **Step 2: Verify the current workflow is missing direct upload deployment**

Run: `grep -n "wrangler\|pages deploy\|CLOUDFLARE_ACCOUNT_ID\|OIDC_DISCOVERY_PAGES_PROJECT\|CLOUDFLARE_API_TOKEN" .github/workflows/publish-discovery.yml`

Expected: no deploy step present, proving the workflow still depends on Cloudflare Git integration.

- [x] **Step 3: Write the minimal workflow change**

Update the workflow to include the extra variables and a deploy step after `Commit and push`.

Use this shape in `ltbase-oidc-discovery-template/.github/workflows/publish-discovery.yml`:

```yaml
      - name: Deploy to Cloudflare Pages
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ vars.CLOUDFLARE_ACCOUNT_ID }}
          OIDC_DISCOVERY_PAGES_PROJECT: ${{ vars.OIDC_DISCOVERY_PAGES_PROJECT }}
        run: |
          set -euo pipefail

          if [[ -z "${CLOUDFLARE_API_TOKEN}" ]]; then
            echo "::error::CLOUDFLARE_API_TOKEN repo secret is not set"
            exit 1
          fi
          if [[ -z "${CLOUDFLARE_ACCOUNT_ID}" ]]; then
            echo "::error::CLOUDFLARE_ACCOUNT_ID repo variable is not set"
            exit 1
          fi
          if [[ -z "${OIDC_DISCOVERY_PAGES_PROJECT}" ]]; then
            echo "::error::OIDC_DISCOVERY_PAGES_PROJECT repo variable is not set"
            exit 1
          fi

          npm install --global wrangler
          wrangler pages deploy <staged-site-dir> --project-name "${OIDC_DISCOVERY_PAGES_PROJECT}"
```

Keep the rest of the generation flow intact. During live validation this task also required publishing a `_headers` file so `/.well-known/openid-configuration` is served as `application/json; charset=utf-8`.

- [ ] **Step 4: Verify the workflow now contains the direct upload path**

Run: `grep -n "wrangler\|pages deploy\|CLOUDFLARE_ACCOUNT_ID\|OIDC_DISCOVERY_PAGES_PROJECT\|CLOUDFLARE_API_TOKEN" .github/workflows/publish-discovery.yml`

Expected: output includes all new deployment inputs and the `wrangler pages deploy .` command.

- [x] **Step 5: Commit the template workflow change**

```bash
git add .github/workflows/publish-discovery.yml
git commit -m "fix: deploy OIDC discovery site via Pages direct upload"
```

### Task 2: Teach Bootstrap To Provision Direct-Upload Companion Config

**Files:**
- Modify: `ltbase-private-deployment/test/bootstrap-oidc-discovery-companion-test.sh`
- Modify: `ltbase-private-deployment/scripts/bootstrap-oidc-discovery-companion.sh`
- Modify: `ltbase-private-deployment-demo01/test/bootstrap-oidc-discovery-companion-test.sh`
- Modify: `ltbase-private-deployment-demo01/scripts/bootstrap-oidc-discovery-companion.sh`

- [ ] **Step 1: Write the failing bootstrap test in the template repo**

Add these assertions to `ltbase-private-deployment/test/bootstrap-oidc-discovery-companion-test.sh` before changing the script:

```bash
assert_log_contains "${log_file}" "gh secret set CLOUDFLARE_API_TOKEN --repo customer-org/customer-ltbase-oidc-discovery --body test-cloudflare-token"
assert_log_contains "${log_file}" "gh variable set CLOUDFLARE_ACCOUNT_ID --repo customer-org/customer-ltbase-oidc-discovery --body cf-account-123"
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_PAGES_PROJECT --repo customer-org/customer-ltbase-oidc-discovery --body customer-ltbase-oidc-discovery"
```

- [ ] **Step 2: Run the template bootstrap test to verify it fails**

Run: `bash test/bootstrap-oidc-discovery-companion-test.sh`

Expected: FAIL because those companion repo secret/variable writes do not exist yet.

- [ ] **Step 3: Implement the minimal bootstrap changes in the template repo**

Add the companion repo config writes immediately after the existing `gh variable set OIDC_DISCOVERY_DOMAIN` and `gh variable set OIDC_DISCOVERY_STACK_CONFIG` calls.

Use this code:

```bash
gh variable set CLOUDFLARE_ACCOUNT_ID --repo "${OIDC_DISCOVERY_REPO}" --body "${CLOUDFLARE_ACCOUNT_ID}"
gh variable set OIDC_DISCOVERY_PAGES_PROJECT --repo "${OIDC_DISCOVERY_REPO}" --body "${OIDC_DISCOVERY_PAGES_PROJECT}"
gh secret set CLOUDFLARE_API_TOKEN --repo "${OIDC_DISCOVERY_REPO}" --body "${CLOUDFLARE_API_TOKEN}"
```

Also add a helper to fail on Cloudflare JSON errors. Replace raw `curl ... >/dev/null` POSTs with a helper like:

```bash
cloudflare_api_post() {
  local url="$1"
  local payload="$2"
  local response
  response="$(curl -fsS -X POST "${cloudflare_headers[@]}" "${url}" --data "${payload}")"
  python3 -c 'import json, sys; data = json.load(sys.stdin); success = data.get("success");
if success is not True:
    errors = data.get("errors") or []
    raise SystemExit("Cloudflare API request failed: " + json.dumps(errors))' <<<"${response}"
}
```

Use the same pattern for any future Cloudflare create call in this script.

- [ ] **Step 4: Run the template bootstrap test to verify it passes**

Run: `bash test/bootstrap-oidc-discovery-companion-test.sh`

Expected: PASS.

- [ ] **Step 5: Mirror the same test-first change in the demo repo**

Add the same three assertions to `ltbase-private-deployment-demo01/test/bootstrap-oidc-discovery-companion-test.sh`, then run:

Run: `bash test/bootstrap-oidc-discovery-companion-test.sh`

Expected: FAIL for the same missing companion repo config.

- [ ] **Step 6: Apply the same bootstrap implementation in the demo repo**

Make the same script changes in `ltbase-private-deployment-demo01/scripts/bootstrap-oidc-discovery-companion.sh`.

- [ ] **Step 7: Run the demo bootstrap test to verify it passes**

Run: `bash test/bootstrap-oidc-discovery-companion-test.sh`

Expected: PASS.

- [ ] **Step 8: Commit the bootstrap changes in both repos**

Template repo:

```bash
git add scripts/bootstrap-oidc-discovery-companion.sh test/bootstrap-oidc-discovery-companion-test.sh
git commit -m "fix: provision companion repo Pages deploy config"
```

Demo repo:

```bash
git add scripts/bootstrap-oidc-discovery-companion.sh test/bootstrap-oidc-discovery-companion-test.sh
git commit -m "fix: provision companion repo Pages deploy config"
```

### Task 3: Strengthen Readiness To Require A Real Pages Deployment

**Files:**
- Modify: `ltbase-private-deployment-demo01/test/evaluate-and-continue-test.sh`
- Modify: `ltbase-private-deployment-demo01/scripts/evaluate-and-continue.sh`

- [ ] **Step 1: Write the failing readiness test**

In `ltbase-private-deployment-demo01/test/evaluate-and-continue-test.sh`, update the fake `gh variable list` / `gh secret list` outputs for the companion repo so they include:

```json
[{"name":"OIDC_DISCOVERY_DOMAIN"},{"name":"OIDC_DISCOVERY_STACK_CONFIG"},{"name":"CLOUDFLARE_ACCOUNT_ID"},{"name":"OIDC_DISCOVERY_PAGES_PROJECT"}]
```

and model companion secrets as:

```json
[{"name":"CLOUDFLARE_API_TOKEN"}]
```

Then add a curl scenario for `oidc_companion_missing` where the Pages project GET returns JSON with `"latest_deployment": null`.

Add this assertion after the `report-oidc` run:

```bash
assert_file_contains "${temp_dir}/report-oidc/report.json" '"pagesDeploymentPresent": false'
```

- [ ] **Step 2: Run the readiness test to verify it fails**

Run: `bash test/evaluate-and-continue-test.sh`

Expected: FAIL because readiness does not yet track a Pages deployment signal.

- [ ] **Step 3: Implement the minimal readiness change**

In `ltbase-private-deployment-demo01/scripts/evaluate-and-continue.sh`:

1. Extend `oidc_companion_repo_config_present()` so it also requires:

```bash
if ! json_name_list_contains "${variable_json}" "CLOUDFLARE_ACCOUNT_ID"; then
  return 1
fi
if ! json_name_list_contains "${variable_json}" "OIDC_DISCOVERY_PAGES_PROJECT"; then
  return 1
fi
```

2. Add a helper that fetches the Pages project JSON and requires non-null `latest_deployment`:

```bash
cloudflare_pages_deployment_present() {
  local response
  response="$(curl -fsS \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${OIDC_DISCOVERY_PAGES_PROJECT}")" || return 1

  python3 -c 'import json, sys; data = json.load(sys.stdin); result = data.get("result") or {}; sys.exit(0 if result.get("latest_deployment") else 1)' <<<"${response}"
}
```

3. Track a new flag in `scan_oidc_discovery_state()`:

```bash
local pages_deployment_present="false"
...
if cloudflare_pages_deployment_present; then
  pages_deployment_present="true"
fi
...
if [[ "${repo_present}" == "true" && "${repo_config_present}" == "true" && "${pages_project_present}" == "true" && "${pages_domain_present}" == "true" && "${pages_deployment_present}" == "true" && "${roles_present}" == "true" ]]; then
  status="complete"
fi
```

4. Emit it into the status file:

```bash
OIDC_DISCOVERY_PAGES_DEPLOYMENT_PRESENT=${pages_deployment_present}
```

- [ ] **Step 4: Run the readiness test to verify it passes**

Run: `bash test/evaluate-and-continue-test.sh`

Expected: PASS.

- [ ] **Step 5: Commit the readiness change**

```bash
git add scripts/evaluate-and-continue.sh test/evaluate-and-continue-test.sh
git commit -m "fix: require OIDC Pages deployment readiness"
```

### Task 4: End-To-End Validation In The Live Demo Repo

**Files:**
- Modify if needed from earlier tasks: `ltbase-private-deployment-demo01/scripts/bootstrap-oidc-discovery-companion.sh`
- Verify live workflow behavior in: `iceboundrock/ltbase-private-deployment-demo01-oidc-discovery`

- [ ] **Step 1: Re-run the companion bootstrap with the updated script**

Run: `./scripts/bootstrap-oidc-discovery-companion.sh --env-file .env`

Expected: companion repo receives Pages direct-upload config plus Cloudflare DNS/project setup.

- [ ] **Step 2: Verify the companion repo now has the required secrets and variables**

Run:

```bash
gh variable list --repo iceboundrock/ltbase-private-deployment-demo01-oidc-discovery
gh secret list --repo iceboundrock/ltbase-private-deployment-demo01-oidc-discovery
```

Expected: variables include `OIDC_DISCOVERY_DOMAIN`, `OIDC_DISCOVERY_STACK_CONFIG`, `CLOUDFLARE_ACCOUNT_ID`, `OIDC_DISCOVERY_PAGES_PROJECT`; secrets include `CLOUDFLARE_API_TOKEN`.

- [ ] **Step 3: Trigger the companion publish workflow**

Run: `gh workflow run publish-discovery.yml --repo iceboundrock/ltbase-private-deployment-demo01-oidc-discovery`

Expected: workflow starts successfully.

- [x] **Step 4: Verify the companion workflow succeeds and Pages shows a deployment**

Run:

```bash
gh run list --repo iceboundrock/ltbase-private-deployment-demo01-oidc-discovery --workflow publish-discovery.yml --limit 1
```

Then query Cloudflare:

```bash
set -a && source .env && set +a && curl -fsS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${DEPLOYMENT_REPO_NAME}-oidc-discovery"
```

Expected: non-null `latest_deployment`.

Observed result: achieved after the companion repo was switched to Pages direct upload.

- [x] **Step 5: Verify the public discovery URL resolves**

Run: `curl -I https://ltbase-demo01-oidc.ltbase.dev/devo/.well-known/openid-configuration`

Expected: HTTP 200 after DNS and Pages propagation.

Observed result: HTTP 200 was not sufficient by itself. Live validation found that `openid-configuration` initially returned `content-type: application/octet-stream`, which still caused AWS issuer validation to fail. The workflow was then patched to deploy a Pages `_headers` file and the endpoint switched to `application/json; charset=utf-8`.

- [ ] **Step 6: Trigger a fresh rollout**

Run: `gh workflow run rollout.yml --repo iceboundrock/ltbase-private-deployment-demo01 -f release_id=v1.0.0`

Expected: rollout starts on the latest main commit.

- [x] **Step 7: Verify issuer validation is past the previous blocker**

Run:

```bash
gh run list --repo iceboundrock/ltbase-private-deployment-demo01 --workflow rollout.yml --limit 1
gh run view <new-run-id> --repo iceboundrock/ltbase-private-deployment-demo01 --json status,conclusion,jobs,url
```

Expected: the `Deploy stack` step no longer fails on `Invalid issuer` for `https://ltbase-demo01-oidc.ltbase.dev/devo`.

Observed result: confirmed. Rollout `24148898998` got past JWT authorizer creation after the content-type fix.

### Task 5: Fix Follow-On Control API Route Migration Bug

**Files:**
- Modify: `ltbase-private-deployment-demo01/infra/internal/services/apigateway.go`
- Modify: `ltbase-private-deployment-demo01/infra/internal/services/apigateway_test.go`
- Backport: `ltbase-private-deployment/infra/internal/services/apigateway.go`
- Backport: `ltbase-private-deployment/infra/internal/services/apigateway_test.go`

- [x] **Step 1: Confirm the new failure is not another OIDC issue**

Observed in rollout `24148518579`:

```text
ConflictException: Route with key ANY /{proxy+} already exists for this API
ConflictException: Route with key ANY / already exists for this API
```

At the same time, the three JWT authorizers were created successfully. That proved the issuer problem was solved and exposed a second bug.

- [x] **Step 2: Identify the Pulumi migration root cause**

The control-plane routes had legacy Pulumi logical names:

- `control-root`
- `control-route`

Current code uses route-key-derived names:

- `control-route-any`
- `control-route-any-proxy`

That made Pulumi try create-before-delete against API Gateway route keys that must be unique.

- [x] **Step 3: Add aliases for legacy control route identities**

Implemented a minimal migration in `infra/internal/services/apigateway.go` so control routes keep their new logical names but alias the legacy resources during adoption.

- [x] **Step 4: Add regression coverage**

Added targeted test coverage in `infra/internal/services/apigateway_test.go` for the legacy control route alias mapping.

- [x] **Step 5: Verify the fix locally and live**

Commands run:

```bash
go test ./internal/services -run 'Test(BuildControlPlaneRouteSpecs|RouteResourceNameIsStableFromRouteKey|ControlRouteAliases)'
```

Observed live result:

- demo repo fix pushed as `d8c6d79`
- template repo backport pushed as `e3e7afd`
- rollout `24148898998` succeeded

- [ ] **Step 8: Commit any remaining demo repo changes**

```bash
git add scripts/bootstrap-oidc-discovery-companion.sh test/bootstrap-oidc-discovery-companion-test.sh scripts/evaluate-and-continue.sh test/evaluate-and-continue-test.sh
git commit -m "fix: deploy OIDC discovery via Pages direct upload"
```

## Self-Review

- Spec coverage: workflow deployment, bootstrap config, Cloudflare API error handling, readiness checks, and live validation are all mapped to tasks.
- Placeholder scan: no `TODO`, `TBD`, or vague “add tests” steps remain.
- Type consistency: the new config names are consistent across workflow, bootstrap, and readiness tasks: `CLOUDFLARE_ACCOUNT_ID`, `OIDC_DISCOVERY_PAGES_PROJECT`, `CLOUDFLARE_API_TOKEN`.
