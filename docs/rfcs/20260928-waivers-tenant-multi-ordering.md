# RFC 20260928 — `with_tenant_tx/1` `Ecto.Multi` clause sets the GUC too late

**Owner affected:** wp-00 (`SportsCoachBookings.Repo`), consumers: every context.
**Status:** discovered by wp-07; worked around in `SportsCoachBookings.Waivers`.

## Problem

`SportsCoachBookings.Repo.with_tenant_tx/2`'s `Ecto.Multi` clause prepends its
tenant-GUC step with `Ecto.Multi.run/3`:

```elixir
multi
|> Ecto.Multi.run(:__set_tenant__, fn _repo, _changes ->
  set_tenant_guc(TenantContext.get_tenant_id())
  {:ok, :ok}
end)
|> transaction(opts)
```

`Ecto.Multi.run/3` **appends** the step, so `:__set_tenant__` runs *after* the
caller's operations. The tenant GUC is therefore not set while the writes run and
Postgres RLS rejects them (`new row violates row-level security policy`) whenever
the caller did not already have the GUC set for the transaction.

This supersedes the diagnosis in
`docs/rfcs/20260928-core-tenant-tx-multi.md` (which described a stale
`:ok` vs `{:ok, _}` return; the current code already returns `{:ok, :ok}`). The
remaining bug is ordering.

The wp-03/wp-06 workaround of running
`Repo.with_tenant_tx(fn -> Repo.transaction(multi) end)` is *not* sufficient
either: the double transaction nesting makes a failed Multi step surface as
`{:error, :rollback}`, losing the failed step's reason
(see `Ecto.Repo.Transaction.transact/4`'s "nested transaction has rolled back and
its error is not bubbled up" case).

## Requested fix (wp-00)

Prepend, don't append:

```elixir
set_tenant =
  Ecto.Multi.run(Ecto.Multi.new(), :__set_tenant__, fn _repo, _changes ->
    set_tenant_guc(TenantContext.get_tenant_id())
    {:ok, :ok}
  end)

multi |> Ecto.Multi.prepend(set_tenant) |> transaction(opts)
```

## wp-07 workaround

`SportsCoachBookings.Waivers.run_multi/2` does not use
`with_tenant_tx/1`'s Multi clause. It prepends the GUC step itself and runs
`Repo.transaction(multi)` once, which both sets the GUC before the writes and
preserves the failed step's reason. Simplify once the core clause is fixed.

Function-form `with_tenant_tx/1` is unaffected and remains the preferred entry
point for non-Multi writes.
