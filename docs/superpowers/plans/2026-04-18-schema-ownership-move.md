# Schema Ownership Move Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the deployment repository own the schema bundle used by preview and rollout publishing.

**Architecture:** Keep the existing deployment workflow and publish script unchanged, add the documented `customer-owned/schemas/` directory with the current schema files, and add a regression test that proves the script works from its default repo-owned schema path.

**Tech Stack:** Bash, JSON, GitHub Actions

---

### Task 1: Prove the default schema directory contract

**Files:**
- Modify: `test/publish-schemas-test.sh`

- [ ] Add coverage that runs `scripts/publish-schemas.sh` without `--schema-dir` and expects it to publish from `customer-owned/schemas/`.
- [ ] Run `bash ./test/publish-schemas-test.sh` and confirm it fails because the default schema directory does not yet exist.

### Task 2: Create the deployment-owned schema bundle

**Files:**
- Create: `customer-owned/schemas/lead.json`
- Create: `customer-owned/schemas/lead_attributes.json`
- Create: `customer-owned/schemas/lead_full.json`
- Create: `customer-owned/schemas/contact.json`
- Create: `customer-owned/schemas/contact_attributes.json`
- Create: `customer-owned/schemas/contact_full.json`
- Create: `customer-owned/schemas/communication.json`
- Create: `customer-owned/schemas/communication_attributes.json`
- Create: `customer-owned/schemas/communication_full.json`
- Create: `customer-owned/schemas/visit.json`
- Create: `customer-owned/schemas/visit_attributes.json`
- Create: `customer-owned/schemas/visit_full.json`
- Create: `customer-owned/schemas/log.json`
- Create: `customer-owned/schemas/log_attributes.json`
- Create: `customer-owned/schemas/log_full.json`

- [ ] Copy the current schema bundle from `ltbase.api/cmd/api/schemas/` into `customer-owned/schemas/`.
- [ ] Keep filenames unchanged so the existing publish manifest and runtime schema references remain stable.

### Task 3: Verify the deployment workflow input exists

**Files:**
- No source changes expected

- [ ] Run `bash ./test/publish-schemas-test.sh` and confirm it passes.
- [ ] Run `git status --short` and confirm only the expected deployment-repo files changed.

### Task 4: Record the decision

**Files:**
- Create: `docs/superpowers/specs/2026-04-18-schema-ownership-move-design.md`
- Create: `docs/superpowers/plans/2026-04-18-schema-ownership-move.md`

- [ ] Save the approved design in the repo.
- [ ] Save this implementation plan in the repo.
