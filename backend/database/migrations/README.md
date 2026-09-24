# Database Migrations

Ordered, forward-only SQL migrations for the WREN Writing Coach relational store
(RDS PostgreSQL 16 + `pgvector`, reached through RDS Proxy with TLS enforced).

Migrations are plain `.sql` files so they are runtime-agnostic — the Node
(`postgres`) and Python (`psycopg`) data-access layers (task 2.4) execute the same
DDL. They are applied in lexical filename order. Summary:

| File | Purpose |
|------|---------|
| `0001_baseline.sql` | Squashed baseline: extensions (`vector`, `pgcrypto`), the full core relational schema in V4 terminology (`department`, `document_type`, `document_type_config`, …), Department catalog visibility (`department.visibility_state` + `department_visibility_grant`), the nullable `department.ask_wren_prompt` column, the Draft-immutability trigger, the least-privilege app LOGIN roles + grants, and seed data (platform policy, notification-type catalog, the Law example department). |
| `0002_authorizer_grants_repair.sql` | Authorizer throttling remediation (Task 5): idempotently re-applies the `wren_authorizer` table privileges (`app_user` SELECT/INSERT/UPDATE, `role_assignment` SELECT/INSERT, `access_grant` SELECT) plus CONNECT/USAGE. Forward-only fix for the Sep 3 Postgres 42501 (permission denied for `app_user`) on environments created before those grants were folded into the squashed baseline — such databases already recorded `0001` and never re-ran the rewritten file. |
| `0003_document_usage_grants_repair.sql` | Document upload remediation: idempotently grants `wren_document` SELECT/INSERT/UPDATE on `user_lifetime_usage` (the per-user lifetime upload cap), which the baseline omitted. Same forward-only rationale as `0002`. |
| `0004_activity_event_append_only_repair.sql` | Activity-log tamper-resistance remediation: makes `activity_event` append-only via the `reject_activity_event_mutation()` trigger and strips the excess UPDATE/DELETE from `wren_admin` (re-asserting SELECT/INSERT only). Forward-only fix for environments provisioned before these protections were folded into the baseline. |

Filenames are applied in **lexical order**. Do not edit an already-applied file — add a new numbered migration instead.

> **Consolidation history.** The earlier per-feature migrations
> (`0001_enable_extensions.sql`, `0002_initial_schema.sql`,
> `0003_v4_terminology_migration.sql`, `0004`–`0036_*.sql`) were consolidated into
> `0001_baseline.sql`. A later round folded the post-baseline migrations
> `0002_department_visibility.sql`, `0003_department_ask_wren_prompt.sql`,
> `0004_department_visibility_grant_privileges.sql`,
> `0005_authorizer_app_user_update_privilege.sql`, and
> `0006_seed_law_department.sql` into the same baseline. Squashing only changes
> what a **fresh** database receives; a database that has already recorded
> `0001_baseline.sql` in `schema_migrations` will not re-run the rewritten file,
> so consolidation must be paired with rebuilding such environments (or applying
> the folded statements out of band).

## Naming

The design document's historical **Writing Domain** entity is implemented as
**`document_type`**. It is data, never a hardcoded domain enumeration.
Administrative groupings are **`department`** rows (not tenants). All identifiers
use `snake_case`. The baseline defines these V4 names directly (the pre-V4
`organization` / `writing_type` names no longer appear as tables).

## Schema invariants enforced here

These are the structural guarantees the schema upholds (asserted by
`backend/database/schema.test.ts`):

1. **Immutable Drafts** — a `BEFORE UPDATE` trigger (`draft_immutable`) rejects any
   update to a `draft` row. Revision creates a new Draft; prior Drafts are
   retained. `DELETE` is allowed only so a Document delete can cascade.
   (Requirement 8.1)
2. **Category linkage by id** — `feedback_item.error_category_id` is a foreign key
   to `error_category(id)`, so renaming a category (which changes only `name`)
   preserves every Feedback Item's linkage. (Requirement 15.3)
3. **No replacement prose** — no table has a `replacement_prose` column. Only
   `{category, question, anchor?, citation?}` are persisted for a Feedback Item.
   (Requirement 11.4 / REQ-CORE-NOGHOST-01)
4. **ActivityEvent independent of Documents** — `activity_event` holds no foreign
   key to `document`, `draft`, or `feedback_item`, so deleting a Document never
   deletes activity-log events. (Requirement 44.2)
5. **Departments are groupings, not tenants** — Departments own no users;
   `app_user` is global. (Requirements 28.1 / 28.2)
6. **Deletion retention partitioning** — deleting a `document` cascades to its
   operational state (`draft`, `anchor`, `feedback_item`,
   `resolution_status_history`) but never to `activity_event` /
   `aggregate_counter`.

`resolution_status_history` is additionally append-only (a `BEFORE UPDATE` trigger
blocks mutation; a re-evaluation inserts a new `(feedback_item, draft)` row).

## Running

Apply with any PostgreSQL client over the TLS-enforced RDS Proxy endpoint, e.g.:

```bash
psql "$DATABASE_URL?sslmode=require" -f 0001_baseline.sql
```

A programmatic migration runner is provided by the data-access layer (task 2.4):
`runMigrations` in `../node` (`@wren/db-node`) and `run_migrations` in
`../python` (`wren_db.migrate`). Both apply these files in lexical filename order
over the TLS-enforced RDS Proxy endpoint, tracking applied files in a
`schema_migrations` table so re-runs are idempotent. Migrations are forward-only;
add a new numbered file rather than editing an applied one.
