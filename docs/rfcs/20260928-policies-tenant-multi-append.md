# RFC 20260928 — `with_tenant_tx/1` `Ecto.Multi` clause calls `append/2` with a list

**Owner affected:** wp-00 (`SportsCoachBookings.Repo`), consumers: every context.
**Status:** discovered by wp-10; worked around in `SportsCoachBookings.Policies`.

## Problem

`SportsCoachBookings.Repo.with_tenant_tx/2`'s `Ecto.Multi` clause builds the
GUC step and then appends it to the caller's Multi:

```elixir
set_tenant
|> Ecto.Multi.append(Ecto.Multi.to_list(multi))
|> transaction(opts)
```

On Ecto 3.14, `Ecto.Multi.append/2` takes **two `Ecto.Multi` structs**, not a
list of operations (`Ecto.Multi.append(lhs, rhs)` calls
`merge_structs/3`, which has no clause for a list). Every call therefore raises:

```
** (FunctionClauseError) no function clause matching in Ecto.Multi.merge_structs/3
```

This supersedes the ordering bug in
`docs/rfcs/20260928-waivers-tenant-multi-ordering.md`: the ordering was fixed,
but the fix used the wrong `Ecto.Multi` API.

## Requested fix (wp-00)

Prepend the GUC Multi (not a list) so it runs before the caller's operations:

```elixir
set_tenant =
  Ecto.Multi.run(Ecto.Multi.new(), :__set_tenant__, fn _repo, _changes ->
    set_tenant_guc(TenantContext.get_tenant_id())
    {:ok, :ok}
  end)

multi |> Ecto.Multi.prepend(set_tenant) |> transaction(opts)
```

## wp-10 workaround

`SportsCoachBookings.Policies.run_multi/2` does not use the `with_tenant_tx/1`
Multi clause. It prepends the GUC step itself and runs a single
`Repo.transaction(multi)`, which both sets the GUC before the writes and
preserves failed-step reasons. Simplify once the core clause is fixed.
