# SportsCoachBookings — Entity Relationship Document

Status: living document, owned by wp-00. Every context owner adds/extends its own
tables through migrations; cross-context foreign keys require an RFC
(`docs/rfcs/`).

Source of truth: `00-shared-context.md` and the `agent-briefs/wp-*.md` "Schemas"
sections. This file describes the logical schema. It does not replace the
migrations.

## How to read this document

Types use canonical tokens:

| Token | Meaning |
|---|---|
| `uuid` | Postgres `uuid`. Primary keys are UUIDv7 (RFC 9562), generated in Elixir by `SportsCoachBookings.Core.Types.UUIDv7`; FK columns are `uuid` with `@foreign_key_type :binary_id`. |
| `citext` | Case-insensitive text (`citext` extension). Used for emails and host names. |
| `string` | `varchar`; Ecto `:string`. |
| `text` | Unbounded text. |
| `integer` | 32-bit integer. All money is `integer` **minor units** (cents), never float. |
| `bigint` | 64-bit integer. |
| `boolean` | boolean. |
| `date` / `time` | calendar date / wall-clock time. |
| `utc_datetime_usec` | `timestamp(6) without time zone`, interpreted as UTC. Used for every timestamp. |
| `jsonb` | JSON object/array (Ecto `:map` or embedded schema serialised to `jsonb`). |
| `uuid[]` / `text[]` | Postgres arrays. |
| `inet` | Postgres `inet` (IP address capture). |

Each table entry states:

- **Owner** — the WP that owns the table.
- **Tenancy** — `tenant-owned` (has `tenant_id`, an RLS policy, created with
  `Core.Migration.tenant_table/3`) or `platform` (no `tenant_id`, no RLS).
- **PK / FK / Indexes** — keys and notable indexes/constraints.
- A column table: `Column | Type | Null | Default | Notes`.

A column marked `AMBIGUITY` is not fully pinned down by the briefs; see
[Ambiguities](#ambiguities) at the end. Nothing is invented to fill those gaps.

## Standard conventions applied to every table

1. **Primary key.** `id uuid primary key`, UUIDv7, generated in Elixir. No
   database default is required (`Core.Schema` sets
   `@primary_key {:id, Core.Types.UUIDv7, autogenerate: true}`).
2. **Timestamps.** `inserted_at` and `updated_at`,
   `utc_datetime_usec not null`. Ledger/history tables may omit `updated_at`
   (`timestamps(updated_at: false)`) because rows are append-only.
3. **Tenant ownership.** Every tenant-owned table has
   `tenant_id uuid not null references tenants(id) on delete cascade`, an index
   on `tenant_id`, `ENABLE` + `FORCE ROW LEVEL SECURITY`, and a policy
   `tenant_id = current_setting('app.tenant_id', true)::uuid`. Create it with
   `SportsCoachBookings.Core.Migration.tenant_table/3`.
4. **Platform tables.** `tenants`, `tenant_domains`, `webhook_events`, and the
   `oban_*` tables are not tenant-scoped and have no RLS. They are queried with
   `skip_tenant: true`, justified in review.
5. **Money.** Integer minor units + the tenant's ISO-4217 currency (the tenant
   has exactly one currency). No `currency` column on line/amount tables, except
   `orders.currency`, which snapshots the currency at order time.
6. **Time.** All timestamps `utc_datetime_usec`; tenants and venues carry IANA
   timezones. The API returns ISO-8601 UTC.
7. **Soft delete / archival.** The briefs generally use `active` booleans,
   `status` enums, or `deleted` tenant status instead of row deletion.
8. **Enums.** Stored as `string` columns with Ecto enum values; the allowed set
   is listed per column.

---

## Platform & core (wp-00)

### tenants

- **Owner:** wp-00, extended by wp-01. **Tenancy:** platform (no `tenant_id`, no RLS).
- **PK:** `id`. **FK:** —. **Indexes:** `unique(slug)`. Later: `unique(tenant_domains.host)` is on the child.
- Referenced by every tenant-owned table via `tenant_id`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| name | string | no | — | |
| slug | citext | no | — | unique; reserved-word blocklist enforced in wp-01 |
| status | string | no | `active` | Ecto enum `active | deleted`; wp-01 soft-deletes by setting `deleted` |
| timezone | string | no | `America/Toronto` | IANA tz |
| currency | string | no | `CAD` | ISO-4217; locked after first paid order (see Ambiguities) |
| contact_email | string | yes | — | reply-to / contact |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

wp-01 extends this table (settings, ownership transfer, deletion). Additional
columns (for example a currency-locked flag or tax/reminder settings) are added
by wp-01's own migration; see Ambiguities.

### tenant_domains

- **Owner:** wp-00. **Tenancy:** platform. Custom domains are out of MVP; subdomains only.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id) on delete cascade`. **Indexes:** `unique(host)`, `index(tenant_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| host | citext | no | — | unique; e.g. `demo.sportscoachbookings.com` |
| primary | boolean | no | `false` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### audit_events

- **Owner:** wp-00 (`Core.Audit`). **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`, `index(resource_type, resource_id)`, `index(action)`. Append-only (no `updated_at`).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| actor_type | string | yes | — | `"StaffActor" | "CustomerActor" | nil` |
| actor_id | uuid | yes | — | staff_user_id or customer_user_id |
| action | string | no | — | dotted snake_case, e.g. `staff.role_changed` |
| resource_type | string | yes | — | Ecto module name as string |
| resource_id | uuid | yes | — | |
| metadata | jsonb | no | `{}` | JSON; never secrets or raw medical values |
| inserted_at | utc_datetime_usec | no | now | |

### webhook_events

- **Owner:** wp-04. **Tenancy:** platform — explicitly **not** tenant-scoped at insert; tenant is resolved later from payload/account. Queries that are tenant-scoped must use `skip_tenant: true` with a comment.
- **PK:** `id`. **FK:** —. **Indexes:** `unique(event_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| provider | string | no | — | e.g. `stripe`, `resend` |
| event_id | string | no | — | provider event id; unique (dedupe) |
| type | string | no | — | provider event type |
| payload | jsonb | yes | — | raw event |
| processed_at | utc_datetime_usec | yes | — | set when the Oban job finishes |
| error | text | yes | — | last processing error |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### oban_jobs, oban_peers (and any further `oban_*`)

- **Owner:** wp-00 (installed by `Oban.Migrations.up()`). **Tenancy:** platform.
- Schema is owned by the Oban version in `mix.exs` (~> 2.18); the exact table set
  and columns follow `Oban.Migrations`. Do not hand-edit these tables.
- `oban_jobs.args` carries `tenant_id` for tenant work. The transactional outbox
  (`Events.publish/2`) inserts a job on the `:events` queue in the same
  transaction as the state change.

---

## Tenancy & Staff (wp-01)

### staff_users

- **Owner:** wp-01. **Tenancy:** platform/global — staff identity is **not**
  tenant-scoped (one login across tenants via a cookie on `.sportscoachbookings.com`).
- **PK:** `id`. **FK:** —. **Indexes:** `unique(email)`. Generated by `phx.gen.auth`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| email | citext | no | — | unique |
| hashed_password | string | no | — | |
| confirmed_at | utc_datetime_usec | yes | — | email confirmation |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### staff_users_tokens

- **Owner:** wp-01. **Tenancy:** platform/global. Generated by `phx.gen.auth`.
- **PK / FK / Indexes:** exact shape follows the generated token schema
  (`phx.gen.auth --binary-id`). Typical columns below; see Ambiguities.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK (binary_id generator) |
| token | uuid / binary | no | — | hashed/opaque token |
| context | string | no | — | e.g. `session`, `reset_password`, `confirm`, `change_email` |
| sent_to | string | yes | — | email a token was sent to (nil for sessions) |
| staff_user_id | uuid | no | — | FK staff_users |
| inserted_at | utc_datetime_usec | no | now | token lifetime for invites/resets is 7 days (enforced in app) |

### memberships

- **Owner:** wp-01. **Tenancy:** tenant-owned (RLS). Links a global `staff_user`
  to a tenant with a role.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `staff_user_id -> staff_users(id)` (cross-context to the global identity context — see notes). **Indexes:** `index(tenant_id)`, `index(staff_user_id)`, `unique(tenant_id, staff_user_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| staff_user_id | uuid | no | — | FK staff_users |
| role | string | no | — | Ecto enum `owner | admin | coach` |
| status | string | no | `active` | Ecto enum `active | removed` (soft removal) |
| display_name | string | yes | — | coach profile, shown in portal |
| bio | text | yes | — | coach profile |
| photo_key | string | yes | — | object-storage key |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### branding

- **Owner:** wp-01. **Tenancy:** tenant-owned (RLS). One row per tenant.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`; `unique(tenant_id)` (one branding row per tenant — see Ambiguities).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| logo_key | string | yes | — | S3 key |
| favicon_key | string | yes | — | S3 key |
| primary_color | string | yes | — | hex |
| secondary_color | string | yes | — | hex |
| accent_color | string | yes | — | hex |
| background_color | string | yes | — | hex |
| text_color | string | yes | — | hex |
| font_family | string | yes | — | from a fixed allowlist |
| email_footer_text | text | yes | — | CASL footer |
| social_links | jsonb | no | `{}` | map |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### staff_invites

- **Owner:** wp-01. **Tenancy:** tenant-owned (RLS).
- **Name is inferred** — the brief describes the invite flow but not the table
  name. **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `invited_by` (membership/staff) cross-context. **Indexes:** `index(tenant_id)`, `unique(token_hash)` (see Ambiguities).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| email | citext | no | — | invitee |
| role | string | no | — | `owner | admin | coach` |
| token_hash | string | no | — | single-use, 7-day expiry |
| invited_by | uuid | yes | — | membership id (or staff_user_id) |
| expires_at | utc_datetime_usec | no | — | |
| accepted_at | utc_datetime_usec | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Customers (wp-02)

### customer_users

- **Owner:** wp-02. **Tenancy:** tenant-owned (RLS). Customer identity is
  **per tenant**: the same email at two tenants is two independent accounts.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `unique(tenant_id, email)` using `citext` (implements `(tenant_id, lower(email))`).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| email | citext | no | — | unique per tenant |
| hashed_password | string | no | — | |
| first_name | string | no | — | registration fields |
| last_name | string | no | — | |
| phone | string | yes | — | E.164 |
| terms_version | string | yes | — | accepted terms version + timestamp |
| terms_accepted_at | utc_datetime_usec | yes | — | |
| privacy_version | string | yes | — | accepted privacy version + timestamp |
| privacy_accepted_at | utc_datetime_usec | yes | — | |
| confirmed_at | utc_datetime_usec | yes | — | confirmation required before purchase/booking (login allowed) |
| active | boolean | no | `true` | deactivation blocks login, retains data (see Ambiguities) |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### customer_users_tokens

- **Owner:** wp-02. **Tenancy:** tenant-owned (RLS). `phx.gen.auth` tokens for the
  tenant-scoped customer identity.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants; RLS |
| token | uuid / binary | no | — | |
| context | string | no | — | `session | reset_password | confirm | change_email` |
| sent_to | string | yes | — | |
| customer_user_id | uuid | no | — | FK customer_users |
| inserted_at | utc_datetime_usec | no | now | |

### households

- **Owner:** wp-02. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`
  (plus any columns wp-02 adds for lookup).
- **AMBIGUITY:** the brief does not enumerate household columns beyond the
  tenant scope, members, and one-household-per-user rule.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### household_members

- **Owner:** wp-02. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `household_id -> households(id)`;
  `customer_user_id -> customer_users(id)`. **Indexes:** `index(tenant_id)`,
  `unique(household_id, customer_user_id)`, and a uniqueness constraint giving
  one household per customer user in MVP ([Ambiguities](#ambiguities)).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| household_id | uuid | no | — | FK households |
| customer_user_id | uuid | no | — | FK customer_users |
| role | string | no | — | Ecto enum `primary | manager` |
| relationship | string | yes | — | free text, e.g. "parent" |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### household_invites

- **Owner:** wp-02. **Tenancy:** tenant-owned (RLS).
- **Name is inferred** — brief describes the invite but not the table.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `household_id -> households(id)`;
  `invited_by -> customer_users(id)`. **Indexes:** `index(tenant_id)`,
  `unique(token_hash)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| household_id | uuid | no | — | FK households |
| email | citext | no | — | invitee |
| relationship | string | yes | — | |
| token_hash | string | no | — | single-use, 7 days |
| invited_by | uuid | yes | — | FK customer_users |
| expires_at | utc_datetime_usec | no | — | |
| accepted_at | utc_datetime_usec | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Catalog (wp-03)

### venues

- **Owner:** wp-03. **Tenancy:** tenant-owned (RLS). Coaches have read-only access.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`, `index(tenant_id, active)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| name | string | no | — | |
| address_line1 | string | yes | — | AMBIGUITY: exact address field set not enumerated |
| address_line2 | string | yes | — | |
| city | string | yes | — | |
| province / region | string | yes | — | |
| postal_code | string | yes | — | |
| country | string | yes | — | |
| timezone | string | no | tenant timezone | IANA |
| notes | text | yes | — | |
| map_url | string | yes | — | |
| active | boolean | no | `true` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### offerings

- **Owner:** wp-03. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`, `unique(tenant_id, slug)`, `index(tenant_id, active, format)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| name | string | no | — | |
| slug | string | no | — | unique per tenant |
| description | text | yes | — | |
| format | string | no | — | Ecto enum `private | semi_private | group` |
| min_age | integer | yes | — | |
| max_age | integer | yes | — | nullable |
| duration_minutes | integer | no | — | |
| default_capacity | integer | no | — | capacity 1 = private |
| credit_cost | integer | no | `1` | credits per booking |
| drop_in_price | integer | yes | — | minor units; null = credits only |
| taxable | boolean | yes | AMBIGUITY (default not stated) | |
| bookable_until_minutes_before | integer | no | `60` | booking window |
| bookable_from_days_ahead | integer | yes | — | null = no limit |
| active | boolean | no | `true` | archive instead of delete when referenced |
| position | integer | no | `0` | reorderable |
| image_key | string | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### packages

- **Owner:** wp-03. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`,
  `index(tenant_id, active)`. Eligible offerings are in `package_offerings`; empty
  set = all offerings.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| name | string | no | — | |
| description | text | yes | — | |
| credit_quantity | integer | no | — | |
| validity_days | integer | yes | — | null = no expiry |
| price | integer | no | — | minor units |
| taxable | boolean | yes | AMBIGUITY (default not stated) | |
| per_household_limit | integer | yes | — | |
| active | boolean | no | `true` | |
| visible_in_portal | boolean | no | `true` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

AMBIGUITY: the brief mentions reordering packages but does not list a
`position` column for packages (offerings have one).

### package_offerings

- **Owner:** wp-03. **Tenancy:** tenant-owned (RLS). Join table; empty = all offerings.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `package_id -> packages(id)`;
  `offering_id -> offerings(id)`. **Indexes:** `unique(package_id, offering_id)`, `index(tenant_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| package_id | uuid | no | — | FK packages |
| offering_id | uuid | no | — | FK offerings |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### discounts

- **Owner:** wp-03. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`,
  partial `unique(tenant_id, code) where code is not null`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| code | citext | yes | — | null = automatic discount |
| kind | string | no | — | Ecto enum `percent | fixed` |
| value | integer | no | — | AMBIGUITY: percent basis (bps/fraction) vs fixed minor units not stated |
| applies_to | string | no | — | Ecto enum `all | packages | drop_ins | products` |
| starts_at | utc_datetime_usec | yes | — | |
| ends_at | utc_datetime_usec | yes | — | |
| max_redemptions | integer | yes | — | |
| per_household_limit | integer | yes | — | |
| min_subtotal | integer | yes | — | minor units |
| active | boolean | no | `true` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### discount target join (name not specified)

- **Owner:** wp-03. **Tenancy:** tenant-owned (RLS).
- The brief lists "optional target IDs (join table)" but does not name it or the
  referenced tables (`offerings`, `packages`, `products`). See
  [Ambiguities](#ambiguities). Expected shape:

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| discount_id | uuid | no | — | FK discounts |
| target_type | string | no | — | `offering | package | product` (inferred) |
| target_id | uuid | no | — | polymorphic reference (inferred) |

### discount_redemptions

- **Owner:** wp-03 (written by wp-13 via `Catalog.record_redemption/3`).
  **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `discount_id -> discounts(id)`
  (same context); `household_id` and `order_id` are cross-context references
  (Customers, Commerce). **Indexes:** `index(tenant_id)`; a uniqueness constraint
  for idempotency is desirable ([Ambiguities](#ambiguities)).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| discount_id | uuid | no | — | FK discounts |
| household_id | uuid | no | — | cross-context (Customers), uuid only |
| order_id | uuid | no | — | cross-context (Commerce), uuid only |
| inserted_at | utc_datetime_usec | no | now | |

### tax_rates

- **Owner:** wp-03. **Tenancy:** tenant-owned (RLS). MVP: one active rate.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`;
  partial `unique(tenant_id) where active` is a possible enforcement of the
  one-active-rate rule ([Ambiguities](#ambiguities)).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| name | string | no | — | e.g. "HST" |
| rate_bps | integer | no | — | basis points |
| active | boolean | no | `true` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Payments (wp-04)

### provider_accounts

- **Owner:** wp-04. **Tenancy:** tenant-owned (RLS). Owner-only endpoints.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`,
  `unique(tenant_id, provider)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| provider | string | no | — | e.g. `stripe` |
| account_ref | string | no | — | connected account id |
| status | string | yes | — | provider account status |
| charges_enabled | boolean | no | `false` | |
| payouts_enabled | boolean | no | `false` | |
| requirements | jsonb | no | `{}` | map of due requirements |
| platform_fee_bps | integer | no | `0` | pending decision #1; see Ambiguities |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### payments

- **Owner:** wp-04. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `order_id` is a cross-context
  reference to Commerce (uuid only by default). **Indexes:** `index(tenant_id)`,
  `index(order_id)`, `unique(provider, payment_ref)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| provider | string | no | — | |
| order_id | uuid | yes | — | cross-context (Commerce) |
| checkout_ref | string | yes | — | provider checkout session id |
| payment_ref | string | yes | — | provider payment/intent id |
| amount | integer | no | — | minor units |
| status | string | no | — | Ecto enum `pending | succeeded | failed | expired` |
| raw | jsonb | no | `{}` | raw provider payload |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### refunds

- **Owner:** wp-04. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `payment_id -> payments(id)`.
  **Indexes:** `index(tenant_id)`, `index(payment_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| payment_id | uuid | no | — | FK payments |
| amount | integer | no | — | minor units |
| reason | text | yes | — | |
| refund_ref | string | yes | — | provider refund id |
| status | string | no | — | provider refund status |
| actor | ? | yes | — | AMBIGUITY: shape not specified (string? actor_type/actor_id?) |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Notifications (wp-05)

### messages

- **Owner:** wp-05. **Tenancy:** tenant-owned (RLS). One row per `deliver/4` call.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`;
  `unique(tenant_id, idempotency_key) where idempotency_key is not null`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| template_key | string | no | — | registry key |
| category | string | no | `transactional` | Ecto enum `transactional | operational | marketing` |
| subject | string | yes | — | rendered subject |
| idempotency_key | string | yes | — | unique per tenant; same key twice is a no-op |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### deliveries

- **Owner:** wp-05. **Tenancy:** tenant-owned (RLS). One row per recipient.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `message_id -> messages(id)`.
  `recipient_id` is a cross-context actor reference. **Indexes:** `index(tenant_id)`,
  `index(message_id)`, `index(tenant_id, email, inserted_at)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| message_id | uuid | no | — | FK messages |
| recipient_type | string | no | — | Ecto enum `customer_user | staff_user | email` |
| recipient_id | uuid | yes | — | cross-context; null when type = `email` |
| email | citext | no | — | destination address |
| status | string | no | — | `queued | sent | delivered | bounced | complained | failed | suppressed` |
| provider_ref | string | yes | — | Resend message id |
| sent_at | utc_datetime_usec | yes | — | |
| delivered_at | utc_datetime_usec | yes | — | |
| bounced_at | utc_datetime_usec | yes | — | |
| error | text | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### suppressions

- **Owner:** wp-05. **Tenancy:** tenant-owned (RLS). Hard bounces/complaints;
  password reset is exempt from suppression.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `unique(tenant_id, email)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| email | citext | no | — | |
| reason | string | no | — | `bounce | complaint` |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### notification_preferences

- **Owner:** wp-05. **Tenancy:** tenant-owned (RLS). Per customer user or staff user.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `unique` per
  (tenant, subject) — see Ambiguities.
- **AMBIGUITY:** the subject is "per customer user / staff user"; whether this is
  polymorphic (`subject_type` + `subject_id`) or two nullable FK columns
  (`customer_user_id`, `staff_user_id`) is not specified.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| subject_type | string | no | — | inferred: `customer_user | staff_user` |
| subject_id | uuid | no | — | inferred |
| marketing_opt_in | boolean | no | `false` | CASL requires express consent |
| operational | boolean | no | `true` | always on |
| transactional | boolean | no | `true` | always on |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Players (wp-06)

### players

- **Owner:** wp-06. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `household_id` is cross-context
  (Customers). **Indexes:** `index(tenant_id)`, `index(tenant_id, household_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| household_id | uuid | no | — | cross-context (Customers) |
| first_name | string | no | — | |
| last_name | string | no | — | |
| preferred_name | string | yes | — | |
| date_of_birth | date | no | — | |
| is_self | boolean | no | `false` | adult booking for themselves |
| photo_key | string | yes | — | |
| active | boolean | no | `true` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### player_profiles

- **Owner:** wp-06. **Tenancy:** tenant-owned (RLS). One row per player.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `player_id -> players(id)`.
  **Indexes:** `unique(player_id)`, `index(tenant_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| player_id | uuid | no | — | FK players; unique |
| home_club | string | yes | — | |
| team | string | yes | — | |
| preferred_positions | text[] | no | `{}` | validated against `player_position_options` |
| dominant_foot / handedness | string | yes | — | optional |
| goals | text | yes | — | |
| interests | text[] | yes | — | AMBIGUITY: array vs tag model |
| notes_from_family | text | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### player_position_options

- **Owner:** wp-06. **Tenancy:** tenant-owned (RLS). Tenant-configurable; seeded
  with soccer positions (GK, CB, FB, DM, CM, AM, W, ST).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`,
  `unique(tenant_id, code)` (inferred).
- **AMBIGUITY:** exact columns (code/label/position/active) not enumerated.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| code | string | no | — | inferred, e.g. `GK` |
| label | string | yes | — | inferred display label |
| position | integer | no | `0` | inferred ordering |
| active | boolean | no | `true` | inferred |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### emergency_contacts

- **Owner:** wp-06. **Tenancy:** tenant-owned (RLS). At least one required before a
  player is bookable.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `player_id -> players(id)`.
  **Indexes:** `index(tenant_id)`, `index(player_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| player_id | uuid | no | — | FK players |
| name | string | no | — | |
| relationship | string | yes | — | |
| phone | string | no | — | E.164 |
| alt_phone | string | yes | — | |
| priority | integer | no | — | 1..n |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### authorized_pickups

- **Owner:** wp-06. **Tenancy:** tenant-owned (RLS). Optional list.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `player_id -> players(id)`.
  **Indexes:** `index(tenant_id)`, `index(player_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| player_id | uuid | no | — | FK players |
| name | string | no | — | |
| relationship | string | yes | — | |
| phone | string | yes | — | |
| notes | text | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

AMBIGUITY: the brief allows an explicit `no_pickup_restrictions` flag but does
not say on which table it lives (likely `players`).

### medical_info

- **Owner:** wp-06. **Tenancy:** tenant-owned (RLS). One row per player. Text
  fields encrypted at rest with `cloak_ecto`; `has_medical_info` is unencrypted
  for quick display. Every read is audited.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `player_id -> players(id)`.
  **Indexes:** `unique(player_id)`, `index(tenant_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| player_id | uuid | no | — | FK players; unique |
| allergies | text (ciphertext) | yes | — | encrypted |
| conditions | text (ciphertext) | yes | — | encrypted |
| medications | text (ciphertext) | yes | — | encrypted |
| notes | text (ciphertext) | yes | — | encrypted |
| has_medical_info | boolean | no | `false` | unencrypted |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Waivers (wp-07)

### waiver_templates

- **Owner:** wp-07. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`,
  `index(tenant_id, active)`. Offering scope is in `waiver_template_offerings`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| name | string | no | — | |
| scope | string | no | — | Ecto enum `all_bookings | offerings` |
| require_resign_on_new_version | boolean | no | `false` | |
| active | boolean | no | `true` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### waiver_template_offerings

- **Owner:** wp-07. **Tenancy:** tenant-owned (RLS). Join for `scope = offerings`.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `waiver_template_id -> waiver_templates(id)`;
  `offering_id` is cross-context (Catalog). **Indexes:** `unique(waiver_template_id, offering_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| waiver_template_id | uuid | no | — | FK waiver_templates |
| offering_id | uuid | no | — | cross-context (Catalog) |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### waiver_versions

- **Owner:** wp-07. **Tenancy:** tenant-owned (RLS). Published versions are
  immutable; publishing a new version supersedes the previous one.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `waiver_template_id -> waiver_templates(id)`.
  **Indexes:** `unique(waiver_template_id, version)`, `index(tenant_id)`;
  a partial unique on one `published` version per template is likely.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| waiver_template_id | uuid | no | — | FK waiver_templates |
| version | integer | no | — | monotonic per template |
| body_markdown | text | no | — | immutable once published |
| status | string | no | `draft` | Ecto enum `draft | published | superseded` |
| published_at | utc_datetime_usec | yes | — | |
| content_sha256 | string | no | — | hash of the signed body |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### waiver_signatures

- **Owner:** wp-07. **Tenancy:** tenant-owned (RLS). One signature per version per
  player (inferred). `content_sha256` must equal the version's.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `waiver_version_id -> waiver_versions(id)`;
  `player_id` (Players) and `customer_user_id` (Customers) are cross-context.
  **Indexes:** `index(tenant_id)`, `index(player_id)`, `index(waiver_version_id)`;
  a uniqueness constraint per (version, player) is likely.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| waiver_version_id | uuid | no | — | FK waiver_versions |
| player_id | uuid | no | — | cross-context (Players) |
| customer_user_id | uuid | no | — | cross-context (Customers); signer |
| signer_name_typed | string | no | — | |
| signer_relationship | string | yes | — | |
| consent_checkbox | boolean | no | `false` | must be `true` |
| signed_at | utc_datetime_usec | no | — | |
| ip | inet | no | — | |
| user_agent | text | no | — | |
| content_sha256 | string | no | — | must match version |
| pdf_key | string | yes | — | async PDF snapshot |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Inventory (wp-08)

### products

- **Owner:** wp-08. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`, `index(tenant_id, active)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| name | string | no | — | |
| description | text | yes | — | |
| image_keys | text[] | no | `{}` | |
| taxable | boolean | yes | AMBIGUITY (default not stated) | |
| active | boolean | no | `true` | |
| visible_in_portal | boolean | no | `true` | |
| position | integer | no | `0` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### product_variants

- **Owner:** wp-08. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `product_id -> products(id)`.
  **Indexes:** `unique(tenant_id, sku)`, `index(product_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| product_id | uuid | no | — | FK products |
| sku | string | no | — | unique per tenant |
| option_values | jsonb | no | `{}` | e.g. `{"size":"YM","colour":"Navy"}` |
| price | integer | no | — | minor units |
| low_stock_threshold | integer | yes | — | |
| active | boolean | no | `true` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### stock_levels

- **Owner:** wp-08. **Tenancy:** tenant-owned (RLS). Single location in MVP;
  `venue_id` is nullable for future multi-location.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `variant_id -> product_variants(id)`;
  `venue_id` is cross-context (Catalog). **Indexes:** `index(tenant_id)`,
  `unique(variant_id, venue_id)` (MVP effectively unique per variant).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| variant_id | uuid | no | — | FK product_variants |
| on_hand | integer | no | `0` | |
| reserved | integer | no | `0` | |
| venue_id | uuid | yes | — | cross-context (Catalog) |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### stock_movements

- **Owner:** wp-08. **Tenancy:** tenant-owned (RLS). Append-only ledger:
  `on_hand == sum(delta for non-reservation movements)`.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `variant_id -> product_variants(id)`.
  `order_id` is cross-context (Commerce). **Indexes:** `index(tenant_id)`,
  `index(variant_id, inserted_at)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| variant_id | uuid | no | — | FK product_variants |
| delta | integer | no | — | signed |
| kind | string | no | — | Ecto enum `received | sold | adjusted | returned | reserved | released` |
| order_id | uuid | yes | — | cross-context (Commerce) |
| actor | ? | yes | — | AMBIGUITY: shape not specified |
| note | text | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |

### fulfillments

- **Owner:** wp-08. **Tenancy:** tenant-owned (RLS). One per order line.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `pickup_venue_id` cross-context
  (Catalog); `picked_up_by` cross-context (Staff). `order_line_id` is cross-context
  (Commerce). **Indexes:** `index(tenant_id)`, `index(order_line_id)`, `index(tenant_id, status)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| order_line_id | uuid | no | — | cross-context (Commerce) |
| status | string | no | `pending` | Ecto enum `pending | ready_for_pickup | picked_up | cancelled` |
| pickup_venue_id | uuid | yes | — | cross-context (Catalog) |
| picked_up_at | utc_datetime_usec | yes | — | |
| picked_up_by | uuid | yes | — | cross-context (Staff membership) |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Policies (wp-10)

### cancellation_policies

- **Owner:** wp-10. **Tenancy:** tenant-owned (RLS). Editing creates a new
  version; existing bookings keep their snapshot.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`;
  partial `unique(tenant_id) where is_default` (one default per tenant).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| name | string | no | — | |
| is_default | boolean | no | `false` | one per tenant |
| version | integer | no | — | |
| active | boolean | no | `true` | |
| rules | jsonb | no | — | embedded `%Rules{}`: cancellation tiers, no-show, rebook, provider-cancel |
| customer_facing_summary | text | yes | — | markdown shown in portal/emails |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### offering_policy_assignments

- **Owner:** wp-10. **Tenancy:** tenant-owned (RLS). Optional per-offering override
  of the default policy.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `cancellation_policy_id -> cancellation_policies(id)`;
  `offering_id` cross-context (Catalog). **Indexes:** `unique(offering_id)` (one
  policy per offering), `index(tenant_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| offering_id | uuid | no | — | cross-context (Catalog) |
| cancellation_policy_id | uuid | no | — | FK cancellation_policies |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Scheduling (wp-11)

### sessions

- **Owner:** wp-11. **Tenancy:** tenant-owned (RLS). `booked_count` and
  `held_count` are written **only** by wp-14 through `Scheduling.Seats`.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `offering_id`, `venue_id` are
  cross-context (Catalog); `series_id -> session_series(id)`. **Indexes:**
  `index(tenant_id, starts_at)`, `index(tenant_id, offering_id)`,
  `index(tenant_id, status)`. **Checks:** `ends_at > starts_at`,
  `booked_count + held_count <= capacity`, `capacity >= 1`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| offering_id | uuid | no | — | cross-context (Catalog) |
| venue_id | uuid | no | — | cross-context (Catalog) |
| starts_at | utc_datetime_usec | no | — | |
| ends_at | utc_datetime_usec | no | — | |
| capacity | integer | no | — | >= 1 |
| booked_count | integer | no | `0` | written only by wp-14 |
| held_count | integer | no | `0` | written only by wp-14 |
| status | string | no | `scheduled` | Ecto enum `scheduled | cancelled | completed` |
| visibility | string | no | `public` | Ecto enum `public | hidden` (hidden = staff-only bookable) |
| title_override | string | yes | — | |
| notes_public | text | yes | — | |
| notes_staff | text | yes | — | |
| series_id | uuid | yes | — | FK session_series |
| cancel_reason | text | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### session_coaches

- **Owner:** wp-11. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `session_id -> sessions(id)`;
  `membership_id` cross-context (Staff). **Indexes:** `unique(session_id, membership_id)`,
  `index(tenant_id)`, `index(membership_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| session_id | uuid | no | — | FK sessions |
| membership_id | uuid | no | — | cross-context (Staff) |
| lead | boolean | no | `false` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### session_series

- **Owner:** wp-11. **Tenancy:** tenant-owned (RLS). Used only at creation/edit
  time; sessions are always materialised rows (no runtime RRULE expansion).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `index(tenant_id)`.
- **AMBIGUITY:** the brief describes the recurrence definition (weekday set,
  local start time, duration, date range, venue tz) but does not enumerate column
  names.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| weekdays | integer[] | no | — | inferred: ISO weekday set |
| start_time_local | time | no | — | inferred |
| duration_minutes | integer | no | — | inferred |
| starts_on | date | no | — | inferred |
| ends_on | date | yes | — | inferred |
| timezone | string | no | — | inferred: venue tz |
| offering_id | uuid | yes | — | inferred; cross-context |
| venue_id | uuid | yes | — | inferred; cross-context |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Credits (wp-12)

### credit_lots

- **Owner:** wp-12. **Tenancy:** tenant-owned (RLS). `remaining` is a cached
  value; the invariant is `remaining == sum(credit_ledger_entries.delta)`.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `household_id` cross-context
  (Customers); `package_id` cross-context (Catalog); `order_line_id` cross-context
  (Commerce). `eligible_offering_ids` references Catalog offerings (uuid array).
  **Indexes:** `index(tenant_id)`, `index(tenant_id, household_id)`,
  partial `unique(order_line_id) where order_line_id is not null` for idempotent
  grants.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| household_id | uuid | no | — | cross-context (Customers) |
| source | string | no | — | Ecto enum `package_purchase | admin_grant | return_grace` |
| order_line_id | uuid | yes | — | cross-context (Commerce); idempotency key |
| package_id | uuid | yes | — | cross-context (Catalog) |
| eligible_offering_ids | uuid[] | no | `{}` | snapshot; empty = all offerings |
| quantity_granted | integer | no | — | |
| remaining | integer | no | — | cached |
| expires_at | utc_datetime_usec | yes | — | null = no expiry |
| granted_at | utc_datetime_usec | no | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### credit_ledger_entries

- **Owner:** wp-12. **Tenancy:** tenant-owned (RLS). Append-only: never updated or
  deleted (revoke `UPDATE`/`DELETE` for the app role, or a trigger).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `credit_lot_id -> credit_lots(id)`;
  `reverses_entry_id -> credit_ledger_entries(id)` (self, same context); `booking_id`
  cross-context (Bookings); `household_id` cross-context (Customers).
  **Indexes:** `index(tenant_id)`, `index(credit_lot_id)`, `index(booking_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| credit_lot_id | uuid | no | — | FK credit_lots |
| household_id | uuid | no | — | cross-context (Customers) |
| delta | integer | no | — | signed |
| reason | string | no | — | Ecto enum `grant | debit | reversal | expire | adjust` |
| booking_id | uuid | yes | — | cross-context (Bookings) |
| reverses_entry_id | uuid | yes | — | FK credit_ledger_entries (self) |
| actor | ? | yes | — | AMBIGUITY: shape not specified |
| note | text | yes | — | |
| inserted_at | utc_datetime_usec | no | now | append-only; no `updated_at` |

---

## Commerce (wp-13)

### carts

- **Owner:** wp-13. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `household_id` cross-context
  (Customers). **Indexes:** `index(tenant_id)`, `index(tenant_id, household_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| household_id | uuid | no | — | cross-context (Customers) |
| discount_code | citext | yes | — | |
| expires_at | utc_datetime_usec | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### cart_lines

- **Owner:** wp-13. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `cart_id -> carts(id)`.
  `ref_id` is polymorphic (package id / variant id / booking hold id).
  **Indexes:** `index(tenant_id)`, `index(cart_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| cart_id | uuid | no | — | FK carts |
| type | string | no | — | Ecto enum `package | product | drop_in` |
| ref_id | uuid | no | — | package / variant / booking hold id |
| quantity | integer | no | `1` | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### orders

- **Owner:** wp-13. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `household_id` cross-context
  (Customers); `discount_id` cross-context (Catalog). **Indexes:** `index(tenant_id)`,
  `unique(tenant_id, number)`, `index(tenant_id, status)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| number | string | no | — | per-tenant sequence, e.g. `A-000123` |
| household_id | uuid | no | — | cross-context (Customers) |
| placed_by | ? | no | — | AMBIGUITY: customer user or staff — shape not specified |
| status | string | no | `pending_payment` | Ecto enum `pending_payment | paid | expired | cancelled | refunded | partially_refunded` |
| currency | string | no | — | ISO-4217 snapshot |
| subtotal | integer | no | — | minor units |
| discount_total | integer | no | — | minor units |
| tax_total | integer | no | — | minor units |
| total | integer | no | — | minor units |
| discount_id | uuid | yes | — | cross-context (Catalog) |
| payment_method | string | yes | — | AMBIGUITY: needed for offline orders (`offline`), not enumerated in schema list |
| expires_at | utc_datetime_usec | yes | — | 30-min hold |
| paid_at | utc_datetime_usec | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### order_lines

- **Owner:** wp-13. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `order_id -> orders(id)`.
  `ref_id` is polymorphic. **Indexes:** `index(tenant_id)`, `index(order_id)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| order_id | uuid | no | — | FK orders |
| type | string | no | — | Ecto enum `package | product | drop_in` |
| ref_id | uuid | no | — | package / variant / booking hold id |
| description | string | no | — | snapshot at purchase |
| unit_price | integer | no | — | minor units |
| quantity | integer | no | — | |
| discount_amount | integer | no | `0` | minor units |
| tax_amount | integer | no | `0` | minor units |
| line_total | integer | no | — | minor units |
| taxable | boolean | no | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

---

## Bookings (wp-14)

### bookings

- **Owner:** wp-14. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `session_id` cross-context
  (Scheduling); `player_id` cross-context (Players); `household_id` cross-context
  (Customers); `order_line_id` cross-context (Commerce); `rebooked_from_id` /
  `rebooked_to_id` self-references. **Unique partial index:** one non-cancelled
  booking per `(session_id, player_id)` (`WHERE status <> 'cancelled'`).
  **Indexes:** `index(tenant_id, session_id)`, `index(tenant_id, player_id)`,
  `index(tenant_id, household_id, status)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| session_id | uuid | no | — | cross-context (Scheduling) |
| player_id | uuid | no | — | cross-context (Players) |
| household_id | uuid | no | — | cross-context (Customers) |
| booked_by | ? | no | — | AMBIGUITY: customer user or staff — shape not specified |
| status | string | no | `held` | Ecto enum `held | confirmed | cancelled | attended | no_show` |
| payment_method | string | no | — | Ecto enum `credits | paid | comp` |
| credits_used | integer | yes | `0` | |
| order_line_id | uuid | yes | — | cross-context (Commerce) for `paid` |
| policy_snapshot | jsonb | no | — | `Policies.snapshot_for/1` output |
| rebook_count | integer | no | `0` | |
| rebooked_from_id | uuid | yes | — | self FK |
| rebooked_to_id | uuid | yes | — | self FK |
| hold_expires_at | utc_datetime_usec | yes | — | 30-min hold |
| cancelled_at | utc_datetime_usec | yes | — | |
| cancel_outcome | jsonb | yes | — | outcome applied |
| free_change_until | utc_datetime_usec | yes | — | set on `session.rescheduled`; see Ambiguities |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### booking_events

- **Owner:** wp-14. **Tenancy:** tenant-owned (RLS). History for staff; append-only.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `booking_id -> bookings(id)`.
  **Indexes:** `index(tenant_id)`, `index(booking_id, inserted_at)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| booking_id | uuid | no | — | FK bookings |
| kind | string | no | — | event kind |
| actor | ? | yes | — | AMBIGUITY: shape not specified |
| data | jsonb | no | `{}` | |
| inserted_at | utc_datetime_usec | no | now | append-only; no `updated_at` |

---

## Feedback (wp-15)

### session_feedback

- **Owner:** wp-15. **Tenancy:** tenant-owned (RLS). One row per
  `(session, player, coach)`; editable by the author for 48 h after sharing.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `session_id` cross-context
  (Scheduling); `player_id` cross-context (Players); `coach_membership_id`
  cross-context (Staff). **Indexes:** `unique(session_id, player_id, coach_membership_id)`,
  `index(tenant_id, player_id)`, `index(tenant_id, visibility)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| session_id | uuid | no | — | cross-context (Scheduling) |
| player_id | uuid | no | — | cross-context (Players) |
| coach_membership_id | uuid | no | — | cross-context (Staff) |
| body | text | no | — | markdown, <= 5k chars |
| skill_ratings | jsonb | no | `{}` | tag -> 1..5 |
| focus_next | text | yes | — | |
| visibility | string | no | `internal` | Ecto enum `internal | shared` |
| shared_at | utc_datetime_usec | yes | — | |
| edited_at | utc_datetime_usec | yes | — | |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### feedback_skill_tags

- **Owner:** wp-15. **Tenancy:** tenant-owned (RLS). Tenant-configurable; seed
  list: first touch, passing, shooting, 1v1 defending, positioning, work rate,
  communication.
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`. **Indexes:** `unique(tenant_id, name)`
  (inferred).
- **AMBIGUITY:** exact columns not enumerated.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| name | string | no | — | inferred |
| position | integer | no | `0` | inferred |
| active | boolean | no | `true` | inferred |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

### feedback_revisions (optional)

- **Owner:** wp-15. **Tenancy:** tenant-owned (RLS).
- **AMBIGUITY:** the brief says edits are versioned "in `booking_events`-style
  history **or** a `feedback_revisions` table". Whether this table exists is not
  decided. If implemented, it is a tenant-owned append-only history of
  `session_feedback` edits.

---

## Broadcasts (wp-17)

### broadcasts

- **Owner:** wp-17. **Tenancy:** tenant-owned (RLS).
- **PK:** `id`. **FK:** `tenant_id -> tenants(id)`; `created_by` is an actor
  reference (shape not specified). **Indexes:** `index(tenant_id)`,
  `index(tenant_id, status)`.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | UUIDv7 | PK |
| tenant_id | uuid | no | — | FK tenants |
| subject | string | no | — | |
| body_markdown | text | no | — | safe markdown subset |
| category | string | no | — | Ecto enum `operational | marketing` |
| segment | jsonb | no | — | embedded segment definition |
| status | string | no | `draft` | Ecto enum `draft | scheduled | sending | sent | cancelled` |
| scheduled_for | utc_datetime_usec | yes | — | |
| sent_at | utc_datetime_usec | yes | — | |
| created_by | ? | no | — | AMBIGUITY: shape not specified |
| recipient_count | integer | yes | — | |
| stats | jsonb | no | `{}` | delivered/bounced counts |
| inserted_at | utc_datetime_usec | no | now | |
| updated_at | utc_datetime_usec | no | now | |

Broadcast sends reuse `messages` / `deliveries` (wp-05) with idempotency per
`(broadcast_id, recipient)`; no separate recipient table is specified.

---

## Privacy & ops (wp-19 / wp-20)

Neither brief specifies tables.

- wp-19 (`App.Privacy`) implements household export (JSON + waiver PDFs) and
  account deletion/anonymisation using existing tables. If it adds a
  `privacy_requests`-style table, that is a new schema requiring its own brief
  entry.
- wp-20 owns infrastructure, not application schema.

---

## Cross-context references and the no-FK rule

Architecture rule: a context only reads/writes its own tables. **Cross-context
foreign keys are not created without an RFC** (`00-shared-context.md`, and
`docs/conventions.md`). By default a cross-context reference is therefore a plain
`uuid` column without a database `REFERENCES` constraint, and the referencing
context must obtain data through the owning context's public API or via domain
events.

The `tenant_id -> tenants(id)` FK is the one universal exception: every
tenant-owned table references `tenants`. `tenants` is platform-level and created
first.

### Within-context FKs (normal `REFERENCES`)

- Tenancy/Staff: `memberships.staff_user_id -> staff_users`, `memberships.tenant_id`.
- Customers: `household_members.household_id/customer_user_id`, `household_invites.household_id/invited_by`.
- Catalog: `package_offerings.package_id/offering_id`, discount target join, `discount_redemptions.discount_id`.
- Payments: `refunds.payment_id`.
- Notifications: `deliveries.message_id`.
- Players: `player_profiles/emergency_contacts/authorized_pickups/medical_info.player_id`.
- Waivers: `waiver_template_offerings.waiver_template_id`, `waiver_versions.waiver_template_id`, `waiver_signatures.waiver_version_id`.
- Inventory: `product_variants.product_id`, `stock_levels.variant_id`, `stock_movements.variant_id`.
- Policies: `offering_policy_assignments.cancellation_policy_id`.
- Scheduling: `session_coaches.session_id`, `sessions.series_id`.
- Credits: `credit_ledger_entries.credit_lot_id`, `reverses_entry_id` (self).
- Commerce: `cart_lines.cart_id`, `order_lines.order_id`.
- Bookings: `booking_events.booking_id`, `rebooked_from_id`/`rebooked_to_id` (self).
- Core: `tenant_domains.tenant_id`, `audit_events.tenant_id`.

### Cross-context references (uuid only by default — no FK without an RFC)

| Column | Referencing context | Target context |
|---|---|---|
| `memberships.staff_user_id` (`staff_users`) | Staff | global staff identity |
| `players.household_id` | Players | Customers |
| `waiver_signatures.player_id` | Waivers | Players |
| `waiver_signatures.customer_user_id` | Waivers | Customers |
| `waiver_template_offerings.offering_id` | Waivers | Catalog |
| `package_offerings.offering_id` (local package) | Catalog | Catalog (same) |
| `discount_redemptions.household_id` / `order_id` | Catalog | Customers / Commerce |
| `payments.order_id` | Payments | Commerce |
| `session_coaches.membership_id` | Scheduling | Staff |
| `sessions.offering_id` / `venue_id` | Scheduling | Catalog |
| `offering_policy_assignments.offering_id` | Policies | Catalog |
| `credit_lots.household_id` / `package_id` / `order_line_id` / `eligible_offering_ids` | Credits | Customers / Catalog / Commerce |
| `credit_ledger_entries.household_id` / `booking_id` | Credits | Customers / Bookings |
| `carts.household_id` | Commerce | Customers |
| `orders.household_id` / `discount_id` | Commerce | Customers / Catalog |
| `bookings.session_id` / `player_id` / `household_id` / `order_line_id` | Bookings | Scheduling / Players / Customers / Commerce |
| `stock_levels.venue_id` | Inventory | Catalog |
| `stock_movements.order_id` | Inventory | Commerce |
| `fulfillments.order_line_id` / `pickup_venue_id` / `picked_up_by` | Inventory | Commerce / Catalog / Staff |
| `session_feedback.session_id` / `player_id` / `coach_membership_id` | Feedback | Scheduling / Players / Staff |

The polymorphic columns (`cart_lines.ref_id`, `order_lines.ref_id`, `discount`
target `target_id`) cannot carry a single FK by design.

---

## Ambiguities

Explicit gaps in the briefs. Resolve by RFC or by the owning WP before relying on
a column.

1. **`tenants.currency_locked`.** wp-01 says to "expose `currency_locked` flag"
   and references `Commerce.any_paid_orders?/0`. Whether this is a persisted
   column (`currency_locked_at`?) or derived at read time is not stated.
2. **`platform_fee_bps` location.** Pending decision #1 says "per tenant", but
   wp-04 places it on `provider_accounts`. The ERD follows wp-04.
3. **Staff and household invite tables.** wp-01/wp-02 describe invite flows
   (email + role/relationship, 7-day single-use token) but do not name the
   tables. `staff_invites` and `household_invites` are inferred names; the
   alternative is a pending-status row in `memberships` / `household_members`.
4. **Token table columns.** `phx.gen.auth` token schemas depend on generation
   flags (`--binary-id`). Column names follow the generated modules; the ERD
   shows the typical shape.
5. **`households` columns.** wp-02 never enumerates household fields beyond the
   tenant scope and members.
6. **`customer_users` deactivation.** "Deactivate customer (blocks login)" — the
   implementing column (`active`, `status`, `deactivated_at`) is not specified.
7. **`venues` address fields.** "address fields" is not enumerated.
8. **`taxable` defaults.** Offerings, packages, and products all have a `taxable`
   flag; no default is stated for any of them.
9. **`packages.position`.** Reordering packages is mentioned, but `position` is
   only listed for offerings and products.
10. **`discounts.value` units.** For `kind = percent` the encoding (basis points
    vs whole percent) is not stated; for `kind = fixed` it is presumably minor
    units. `Catalog.Pricing` rounding is specified (per line, half-up) but not the
    value encoding.
11. **Discount target join table.** "optional target IDs (join table)" — table
    name and shape (polymorphic vs one join per target type) are unspecified.
12. **`discount_redemptions` uniqueness.** `record_redemption/3` should be
    callable repeatedly from event replays; whether it is protected by a unique
    constraint (e.g. `(discount_id, order_id)`) is not stated.
13. **`tax_rates` one-active-rate.** "MVP: one active rate" — whether enforced by
    a partial unique index is not stated.
14. **`notification_preferences` subject.** "per customer user / staff user" —
    polymorphic vs two nullable FKs is unspecified.
15. **`player_profiles.interests`.** "array/tags" — array vs tag model
    unspecified.
16. **`player_position_options` columns.** Only the seed values are given.
17. **`no_pickup_restrictions`.** Allowed explicitly, but its hosting table
    (`players`?) is not stated.
18. **`session_series` columns.** Recurrence definition described in prose only.
19. **`bookings.free_change_until`.** wp-14 says a `free_change_until` flag is
    set on affected bookings; the column is inferred from the prose (it is not in
    the listed schema fields).
20. **Actor columns.** `refunds.actor`, `stock_movements.actor`,
    `credit_ledger_entries.actor`, `booking_events.actor`, `broadcasts.created_by`,
    and `orders.placed_by` / `bookings.booked_by` are described as "actor" without
    a shape. The `Core.Audit` pattern (`actor_type` string + `actor_id` uuid) is
    the natural precedent but is not mandated for these tables.
21. **`orders.payment_method`.** Offline orders are "marked paid with
    `payment_method: offline`", implying a column not in the listed schema.
22. **`feedback_revisions`.** Explicitly optional ("or a `booking_events`-style
    history").
23. **`oban_*` columns.** Owned by the installed Oban version; enumerate from
    `Oban.Migrations` rather than this document.
24. **One-household-per-user.** Enforced "in MVP"; the exact constraint (unique
    on `customer_user_id`, scoped by tenant) is inferred.
