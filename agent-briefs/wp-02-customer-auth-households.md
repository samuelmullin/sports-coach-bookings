# WP-02 — Customer Accounts & Households

**Phase:** 1 · **Hard deps:** wp-00 · **Soft deps:** wp-05

## Goal
Customers register per tenant, get a household, and can invite other adults to co-manage it.

## You own
`App.Customers`, controllers under `portal/account/` and `staff/customers/`. Migrations prefixed `customers_`.

## Scope

### Customer identity (per tenant)
- `phx.gen.auth` into `App.Customers` (`CustomerUser`, tokens), **tenant-scoped**: unique index on `(tenant_id, lower(email))` (use `citext`). Same email may exist at other tenants as a separate account.
- Registration fields: first/last name, email, phone (E.164), password, accept terms + privacy (store version + timestamp).
- Email confirmation required before purchase/booking (login allowed). Password reset. Host-only session cookie.
- Rate limiting is added in wp-19; leave a plug hook point.

### Households
- On registration, create `household` and `household_member` (`role: primary`).
- `household_members`: `customer_user_id`, `household_id`, `role` (`primary|manager`), `relationship` (free text, e.g. "parent").
- One household per customer user (MVP). All managers have equal access to players, bookings, purchases. Only `primary` can remove other managers or transfer primary.
- Invite another adult: email + relationship → token (7 days). Invitee registers (or logs in, if they already have an account at this tenant with no other household members) and joins. Publish `household.member_invited`, `household.member_joined`.
- A manager can leave; primary cannot leave without transferring.

### Admin (owner/admin) endpoints
- Search/list customers & households (name, email, phone, player name via wp-06 join function once available).
- View household detail (members; players/bookings/orders are composed by the frontend from other endpoints).
- Edit customer contact details, trigger password reset email, deactivate customer (blocks login; data retained). Audited.

### Account self-service
- Update profile, change email (re-confirm), change password, notification preferences (delegates to wp-05 `Preferences`).

## Contracts you publish
- `App.Customers.get_household!/1`, `household_for_user/1`, `list_manager_emails(household_id)` (used by notifications), `CustomerActor` construction plug.
- Events above.

## Acceptance criteria
- Same email registers at tenants A and B → two independent accounts; login on A's host can't reach B's.
- Invite flow works for new and existing users; removed manager loses access immediately.
- Unconfirmed customer can log in but gets `403 email_unconfirmed` from a stub "purchase" guard (`App.Customers.require_confirmed/1` exported for wp-13/wp-14).
- Isolation + policy tests.

## Out of scope
Players (wp-06), UI (fe-02), social login.
