defmodule Bonfire.Gatherings.EventTest do
  @moduledoc "The native Event type: a virtual whose every field lives in a mixin."
  use Bonfire.Gatherings.DataCase, async: true

  import Bonfire.Me.Fake
  alias Bonfire.Common.Repo
  alias Bonfire.Gatherings.Event

  defp insert_event!(attrs) do
    %Event{id: Needle.UID.generate(Event)}
    |> Ecto.Changeset.change()
    |> then(fn changeset ->
      Enum.reduce(attrs, changeset, fn {key, value}, acc ->
        Ecto.Changeset.put_assoc(acc, key, value)
      end)
    end)
    |> Repo.insert!()
  end

  test "an event is stored with a name, a summary and a creator, and read back with them" do
    user = fake_user!()

    event =
      insert_event!(
        post_content: %Bonfire.Data.Social.PostContent{
          name: "Garden party",
          summary: "Bring snacks"
        },
        created: %Bonfire.Data.Social.Created{creator_id: user.id}
      )

    assert %{post_content: %{name: "Garden party", summary: "Bring snacks"}, created: created} =
             Event |> Repo.get!(event.id) |> Repo.preload([:post_content, :created])

    assert created.creator_id == user.id
  end

  test "an event whose pointer is marked deleted is hidden, and comes back with its mixins when restored" do
    user = fake_user!()

    event =
      insert_event!(
        post_content: %Bonfire.Data.Social.PostContent{name: "Garden party"},
        created: %Bonfire.Data.Social.Created{creator_id: user.id}
      )

    pointer = from(p in Needle.Pointer, where: p.id == ^event.id)

    assert %Event{} = Repo.get(Event, event.id)

    assert {1, _} = Repo.update_all(pointer, set: [deleted_at: DateTime.utc_now()])
    assert is_nil(Repo.get(Event, event.id))

    assert {1, _} = Repo.update_all(pointer, set: [deleted_at: nil])

    assert %{post_content: %{name: "Garden party"}, created: %{creator_id: creator_id}} =
             Event |> Repo.get!(event.id) |> Repo.preload([:post_content, :created])

    assert creator_id == user.id
  end

  test "an event is stored with a time span and a primary geolocation, and read back with them" do
    user = fake_user!()
    geolocation = Bonfire.Geolocate.Simulate.fake_geolocation!(user)
    begins = ~U[2027-05-01 18:00:00.000000Z]
    ends = ~U[2027-05-01 22:00:00.000000Z]

    event =
      insert_event!(
        post_content: %Bonfire.Data.Social.PostContent{name: "Garden party"},
        time_span: %Bonfire.Data.Time.TimeSpan{has_beginning: begins, has_end: ends}
      )

    assert {:ok, _} = Bonfire.Geolocate.PrimaryGeolocations.set(event, geolocation)

    assert %{time_span: time_span, primary_geolocation: %{geolocation_id: geolocation_id}} =
             Event |> Repo.get!(event.id) |> Repo.preload([:time_span, :primary_geolocation])

    assert time_span.has_beginning == begins
    assert time_span.has_end == ends
    assert geolocation_id == geolocation.id
  end

  describe "the links in extra_info" do
    @begins %{has_beginning: ~U[2027-05-01 18:00:00.000000Z]}

    defp info_change(extra_info) do
      changeset = Event.changeset(%{time_span: @begins, extra_info: extra_info})
      Ecto.Changeset.get_change(changeset, :extra_info)
    end

    test "keeps http(s) URLs, with string keys, and the other keys of info" do
      assert %{changes: %{info: info}} =
               info_change(%{
                 info: %{
                   :external_participation_url => "https://tickets.example.local/e/1",
                   "online_address" => "http://meet.example.local/room",
                   "other" => "kept"
                 }
               })

      assert info == %{
               "external_participation_url" => "https://tickets.example.local/e/1",
               "online_address" => "http://meet.example.local/room",
               "other" => "kept"
             }
    end

    test "drops what is not an http(s) URL" do
      assert %{changes: %{info: info}} =
               info_change(%{
                 info: %{
                   "external_participation_url" => "javascript:alert(1)",
                   "online_address" => "https://meet.example.local/room"
                 }
               })

      assert info == %{"online_address" => "https://meet.example.local/room"}

      # control: the same key with a valid URL alone does make the row
      assert %{changes: %{info: %{"online_address" => "https://meet.example.local/room"}}} =
               info_change(%{info: %{"online_address" => "https://meet.example.local/room"}})

      for bad <- [
            "javascript:alert(1)",
            "come to the garden",
            "ftp://files.example.local/x",
            "https://",
            "",
            nil,
            5
          ] do
        assert is_nil(info_change(%{info: %{"online_address" => bad}})),
               "no extra_info for #{inspect(bad)}"
      end
    end

    test "makes no extra_info row without any" do
      assert is_nil(info_change(nil))

      assert is_nil(
               Ecto.Changeset.get_change(Event.changeset(%{time_span: @begins}), :extra_info)
             )
    end
  end
end
