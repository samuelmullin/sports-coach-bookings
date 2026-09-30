defmodule SportsCoachBookingsWeb.LegalJSON do
  @moduledoc "Serialises legal documents."

  alias SportsCoachBookings.Legal.LegalDocument

  @doc "Serialises a document including its body."
  @spec document(LegalDocument.t()) :: map()
  def document(%LegalDocument{} = document) do
    %{
      id: document.id,
      kind: document.kind,
      title: document.title,
      body_markdown: document.body_markdown,
      version: document.version,
      active: document.active,
      inserted_at: datetime(document.inserted_at),
      updated_at: datetime(document.updated_at)
    }
  end

  @doc "Serialises a document without its body (list views)."
  @spec summary(LegalDocument.t()) :: map()
  def summary(%LegalDocument{} = document) do
    %{
      id: document.id,
      kind: document.kind,
      title: document.title,
      version: document.version,
      active: document.active,
      updated_at: datetime(document.updated_at)
    }
  end

  @doc "Wraps serialised rows in a `%{data: [...]}` envelope."
  @spec collection([map()]) :: map()
  def collection(data), do: %{data: data}

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
