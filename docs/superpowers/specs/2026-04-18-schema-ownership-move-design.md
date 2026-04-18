# Schema Ownership Move Design

**Date:** 2026-04-18
**Status:** Approved in conversation
**Repos:** `ltbase-private-deployment-demo01`, `ltbase.api`

## Goal

Make `ltbase-private-deployment-demo01` the deployment-owned source for Forma schemas so the existing preview and rollout GitHub Actions can validate and upload schemas to S3.

## Decision

- `ltbase-private-deployment-demo01/customer-owned/schemas/` becomes the canonical deployment-owned schema directory.
- The existing `scripts/publish-schemas.sh` default path remains the upload source for preview and rollout workflows.
- `ltbase.api` is not changed in this slice because it still packages local schema files for SAM, release artifacts, and the `forma-cdc` Lambda.

## Scope

Included:

- create the documented `customer-owned/schemas/` directory in `ltbase-private-deployment-demo01`
- copy the current schema bundle from `ltbase.api/cmd/api/schemas/` into that directory
- add regression coverage proving `publish-schemas.sh` works with the default repo-owned schema path

Not included:

- deleting `ltbase.api/cmd/api/schemas/`
- changing `forma-cdc` to read schemas from S3
- changing release artifact packaging in `ltbase.api`

## Why This Slice

The deployment repository already owns the upload workflow contract:

- preview validates schemas with `./scripts/publish-schemas.sh --dry-run`
- rollout publishes schemas to `schemas/releases/<version>/...` and updates `schemas/published/manifest.json`

The missing piece is the schema bundle itself. Creating `customer-owned/schemas/` in the deployment repo unblocks the workflow without breaking current local or release behavior in `ltbase.api`.

## Follow-Up

A later cleanup can remove the product-repo schema copies after `ltbase.api` no longer depends on bundled local schemas for release packaging and `forma-cdc` runtime initialization.
