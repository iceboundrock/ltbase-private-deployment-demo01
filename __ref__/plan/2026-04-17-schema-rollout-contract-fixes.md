# Schema Rollout Contract Fixes

- Scope: fix rollout/apply contract bugs only.
- Repos: `ltbase-private-deployment-demo01`, `ltbase.api`.
- TDD order:
  1. Add failing workflow and script tests for published/applied prefixes and drift guardrails.
  2. Add failing infra tests for separate runtime/control-plane schema prefixes.
  3. Implement minimal publication and workflow changes.
  4. Run targeted shell and Go tests.

- Intended contract:
  - `scripts/publish-schemas.sh` publishes immutable releases and a published pointer only.
  - `ensure-project` is solely responsible for advancing the applied/runtime pointer.
  - Lambdas do not read `schemas/current` directly for runtime consumption.
  - Rollout validates that workflow publish bucket matches Pulumi-configured runtime schema bucket.
