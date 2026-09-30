# RFC 20260928 — Legal documents & document viewing (portal)

**Owner:** portal legal-documents work. **Status:** implemented.

## Context

The portal must show the tenant's Terms of Service and Privacy Policy (and, soon,
other kinds) as documents in a modal with Print and “email me a copy”, plus the
same actions for waiver bodies. Registration already records `terms_version` /
`privacy_version` on `CustomerUser`, and waivers already have versioned
`body_markdown`. This RFC records the decisions that are not obvious from the
brief.

## Decisions

1. **One tenant-owned `legal_documents` table for every kind.** `kind` is a free
   string (`terms` | `privacy`, extensible) rather than an enum, so a new kind is
   a data change, not a migration. A partial unique index enforces at most one
   `active` row per `(tenant, kind)`; a second unique index enforces unique
   `(tenant, kind, version)`. `publish_document/2` increments `version` and
   flips the previous active row to inactive in one transaction, so readers never
   see zero or two active rows.

2. **Superseding model, not waivers’ draft/publish model.** Legal documents are
   always “live” once published; there is no draft/sign flow and no content-hash
   immutability. Publishing simply supersedes. This keeps the staff API to
   list + publish, which is all the brief needs.

3. **`tenant.created` seeding.** A `Legal.TenantCreatedSubscriber` seeds the
   default Terms and Privacy for every new tenant, idempotently, mirroring
   `Policies.TenantCreatedSubscriber`. The `demo` tenant is seeded via
   `priv/repo/seeds.exs` because seeds insert it directly rather than through
   `Tenancy.create_tenant/1`. Because `tenant.created` now has two subscribers,
   the policies test asserts membership rather than exact equality.

4. **Portal reads are public.** Anonymous customers must read the documents they
   are asked to accept during registration, so `GET /api/portal/documents` and
   `GET /api/portal/documents/:kind` take no actor. Email-a-copy validates the
   supplied address and works anonymously; it is rate-limited per IP + tenant +
   email.

5. **One `legal_document` notification template, reused for waivers.** Both
   document copies and waiver copies are “here is a titled markdown body”, so
   they share `Notifications.Templates.LegalDocument`. Assigns carry both a
   plain-text `body` (markdown stripped) and `body_html` (rendered by the
   broadcasts markdown renderer). Waiver copies email the *version body* only;
   the signed-PDF snapshot remains stubbed (see
   `docs/rfcs/20260928-waivers-pdf-stub.md`).

6. **Print is a print-only region + `window.print()`.** The modal portals
   `#document-print-region` to `document.body`; a `@media print` rule hides the
   rest of the app and shows the region. This avoids pop-up blockers and keeps
   the printed output to just the document.

## Consequences

- `docs/erd.md` is intentionally untouched (owned elsewhere); this RFC is the
  record of the added table.
- A future “cookies” or “acceptable use” document is just a new `kind`.
- Effective-dating and per-version acceptance tracking are out of scope; the
  registration consent already stores the accepted `*_version` strings, which
  do not yet map to `legal_documents.version` (both are date-like today).
