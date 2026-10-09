# RFC 20260928 — Core RLS policies: guard against an empty tenant GUC

**Owner:** wp-00 (Core). **Status:** resolved — `NULLIF(current_setting('app.tenant_id', true), '')` is in `Core.Migration` and migration `20260928140000_core_rls_nullif_empty_guc`.

## Context

Every tenant-owned table created by `SportsCoachBookings.Core.Migration.tenant_table/3`
gets a policy:

```sql
USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
```

Postgres returns `NULL` from `current_setting(name, true)` only while the custom
GUC is *unknown*. Once a connection has run `set_config('app.tenant_id', …)`
(even transaction-locally) and that transaction is rolled back — which the SQL
Sandbox does for every test — the placeholder becomes defined at session scope
with its reset value, an **empty string**. A later statement that consults the
policy without setting the GUC then evaluates `''::uuid` and raises
`invalid_text_representation`.

This is observable as a seed/ordering-dependent failure of
`RepoTenancyTest."skip_tenant bypasses the guard (RLS still applies)"`
(`Repo.all(Event, skip_tenant: true)`), which does not set the GUC. It is
unrelated to WP-02; WP-02's own isolation tests set the GUC and pass.

## Proposal

Change the policy predicate (in `core/migration.ex` and the core
`core_tenants` migration for `audit_events`) to:

```sql
tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
```

wp-01 already uses exactly this pattern for its additive
`memberships_self_read` policy, so the fix is consistent with the codebase.
An empty or unset GUC then yields `NULL`, the predicate is `NULL`, and RLS
returns no rows instead of erroring.

## Not changed

- WP-02 does **not** edit `core/*`; this RFC is the hand-off to wp-00. WP-02's
  tables use the same `tenant_table/3` helper and would benefit from the fix.
