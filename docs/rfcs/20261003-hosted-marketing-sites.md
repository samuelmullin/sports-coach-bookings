# RFC 20261003 — Hosted marketing sites

**Owner:** Websites context.  
**Status:** implemented (custom-domain commissioning remains operational).

## Decision

Each tenant gets one opinionated marketing site inside the existing customer
portal. It is a structured content editor, not a free-form page builder. The
site shares the tenant's branding, catalog, schedule, packages, shop, customer
accounts, and checkout, so operators never maintain a second product database.

The editable surface covers the pages needed by the first customer: home,
programs, schedule, about, coaches, testimonials, gallery, sponsors, FAQ, and
contact. Content includes announcement and hero copy, story, statistics,
features, staff biographies, testimonials, gallery images, sponsors, contact
details, footer copy, and SEO metadata. Image uploads use the existing tenant
storage boundary.

Draft and published content are stored separately. Saving cannot change the
public site; publishing atomically snapshots the complete draft. Disabling the
site removes published content from the public API, disallows crawlers, and
removes its sitemap. Public links are limited in the UI to internal paths and
HTTP(S) destinations.

## Contact intake

The public contact form is rate limited, length validated, and writes a
tenant-scoped submission. Owners and admins receive the existing transactional
notification and work the submission through new, read, and resolved states in
the website inbox. User-provided HTML is escaped in email output and subjects
cannot contain header line breaks.

## Domains and launch

The wildcard tenant subdomain works without per-customer setup. A custom domain
uses the existing `tenant_domains` host lookup but is manually commissioned for
MVP: verify ownership, provision the platform certificate, add the exact host
mapping, verify both public and admin hosts, then switch DNS. Automated DNS and
certificate lifecycle management is deliberately deferred until demand
justifies it. The operational procedure is in `docs/ops.md`.

## Deliberate limits

- No arbitrary HTML, custom JavaScript, theme marketplace, or drag-and-drop
  layout editor.
- No separate Shopify product synchronization. Commerce is native to this
  product; migration imports or recreates active products and packages once.
- Search metadata is client-managed in the SPA. Server rendering and structured
  data are a later SEO enhancement if traffic warrants it.
- Custom domains are support-managed rather than self-service.

## Events

- `website.published`
- `website.contact_submitted`

Both are transactional, contain identifiers plus `tenant_id`, and never embed
content or contact messages in job arguments.
