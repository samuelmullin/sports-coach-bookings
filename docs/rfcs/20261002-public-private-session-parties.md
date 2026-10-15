# RFC 20261002 — Public/private session parties and invitations

**Owner:** Catalog, Scheduling, and Bookings contexts.  
**Status:** implemented.

## Decision

“Semi-private” and “group” remain available as marketing names, but are not
booking mechanics. Every offering instead configures two independent modes:

- **Public:** unrelated households may fill the occurrence up to the public
  maximum.
- **Private:** one household owns the occurrence and may use any configured
  party-size tier up to the private maximum. The private maximum may exceed the
  public maximum.

Each enabled mode has its own maximum players, players-per-coach ratio, and a
complete per-player money/credit tier map for sizes `1..maximum`. Legacy
`format`, `default_capacity`, `drop_in_price`, and `credit_cost` fields remain
while older clients and records migrate.

## Invitations

A customer with an active booking may invite a prior accepted partner or any
email address, without exceeding the occurrence capacity.

- **Split payment:** one seat is atomically held for `invite_hold_hours`
  (default 48). A new hold is refused once the session begins inside that
  horizon. Acceptance transfers the held counter into a paid or credit booking
  in one transaction.
- **Organizer pays:** the organizer immediately creates a credit booking or
  paid checkout hold for the guest. This remains available inside the split
  hold horizon because capacity is actually being purchased, not reserved for
  later payment.

Tokens are random and opaque; only their SHA-256 hashes are stored. Acceptance
requires an authenticated customer whose normalized email matches the invite.
Organizer-funded bookings may temporarily have no player and are assigned to
an eligible player in the invitee household on acceptance.

The invitation snapshots both email addresses so accepted partners can be
selected again whether the current household originally sent or received the
invitation.

Customers can see invitation history and status. An organizer may resend a
pending invitation, which rotates its opaque token and invalidates every older
link, or revoke it. Revoking a split invitation releases the reserved seat;
revoking an organizer-funded invitation cancels the guest booking with a full
credit return or payment refund.

## Private sessions

If enabled, a customer may convert an empty public occurrence to private and
choose any configured private party size. Capacity becomes that selected party
size, so private conversion can increase capacity up to the private maximum
without letting a smaller price tier consume more seats. Conversion is atomic,
exclusive to that household, and requires enough assigned coaches for the
chosen ratio.

If private requests are enabled, a customer may instead submit a party size,
preferred times, and notes. An owner/admin approves by assigning an empty
matching occurrence (again requiring adequate staffing) or declines it.
Customers can track pending and reviewed requests in the portal. Approval or
decline sends a transactional email to every household manager; approvals link
to the assigned occurrence and declines may include the operator's reason.

## Journey coverage

`e2e/tests/10-session-parties.spec.ts` exercises the real portal, admin SPA,
Phoenix API, Postgres, Oban, and local mailbox across two households. It covers
split acceptance, prior-partner reuse, token-rotating resend, revoke, cutoff
rules, organizer-funded seats, public-to-private capacity expansion, private
request approval, decision email, and customer-visible status.

## Staffing compatibility

Existing scheduling permits publishing occurrences before coaches are
assigned. Accordingly, public booking remains possible while an occurrence has
zero assigned coaches. As soon as at least one coach is assigned, the ratio is
a hard booking/invitation limit. Private conversion and private-request
approval always require the full ratio before the occurrence becomes private.

## Events

The transactional event catalog gains:

- `session.converted_private`
- `session.invitation_accepted`

Both payloads contain identifiers and `tenant_id`, never structs or invite
tokens.
