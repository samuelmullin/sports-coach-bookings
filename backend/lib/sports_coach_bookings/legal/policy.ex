defmodule SportsCoachBookings.Legal.Policy do
  @moduledoc """
  Authorization for legal documents.

  | Actor | Staff list/get | Staff publish | Portal view |
  |---|---|---|---|
  | Owner / admin | Yes | Yes | Yes |
  | Coach | Yes | No | Yes |
  | Customer / anonymous | No | No | Yes |

  The portal endpoints (`GET /api/portal/documents...`) are public and do not go
  through this policy; it guards the staff publishing API only.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Legal.LegalDocument

  @manager_actions [:list, :get, :publish]
  @read_actions [:list, :get]

  def authorize(%StaffActor{role: role}, action, resource)
      when role in [:owner, :admin] and action in @manager_actions and
             resource in [:legal_document],
      do: :ok

  def authorize(
        %StaffActor{role: role, tenant_id: tenant_id},
        action,
        %LegalDocument{tenant_id: tenant_id}
      )
      when role in [:owner, :admin] and action in @manager_actions,
      do: :ok

  def authorize(%StaffActor{role: :coach}, action, resource)
      when action in @read_actions and resource in [:legal_document],
      do: :ok

  def authorize(%StaffActor{role: :coach, tenant_id: tenant_id}, action, %LegalDocument{
        tenant_id: tenant_id
      })
      when action in @read_actions,
      do: :ok

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "Every action the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions, do: @manager_actions
end
