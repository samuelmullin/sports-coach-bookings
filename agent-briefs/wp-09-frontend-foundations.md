# WP-09 — Frontend Foundations (UI kit, theming, app shells, auth screens)

**Phase:** 1 · **Hard deps:** wp-00 · **Soft deps:** wp-01, wp-02 (build against generated MSW mocks)

## Goal
Everything the feature UI agents (fe-01/02/03) need so they only build screens: component library, per-tenant theming, routing shells, API/auth plumbing, and auth screens.

## You own
`frontend/packages/ui`, `frontend/packages/api-client` (wrapper only; generated code is from wp-00's pipeline), app shells in `frontend/apps/admin` and `frontend/apps/portal` (routing, layouts, providers, auth screens).

## Deliverables

### packages/ui
- Stack: Tailwind (configured to read CSS variables), Radix UI primitives, `react-hook-form` + `zod`, `date-fns` + `date-fns-tz`.
- Components: Button, IconButton, Input, Textarea, Select, Combobox, Checkbox, Radio, Switch, DatePicker, TimePicker, FormField (label/help/error), Table (sortable, cursor-paginated), EmptyState, Modal/Drawer, Toast, Tabs, Badge, Card, Avatar, FileUpload (presigned-URL flow), MoneyInput/MoneyDisplay (minor units), ConfirmDialog, Skeleton, **Calendar** (week + month + agenda list views, timezone-aware, event slots with capacity badge).
- Accessibility: keyboard nav, focus rings, labels; axe checks in component tests.
- Storybook (or Ladle) with a theme switcher showing two tenant themes.

### Theming
- Portal fetches `GET /api/portal/branding` at boot and sets CSS variables on `:root` (`--color-primary`, etc.) plus logo/favicon/title. Loading state must not flash unbranded UI (render a neutral splash until loaded).
- Admin uses a fixed platform theme, with the tenant's logo in the header.

### API plumbing
- Fetch wrapper: base URL, credentials `include`, CSRF token header, standard error parsing into `ApiError { code, message, fields }`, 401 → redirect to login, 403 → forbidden screen.
- TanStack Query provider with sensible defaults; mutation helper that maps `fields` errors into react-hook-form.
- `VITE_USE_MOCKS=true` runs MSW handlers from `packages/mocks` so feature agents can work before the backend is ready.
- Money/time helpers: format in tenant currency and venue timezone.

### App shells
- **admin**: routes under `/admin`, layout with sidebar, role-aware navigation (owner/admin see everything; coach sees only "My sessions", "Players", "Feedback"), tenant switcher (for staff with multiple memberships → navigates to other subdomain), route guards by role.
- **portal**: public routes (home, schedule, packages, shop) + authenticated routes (account, household, players, bookings, orders); header with tenant branding; mobile-first layout.
- i18n-ready: all strings via `react-i18next` with an `en` bundle (French can be added later).

### Auth screens
- Admin: staff login, forgot/reset password, confirm email, accept invite (existing vs new user), tenant signup wizard (name, slug with availability check, timezone, currency).
- Portal: register, login, forgot/reset, confirm email, accept household invite.

## Acceptance criteria
- Both apps run fully on mocks; login → shell → role-based nav works for owner/admin/coach/customer mock users.
- Portal renders with two different mocked brandings with no unbranded flash.
- Lighthouse accessibility ≥ 95 on auth screens. Vitest + Testing Library coverage for components.

## Out of scope
Feature screens (fe-01/02/03).
