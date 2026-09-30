defmodule SportsCoachBookings.WaiversTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Waivers
  alias SportsCoachBookings.Waivers.PdfWorker
  alias SportsCoachBookings.Waivers.WaiverSignature
  alias SportsCoachBookings.Waivers.WaiverTemplate
  alias SportsCoachBookings.Waivers.WaiverVersion

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  defp published_template(scope \\ :all_bookings, attrs \\ %{}) do
    offering_ids =
      case scope do
        :offerings -> Map.get(attrs, :offering_ids) || Map.get(attrs, "offering_ids")
        _ -> nil
      end

    attrs =
      Map.merge(
        %{"name" => "Waiver", "scope" => scope, "offering_ids" => offering_ids},
        attrs
      )

    {:ok, template} = Waivers.create_template(nil, attrs)
    {:ok, draft} = Waivers.create_version(nil, template.id, %{"body_markdown" => "Body one"})
    {:ok, published} = Waivers.publish_version(nil, draft.id)
    {template, published}
  end

  describe "hash_body/1" do
    test "is a lower-case hex sha256" do
      assert Waivers.hash_body("abc") ==
               "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    end
  end

  describe "templates" do
    test "creates an all-bookings template and audits it" do
      assert {:ok, %WaiverTemplate{} = template} =
               Waivers.create_template(nil, %{"name" => "General", "scope" => "all_bookings"})

      assert template.scope == :all_bookings
      assert template.active

      assert Repo.exists?(
               from e in SportsCoachBookings.Core.Audit.Event,
                 where: e.action == "waiver.template.created" and e.resource_id == ^template.id
             )
    end

    test "links offerings for an offerings-scoped template and validates them" do
      offering = insert(:offering, tenant_id: TenantContext.get_tenant_id())

      assert {:ok, template} =
               Waivers.create_template(nil, %{
                 "name" => "Soccer release",
                 "scope" => "offerings",
                 "offering_ids" => [offering.id]
               })

      assert Waivers.template_offering_ids(template.id) == [offering.id]

      assert {:error, :not_found} =
               Waivers.create_template(nil, %{
                 "name" => "Bad",
                 "scope" => "offerings",
                 "offering_ids" => [Ecto.UUID.generate()]
               })
    end

    test "archives a template" do
      {:ok, template} = Waivers.create_template(nil, %{"name" => "T", "scope" => "all_bookings"})
      assert {:ok, archived} = Waivers.archive_template(nil, template.id)
      refute archived.active
    end
  end

  describe "versions" do
    test "auto-numbers versions and derives content_sha256" do
      {:ok, template} =
        Waivers.create_template(nil, %{"name" => "T", "scope" => "all_bookings"})

      {:ok, v1} = Waivers.create_version(nil, template.id, %{"body_markdown" => "One"})
      {:ok, v2} = Waivers.create_version(nil, template.id, %{"body_markdown" => "Two"})

      assert v1.version == 1
      assert v2.version == 2
      assert v1.content_sha256 == Waivers.hash_body("One")
      assert v2.content_sha256 == Waivers.hash_body("Two")
      assert v1.status == :draft
    end

    test "publishing supersedes the previous published version and emits an event" do
      {:ok, template} =
        Waivers.create_template(nil, %{"name" => "T", "scope" => "all_bookings"})

      {:ok, v1} = Waivers.create_version(nil, template.id, %{"body_markdown" => "One"})
      {:ok, p1} = Waivers.publish_version(nil, v1.id)
      assert p1.status == :published
      assert p1.published_at

      {:ok, v2} = Waivers.create_version(nil, template.id, %{"body_markdown" => "Two"})
      {:ok, p2} = Waivers.publish_version(nil, v2.id)

      assert p2.status == :published
      assert Repo.get!(WaiverVersion, v1.id).status == :superseded

      events = Repo.all(from j in Oban.Job, select: j.args["name"])
      assert Enum.count(events, &(&1 == "waiver.published")) == 2
    end

    test "draft versions can be edited" do
      {:ok, template} =
        Waivers.create_template(nil, %{"name" => "T", "scope" => "all_bookings"})

      {:ok, draft} = Waivers.create_version(nil, template.id, %{"body_markdown" => "One"})

      assert {:ok, updated} =
               Waivers.update_version(nil, draft.id, %{"body_markdown" => "One, revised"})

      assert updated.body_markdown == "One, revised"
      assert updated.content_sha256 == Waivers.hash_body("One, revised")
    end

    test "published version bodies cannot be edited (changeset)" do
      {_template, published} = published_template()

      assert {:error, {:immutable_version, _}} =
               Waivers.update_version(nil, published.id, %{"body_markdown" => "Tampered"})

      assert Repo.get!(WaiverVersion, published.id).body_markdown == "Body one"
    end

    test "published version bodies cannot be edited (db trigger)" do
      {_template, published} = published_template()

      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn ->
          Repo.query!(
            "UPDATE waiver_versions SET body_markdown = $1 WHERE id = $2",
            ["Tampered", Ecto.UUID.dump!(published.id)]
          )
        end)
      end

      assert Repo.get!(WaiverVersion, published.id).body_markdown == "Body one"
    end
  end

  describe "sign/5" do
    test "signs the current published version, enqueues the PDF job, and emits an event" do
      {_template, published} = published_template()
      player_id = Ecto.UUID.generate()

      attrs = sign_attrs(published.content_sha256)

      assert {:ok, %WaiverSignature{} = signature} =
               Waivers.sign(nil, player_id, published.id, attrs)

      assert signature.player_id == player_id
      assert signature.content_sha256 == published.content_sha256
      assert Waivers.IP.format(signature.ip) == "203.0.113.7"

      names = Repo.all(from j in Oban.Job, select: j.args["name"])
      assert "waiver.signed" in names

      job = Repo.one(from j in Oban.Job, where: j.args["name"] == "waiver.signed")
      assert job.args["payload"]["signature_id"] == signature.id
    end

    test "rejects a client content_sha256 that does not match the published version" do
      {_template, published} = published_template()

      attrs = sign_attrs(Waivers.hash_body("not the current text"))

      assert {:error, {:stale_waiver, _}} =
               Waivers.sign(nil, Ecto.UUID.generate(), published.id, attrs)
    end

    test "requires the consent checkbox" do
      {_template, published} = published_template()

      attrs =
        published.content_sha256
        |> sign_attrs()
        |> Map.put("consent_checkbox", false)

      assert {:error, %Ecto.Changeset{}} =
               Waivers.sign(nil, Ecto.UUID.generate(), published.id, attrs)
    end

    test "cannot sign the same version twice for the same player" do
      {_template, published} = published_template()
      player_id = Ecto.UUID.generate()

      attrs = sign_attrs(published.content_sha256)

      assert {:ok, _} = Waivers.sign(nil, player_id, published.id, attrs)
      assert {:error, :conflict} = Waivers.sign(nil, player_id, published.id, attrs)
    end
  end

  describe "missing_for/2" do
    test "returns [] when the tenant has no published waivers" do
      assert Waivers.missing_for(Ecto.UUID.generate(), Ecto.UUID.generate()) == []
    end

    test "requires an all-bookings waiver for every offering" do
      {template, published} = published_template()
      result = Waivers.missing_for(Ecto.UUID.generate(), Ecto.UUID.generate())

      assert [%{template_id: id, version_id: vid, name: "Waiver"}] = result
      assert id == template.id
      assert vid == published.id
    end

    test "requires an offerings-scoped waiver only for linked offerings" do
      offering = insert(:offering, tenant_id: TenantContext.get_tenant_id())
      other = insert(:offering, tenant_id: TenantContext.get_tenant_id())
      player_id = Ecto.UUID.generate()

      {_template, published} =
        published_template(:offerings, %{"offering_ids" => [offering.id]})

      assert [%{version_id: vid}] = Waivers.missing_for(player_id, offering.id)
      assert vid == published.id
      assert Waivers.missing_for(player_id, other.id) == []
    end

    test "a new version with re-sign required makes previously-signed players missing" do
      {:ok, template} =
        Waivers.create_template(nil, %{
          "name" => "Resign",
          "scope" => "all_bookings",
          "require_resign_on_new_version" => true
        })

      {:ok, v1} = Waivers.create_version(nil, template.id, %{"body_markdown" => "v1"})
      {:ok, p1} = Waivers.publish_version(nil, v1.id)

      player_id = Ecto.UUID.generate()
      offering_id = Ecto.UUID.generate()
      {:ok, _} = Waivers.sign(nil, player_id, p1.id, sign_attrs(p1.content_sha256))

      assert Waivers.missing_for(player_id, offering_id) == []

      {:ok, v2} = Waivers.create_version(nil, template.id, %{"body_markdown" => "v2"})
      {:ok, p2} = Waivers.publish_version(nil, v2.id)

      assert [%{version_id: vid}] = Waivers.missing_for(player_id, offering_id)
      assert vid == p2.id
    end

    test "a new version without re-sign required keeps previously-signed players signed" do
      {:ok, template} =
        Waivers.create_template(nil, %{
          "name" => "No resign",
          "scope" => "all_bookings",
          "require_resign_on_new_version" => false
        })

      {:ok, v1} = Waivers.create_version(nil, template.id, %{"body_markdown" => "v1"})
      {:ok, p1} = Waivers.publish_version(nil, v1.id)

      player_id = Ecto.UUID.generate()
      offering_id = Ecto.UUID.generate()
      {:ok, _} = Waivers.sign(nil, player_id, p1.id, sign_attrs(p1.content_sha256))

      {:ok, v2} = Waivers.create_version(nil, template.id, %{"body_markdown" => "v2"})
      {:ok, _p2} = Waivers.publish_version(nil, v2.id)

      assert Waivers.missing_for(player_id, offering_id) == []
    end
  end

  describe "status_for_household/1" do
    test "returns a per-player required/signed matrix" do
      household = Ecto.UUID.generate()
      player = insert(:player, tenant_id: TenantContext.get_tenant_id(), household_id: household)
      other = insert(:player, tenant_id: TenantContext.get_tenant_id(), household_id: household)

      {_template, published} = published_template()
      {:ok, _} = Waivers.sign(nil, player.id, published.id, sign_attrs(published.content_sha256))

      assert %{players: players} = Waivers.status_for_household(household)

      assert Enum.map(players, & &1.player_id) |> Enum.sort() ==
               Enum.sort([player.id, other.id])

      signed = Enum.find(players, &(&1.player_id == player.id))
      missing = Enum.find(players, &(&1.player_id == other.id))

      assert [%{signed: true, version_id: vid}] = signed.waivers
      assert vid == published.id
      assert [%{signed: false}] = missing.waivers

      player_id = player.id

      assert %{player_id: ^player_id, waivers: [%{signed: true}]} =
               Waivers.status_for_player(player.id)
    end
  end

  describe "export_signatures_csv/1" do
    test "exports a header and signature rows" do
      {template, published} = published_template()
      player_id = Ecto.UUID.generate()
      {:ok, _} = Waivers.sign(nil, player_id, published.id, sign_attrs(published.content_sha256))

      csv = Waivers.export_signatures_csv(%{"template_id" => template.id})
      [header | rows] = csv |> String.trim_trailing() |> String.split("\r\n")

      assert header ==
               "template,version,player_id,signer_name,signer_relationship,signed_at,content_sha256"

      assert length(rows) == 1
      assert rows |> hd() |> String.contains?(player_id)
    end
  end

  describe "PdfWorker" do
    test "renders and stores the pdf_key via the configured renderer" do
      {_template, published} = published_template()
      player_id = Ecto.UUID.generate()

      {:ok, signature} =
        Waivers.sign(nil, player_id, published.id, sign_attrs(published.content_sha256))

      job = %Oban.Job{args: %{"signature_id" => signature.id, "tenant_id" => signature.tenant_id}}
      assert :ok = PdfWorker.perform(job)

      assert Repo.get!(WaiverSignature, signature.id).pdf_key == "waivers/#{signature.id}.pdf"
    end
  end

  defp sign_attrs(sha) do
    %{
      "content_sha256" => sha,
      "customer_user_id" => Ecto.UUID.generate(),
      "signer_name_typed" => "Dana Reyes",
      "signer_relationship" => "Parent",
      "consent_checkbox" => true,
      "ip" => "203.0.113.7",
      "user_agent" => "Mozilla"
    }
  end
end
