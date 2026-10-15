# RFC 20260928 — Tenancy branding asset storage is stubbed

**Owner:** wp-01 (Tenancy). **Status:** resolved — S3 backend implemented (`Tenancy.Storage.S3`, selected by `S3_BUCKET`); `Fake` remains the dev/test default. Presigned uploads are verified against RustFS in CI; the selected production provider still requires staging validation.

## Context

WP-01's branding upload flow is `POST /api/staff/branding/uploads` → presigned
S3 PUT → client uploads → `PATCH /api/staff/branding` saves the key. No S3
backend is configured in this environment, and there is no image toolchain to
rasterise SVGs.

## Decision

1. `SportsCoachBookings.Tenancy.Storage` is a behaviour
   (`presign_put/2`, `public_url/1`). The default implementation is
   `SportsCoachBookings.Tenancy.Storage.Fake`, selected by
   `config :sports_coach_bookings, :tenancy_storage`.
2. The fake produces a **deterministic** key (`"<tenant_id>/<sanitised
   filename>"`) and a presigned-style URL, and a public CDN-style URL. Nothing
   is uploaded or stored.
3. Type/size validation is real: PNG/JPEG/WebP/SVG, `> 0` and `<= 2 MB`. Errors
   are `:unsupported_content_type`, `:invalid_byte_size`, `:file_too_large`.
4. SVG safety is **sanitise-by-rejection**
   (`SportsCoachBookings.Tenancy.Storage.Svg`): SVGs containing `<script>`,
   event handlers, `<foreignObject>`/`<iframe>`/`<embed>`/`<object>`,
   `javascript:`, or external `xlink:href` are refused with `:unsafe_svg`.
   A production backend should rasterise instead.
5. The dev/test stub accepts optional inline `content` so the SVG sanitiser is
   exercised without a real object store.

## Production follow-up

- Validate the presigned upload and public-read policy against the selected
  production provider in staging.
- Rasterise SVGs at upload (or in an Oban job) rather than trusting rejection.

## Not changed

- No `core/*`, other contexts, or `docs/erd.md` edited.
