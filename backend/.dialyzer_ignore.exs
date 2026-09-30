# Dialyzer ignore file. Every entry is a justified false positive; see
# docs/security-review.md ("Static analysis").
#
# `:call_without_opaque` on the Ecto contexts is the well-known Dialyzer
# false positive where `Ecto.Multi.t/0` is opaque: the contexts thread a
# `Multi` through a private `run_multi/2` (or `multi_tx/1`) helper into
# `Repo.transaction/2`, which Dialyzer reports at the `Multi.insert/update/run`
# construction site even though the calls are correct. Runtime tests and
# `mix test` prove the pipelines work; removing the helpers is a Core change
# (see docs/rfcs/20260928-core-tenant-tx-multi.md) and is out of scope for
# wp-19. Do not add other warning types here without a code fix.
[
  {"lib/sports_coach_bookings/catalog.ex", :call_without_opaque},
  {"lib/sports_coach_bookings/customers.ex", :call_without_opaque},
  {"lib/sports_coach_bookings/inventory.ex", :call_without_opaque},
  {"lib/sports_coach_bookings/players.ex", :call_without_opaque},
  {"lib/sports_coach_bookings/policies.ex", :call_without_opaque},
  {"lib/sports_coach_bookings/repo.ex", :call_without_opaque},
  {"lib/sports_coach_bookings/waivers.ex", :call_without_opaque}
]
