defmodule SportsCoachBookings.Waivers.PdfStore do
  @moduledoc """
  Private object storage for signed-waiver PDFs.

  Unlike `SportsCoachBookings.Tenancy.Storage` (public branding assets, direct
  browser uploads), waiver PDFs contain a minor's name and the signer's IP, so
  bytes only ever move server-side: the app writes the object after rendering
  and streams it back through an authorized controller. Objects must never be
  publicly readable.

  The implementation is `Waivers.PdfStore.Local` (dev/test) or
  `Waivers.PdfStore.S3` (selected in `config/runtime.exs` when `S3_BUCKET` is
  set), overridable with `config :sports_coach_bookings, :waiver_pdf_store, Mod`.
  """

  @callback put(key :: binary(), pdf :: binary()) :: :ok | {:error, term()}
  @callback get(key :: binary()) :: {:ok, binary()} | {:error, :not_found | term()}
  @callback delete(key :: binary()) :: :ok | {:error, term()}

  @doc "The configured store module."
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :sports_coach_bookings,
      :waiver_pdf_store,
      SportsCoachBookings.Waivers.PdfStore.Local
    )
  end

  @doc "Stores `pdf` under `key`."
  @spec put(binary(), binary()) :: :ok | {:error, term()}
  def put(key, pdf), do: impl().put(key, pdf)

  @doc "Reads the object stored under `key`."
  @spec get(binary()) :: {:ok, binary()} | {:error, :not_found | term()}
  def get(key), do: impl().get(key)

  @doc "Deletes the object under `key`. Deleting a missing object succeeds."
  @spec delete(binary()) :: :ok | {:error, term()}
  def delete(key), do: impl().delete(key)
end
