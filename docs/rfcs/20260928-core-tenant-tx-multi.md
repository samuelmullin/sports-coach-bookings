# RFC 20260928 — Core `Repo.with_tenant_tx/1` `Ecto.Multi` clause is unusable

**Owner affected:** wp-00 (`SportsCoachBookings.Repo`), consumers: every context.
**Status:** stubbed around by wp-03.

## Problem

`SportsCoachBookings.Repo.with_tenant_tx/2` has two clauses. The `Ecto.Multi`
clause prepends a `Multi.run(:__set_tenant__, fn _repo, _changes -> set_tenant_guc(...) end)`
step. `Repo.set_tenant_guc/1` returns `:ok`, but `Ecto.Multi.run/3` callbacks
must return `{:ok, value} | {:error, value}`. Any call to
`Repo.with_tenant_tx(%Ecto.Multi{})` therefore raises:

```
** (RuntimeError) expected Ecto.Multi callback named `:__set_tenant__` to return
either {:ok, value} or {:error, value}, got: :ok
```

The function clause works; only the `Ecto.Multi` clause is affected.

## Requested fix (wp-00)

Wrap the result:

```elixir
|> Ecto.Multi.run(:__set_tenant__, fn _repo, _changes ->
  set_tenant_guc(TenantContext.get_tenant_id())
  {:ok, nil}
end)
```

## wp-03 workaround

`SportsCoachBookings.Catalog.run_multi/2` does not pass a `Multi` to
`with_tenant_tx/1`. It runs `Repo.with_tenant_tx(fn -> Repo.transaction(multi) end)`
and unwraps the nested result. This is correct but redundant, and should be
simplified once the core clause is fixed. `Repo.transaction/2` calls without a
tenant GUC remain unsafe (see `docs/conventions.md` §1.2).
