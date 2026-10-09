# RFC 20260928 — Waivers: PDF/S3 stub

**Owner:** wp-07 (Waivers). **Status:** resolved 2026-09-30 — see *Resolution* below (was a temporary
stub).

## Context

WP-07 must produce a PDF snapshot of the exact signed waiver text plus the
signature block, store it in S3-compatible object storage, and let the household
and staff download it. No S3 credentials and no PDF renderer (ChromicPDF or
equivalent) are configured in this repository.

## Decision

1. PDF generation sits behind a behaviour,
   `SportsCoachBookings.Waivers.PdfRenderer`, with
   `render(signature) :: {:ok, storage_key} | {:error, term}`.
2. The default implementation is
   `SportsCoachBookings.Waivers.PdfRenderer.Noop`. It returns the deterministic
   key `"waivers/<signature_id>.pdf"` without producing a file.
3. `SportsCoachBookings.Waivers.PdfWorker` (an Oban
   `SportsCoachBookings.Core.TenantWorker` on the `:default` queue) runs on
   signing, calls the configured renderer, and stores the returned key in
   `waiver_signatures.pdf_key`. It is idempotent.
4. A real renderer is enabled by setting
   `config :sports_coach_bookings, :waiver_pdf_renderer, MyRenderer` (runtime
   config); no code change is required.
5. `GET /api/staff/waivers/signatures/:id/pdf` and
   `GET /api/portal/waivers/signatures/:id/pdf` return JSON PDF metadata
   (`pdf_key`, `status`, `download_url`) instead of a redirect/binary.

`waiver_signatures.ip` is stored as Postgres `inet` via a small custom Ecto type,
`SportsCoachBookings.Waivers.IP` (`type/0` returns `:inet`).

## Follow-up

- Implement a real `PdfRenderer` that renders the signed body and uploads to S3,
  then make the download endpoints return a short-lived signed URL (or stream
  the object).
- Replace the JSON download response with the actual file once storage exists.

## Not changed

- No S3/PDF dependency is added to `mix.exs` in this change.
- No other context, `core/*`, or `docs/erd.md` is edited by wp-07.

## Resolution (updated 2026-10-02)

- Production uses `PdfRenderer.Browser` (ChromicPDF + the image's sandboxed
  Chromium) to render escaped HTML. It supports Unicode via bundled Noto/Lato
  fonts and applies tenant logo, colour, and font branding. Dev/test retain the
  pure-Elixir `PdfRenderer.Document` fallback so they do not require a browser;
  `Noop` remains for pipeline-only tests.
- `Waivers.PdfStore` (private, server-side only): `Local` for dev/test, `S3` when
  `S3_BUCKET` is set (optionally `S3_PRIVATE_BUCKET`). Keys are
  `<tenant_id>/waivers/<signature_id>.pdf`.
- Both download endpoints now return `application/pdf` (`attachment`,
  `private, no-store`) instead of JSON metadata, rendering on demand if the
  background job has not run. The admin UI already linked directly to the URL;
  the portal button is now a plain download link.
- Erasure (`Privacy`) anonymizes signatures and enqueues
  `Waivers.PdfCleanupWorker` to delete the stored objects.
- CI verifies presigned public uploads and private PDF put/get/delete against
  RustFS; request construction is also unit-tested with `Req.Test`. Validate
  against the production provider in staging.
