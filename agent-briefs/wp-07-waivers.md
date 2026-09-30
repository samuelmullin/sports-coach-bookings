# WP-07 — Waivers & Releases

**Phase:** 1 (feeds critical path) · **Hard deps:** wp-00 · **Soft deps:** wp-03 (offerings), wp-06 (players)

## Goal
Owners publish versioned waivers; household managers sign them per player; bookings are blocked until required waivers are signed.

## You own
`App.Waivers`, controllers `staff/waivers/`, `portal/waivers/`. Migrations prefixed `waivers_`.

## Schemas
- **waiver_templates**: name, `scope` (`all_bookings|offerings`), `require_resign_on_new_version` (bool), `active`.
- **waiver_template_offerings**: join for `scope = offerings`.
- **waiver_versions**: template, `version` (int), `body_markdown`, `status` (`draft|published|superseded`), `published_at`, `content_sha256`. Published versions are immutable.
- **waiver_signatures**: version, player, signer (`customer_user_id`), `signer_name_typed`, `signer_relationship`, `consent_checkbox` true, `signed_at`, `ip`, `user_agent`, `content_sha256` (must match the version's), `pdf_key` (async).

## Behaviour
- Publishing a new version supersedes the previous one. If `require_resign_on_new_version`, players who signed old versions become "missing" and `waiver.published` is emitted so wp-16 can email affected households (households with upcoming bookings first).
- Signing is per player (a manager signs on behalf of a minor; an adult player signs for themselves).
- PDF snapshot: Oban job renders the exact signed content + signature block → PDF (ChromicPDF or equivalent) → S3. Downloadable by the household and staff.

## Public API
- `Waivers.missing_for(player_id, offering_id) :: [%{template_id, version_id, name}]` (stubbed in wp-00 — implement it). This is the booking gate used by wp-14; keep it to ≤ 2 queries.
- `Waivers.status_for_household(household_id)` → per-player matrix of templates × status.
- Events: `waiver.published`, `waiver.signed`.

## Endpoints
- Staff: CRUD templates, draft/publish versions, preview, list signatures (filter by template/player), download PDF, export CSV.
- Portal: list required + signed waivers per player, fetch version body, sign, download own PDFs.

## Acceptance criteria
- `missing_for` correct for: no waivers, all-bookings waiver, offering-scoped waiver, new version with and without re-sign required.
- Signature rejected if `content_sha256` from client doesn't match the current published version (prevents signing stale text).
- Published version bodies cannot be edited (changeset + DB trigger or check).
- Isolation + policy tests.

## Out of scope
Drawn/handwritten signatures, e-signature provider integrations, UI (fe-01/fe-02).
