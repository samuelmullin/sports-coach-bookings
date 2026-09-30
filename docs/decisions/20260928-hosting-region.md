# Decision 2026-09-28 — Hosting region: Canadian (Fly.io `yyz`)

Status: accepted · Owner: wp-20

## Context

Pending decision #7 in `00-shared-context.md` requires **Canadian hosting** because
the product stores data about minors (players) and their medical information
(field-level encrypted). This is a product/privacy constraint, not just a
performance one: the compute, the primary database, and the object-storage bucket
must all stay in Canada so that (a) player data does not leave Canadian
jurisdiction, and (b) we can answer data-residency questions from tenants.

## Decision

Host on **Fly.io with `primary_region = "yyz"` (Toronto, Canada)**:

| Component | Choice | Region |
|---|---|---|
| App compute | Fly Machines (`shared-cpu-1x`) | `yyz` |
| Postgres | Fly Managed Postgres (PITR, encrypted at rest) | `yyz` |
| Object storage | S3-compatible bucket (Fly Tigris / AWS S3) | `ca-central-1` / `yyz` |
| Secrets | Fly secrets (per app/environment) | n/a |
| Logs | Fly log drain → structured JSON (`docs/ops.md`) | n/a |

`ca-central-1` is AWS's Montreal region; `yyz` is Toronto. Both are Canadian and
either satisfies the requirement. We standardise on `yyz` for app + DB because
Fly's managed Postgres and Machines co-locate there, which keeps latency low,
while the S3 bucket uses `ca-central-1` (or a `yyz`-local Tigris bucket) because
object storage is region-pinned at bucket creation and cannot be changed later.

## Consequences

- Staging and production both run in `yyz`; see `fly.toml` / `fly.staging.toml`.
- A failover region is deliberately **not** configured: cross-region replication
  out of Canada would violate the residency requirement. Recovery is
  restore-from-backup in `yyz` (see `docs/ops.md`).
- DNS/TLS wildcard (`*.sportscoachbookings.com`) and the Resend sending domain
  are independent of compute region and can be provisioned anywhere.

## Alternatives considered

- **AWS `ca-central-1` (ECS/EKS + RDS + S3)** — maximum control and the strongest
  enterprise compliance story, but substantially more infrastructure to run
  (VPC, IAM, ALB, ECR, ECS) for a small team. Revisit if we need VPC peering or
  more granular IAM.
- **Render / Railway Canadian regions** — simpler, but neither offers a complete
  Canadian region across app + managed Postgres + object storage with the same
  operational model. Fly covers all three.
- **US regions (`iad`, `sea`)** — rejected: violates the minors-data requirement.
