# WP-01 — Tenant Signup, Settings, Branding, Staff

**Phase:** 1 · **Hard deps:** wp-00 · **Soft deps:** wp-05 (use `Notifications.deliver/…`; stub if not merged)

## Goal
A provider can sign up, create their tenant, set up branding, and invite admins and coaches.

## You own
`App.Tenancy`, `App.Staff`, controllers under `platform/` and `staff/settings/`, `staff/team/`. Migrations prefixed `tenancy_` and `staff_`.

## Scope

### Staff identity (global)
- Generate with `phx.gen.auth` into `App.Staff` (`StaffUser`, tokens). Email+password, email confirmation, password reset, session cookie scoped to `.yourapp.com`.
- `memberships`: `staff_user_id`, `tenant_id`, `role` (`owner|admin|coach`), `status` (`active|removed`), `display_name`, `bio`, `photo_key` (coach profile, shown in portal).
- `GET /api/platform/me` → user + memberships (tenant picker).
- `/api/staff/*` requests require an active membership for the resolved tenant; build `StaffActor` in a plug.

### Tenant signup
- `POST /api/platform/signup`: creates staff user (or uses the logged-in one), tenant (`name`, `slug` unique + reserved-word blocklist, `timezone`, `currency` default `CAD`, `contact_email`), owner membership, default branding. Publishes `tenant.created`.
- Slug availability endpoint.

### Tenant settings (owner/admin)
- Update name, contact email, timezone, currency (currency locked after first paid order — expose `currency_locked` flag; wp-13 provides `Commerce.any_paid_orders?/0`, stub until merged).
- Owner-only: transfer ownership, soft-delete tenant (mark deleted, block access).

### Branding
- `branding`: `logo_key`, `favicon_key`, `primary_color`, `secondary_color`, `accent_color`, `background_color`, `text_color`, `font_family` (from a fixed allowlist), `email_footer_text`, `social_links` (map).
- Upload flow: `POST /api/staff/branding/uploads` returns a presigned S3 PUT URL; client uploads; `PATCH` saves the key. Validate type (png/svg/jpg/webp) and size (≤ 2 MB). Sanitize SVGs or rasterize them.
- Validate WCAG AA contrast between `text_color`/`background_color` and between `primary_color` and white/black button text; return a warning (not an error) on failure.
- `GET /api/portal/branding` (public): theme tokens + asset URLs + tenant name. Cacheable (ETag).
- `App.Tenancy.branding_for_email(tenant_id)` for wp-05.

### Staff invites & team management
- Invite by email + role (owner/admin can invite admin or coach; only owner can invite owner). Token valid 7 days, single use. Email via Notifications template `staff_invite`.
- Accept flow: logged-in existing user → join; new user → register then join.
- List team, change role, remove member (soft). Cannot remove or demote the last owner. Coaches cannot access this area.
- Publish `staff.invited`, `staff.joined`, `staff.removed`. Audit every role change.

## Contracts you publish
- `App.Tenancy.get_tenant!/1`, `branding_for_email/1`, `tenant_settings/1`
- `App.Staff.list_coaches/0` (for scheduling pickers), `App.Staff.get_membership!/1`
- Events listed above

## Acceptance criteria
- Owner signs up, gets tenant at `{slug}.localhost`, uploads a logo, changes colors, `GET /api/portal/branding` reflects it.
- Owner invites an admin and a coach; both accept; coach gets 403 on team and settings endpoints.
- Last-owner protection tested. Staff user with memberships in two tenants can use both without re-login.
- Tenant isolation + policy matrix tests pass.

## Out of scope
UI (fe-01), custom domains, SSO.
