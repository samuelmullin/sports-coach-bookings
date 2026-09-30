defmodule SportsCoachBookings.LegalTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Legal
  alias SportsCoachBookings.Legal.LegalDocument

  setup do
    tenant = insert(:tenant)
    put_tenant(tenant)
    %{tenant: tenant}
  end

  describe "publish_document/2" do
    test "creates version 1, marks it active, and audits it", %{tenant: tenant} do
      assert {:ok, %LegalDocument{} = document} =
               Legal.publish_document(nil, %{
                 "kind" => "terms",
                 "title" => "Terms of Service",
                 "body_markdown" => "# Terms"
               })

      assert document.kind == "terms"
      assert document.version == 1
      assert document.active

      assert Repo.exists?(
               from e in Audit.Event,
                 where:
                   e.action == "legal.document.published" and e.resource_id == ^document.id and
                     e.tenant_id == ^tenant.id
             )
    end

    test "auto-numbers versions and supersedes the previous active version" do
      {:ok, v1} =
        Legal.publish_document(nil, %{"kind" => "terms", "title" => "A", "body_markdown" => "A"})

      {:ok, v2} =
        Legal.publish_document(nil, %{"kind" => "terms", "title" => "B", "body_markdown" => "B"})

      assert {v1.version, v2.version} == {1, 2}
      refute Repo.get!(LegalDocument, v1.id).active
      assert Repo.get!(LegalDocument, v2.id).active

      assert {:ok, active} = Legal.active_document("terms")
      assert active.id == v2.id
    end

    test "keeps kinds independent" do
      {:ok, terms} =
        Legal.publish_document(nil, %{"kind" => "terms", "title" => "T", "body_markdown" => "T"})

      {:ok, privacy} =
        Legal.publish_document(nil, %{"kind" => "privacy", "title" => "P", "body_markdown" => "P"})

      assert terms.active
      assert privacy.active
      assert {:ok, active_terms} = Legal.active_document(:terms)
      assert active_terms.id == terms.id
      assert {:ok, active_privacy} = Legal.active_document("privacy")
      assert active_privacy.id == privacy.id
    end

    test "enforces at most one active row per (tenant, kind)" do
      {:ok, _active} =
        Legal.publish_document(nil, %{"kind" => "terms", "title" => "A", "body_markdown" => "A"})

      attrs = %{
        tenant_id: TenantContext.get_tenant_id(),
        kind: "terms",
        title: "Forced",
        body_markdown: "B",
        version: 99,
        active: true
      }

      assert {:error, %Ecto.Changeset{}} =
               %LegalDocument{} |> LegalDocument.changeset(attrs) |> Repo.insert()
    end
  end

  describe "reads" do
    test "get_document/2 fetches a specific version" do
      {:ok, v1} =
        Legal.publish_document(nil, %{"kind" => "terms", "title" => "A", "body_markdown" => "A"})

      {:ok, _v2} =
        Legal.publish_document(nil, %{"kind" => "terms", "title" => "B", "body_markdown" => "B"})

      assert {:ok, %{id: id}} = Legal.get_document("terms", 1)
      assert id == v1.id
      assert {:error, :not_found} = Legal.get_document("terms", 42)
    end

    test "list_documents/1 returns every version newest first" do
      {:ok, _v1} =
        Legal.publish_document(nil, %{"kind" => "terms", "title" => "A", "body_markdown" => "A"})

      {:ok, _v2} =
        Legal.publish_document(nil, %{"kind" => "terms", "title" => "B", "body_markdown" => "B"})

      assert Enum.map(Legal.list_documents("terms"), & &1.version) == [2, 1]
      assert Enum.map(Legal.list_documents(), & &1.version) == [2, 1]
    end
  end

  describe "seed_defaults/0" do
    test "creates terms and privacy once and is idempotent" do
      assert :ok = Legal.seed_defaults()
      assert :ok = Legal.seed_defaults()

      assert length(Legal.list_documents("terms")) == 1
      assert length(Legal.list_documents("privacy")) == 1
      assert {:ok, %{title: "Terms of Service"}} = Legal.active_document("terms")
      assert {:ok, %{title: "Privacy Policy"}} = Legal.active_document("privacy")
    end
  end

  describe "render_assigns/2" do
    test "produces plain text and rendered HTML" do
      assigns = Legal.render_assigns("Terms", "# Heading\n\nSome **bold** text.")

      assert assigns.title == "Terms"
      assert assigns.body =~ "Heading"
      assert assigns.body =~ "bold"
      refute assigns.body =~ "#"
      assert assigns.body_html =~ "<h1>Heading</h1>"
      assert assigns.body_html =~ "<strong>bold</strong>"
    end
  end

  test "tenant isolation" do
    assert_tenant_isolated(LegalDocument, :legal_document)
  end
end
