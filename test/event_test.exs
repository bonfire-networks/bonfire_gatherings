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
end
