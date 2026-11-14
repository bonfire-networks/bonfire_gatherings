defmodule Bonfire.Gatherings.APActivityEventsMigrationTest do
  @moduledoc """
  Events stored as APActivities (before `Bonfire.Gatherings.Events` claimed the `Event` type, or while gatherings was off) become native events: the same pointer id, so their activity, tags, boundary and creator stay, with their own mixins written from the AS2 json.
  """
  use Bonfire.Gatherings.DataCase, async: false

  import Bonfire.Me.Fake
  alias Bonfire.Common.Repo
  alias Bonfire.Gatherings.Event
  alias Bonfire.Gatherings.APActivityEventsMigration, as: Conversion

  @public "https://www.w3.org/ns/activitystreams#Public"

  # an APActivity as the fallback stored it, bypassing the routing that now makes a native event
  defp apactivity!(user, object) do
    activity = %{
      "type" => "Create",
      "actor" => Bonfire.Common.URIs.canonical_url(user),
      "published" => DateTime.to_iso8601(DateTime.utc_now()),
      "to" => [@public]
    }

    {:ok, apactivity} = Bonfire.Social.APActivities.ap_receive(user, activity, object, true)
    apactivity
  end

  defp event_json(extra) do
    Map.merge(
      %{
        "type" => "Event",
        "name" => "Harvest Supper",
        "content" => "<p>Bring a dish</p>",
        "startTime" => "2030-09-20T18:00:00Z",
        "endTime" => "2030-09-20T22:00:00Z",
        "timezone" => "Europe/Paris",
        "to" => [@public]
      },
      extra
    )
  end

  defp convert_all, do: Conversion.migrate(Repo.all(Conversion.base_query()))

  test "an APActivity event becomes a native event with the same id, and its activity stays" do
    user = fake_user!()
    %{id: id} = apactivity!(user, event_json(%{}))

    convert_all()

    assert %Event{} = event = Repo.get(Event, id)
    event = Repo.preload(event, [:post_content, :time_span, :created])

    assert event.post_content.name == "Harvest Supper"
    assert event.post_content.html_body =~ "Bring a dish"
    assert DateTime.compare(event.time_span.has_beginning, ~U[2030-09-20 18:00:00Z]) == :eq
    assert DateTime.compare(event.time_span.has_end, ~U[2030-09-20 22:00:00Z]) == :eq
    assert event.time_span.timezone == "Europe/Paris"
    assert event.created.creator_id == user.id

    # readable as an event (the pointer was not left deleted by removing the APActivity row)
    assert {:ok, %Event{}} = Bonfire.Gatherings.Events.read(id, current_user: user)

    assert is_nil(Repo.get(Bonfire.Data.Social.APActivity, id))

    assert Repo.exists?(from(a in Bonfire.Data.Social.Activity, where: a.object_id == ^id))
  end

  test "an APActivity event with no start stays an APActivity, as an event needs one" do
    %{id: id} = apactivity!(fake_user!(), event_json(%{"startTime" => nil}))

    convert_all()

    assert %Bonfire.Data.Social.APActivity{} = Repo.get(Bonfire.Data.Social.APActivity, id)
    assert is_nil(Repo.get(Event, id))
  end

  test "an APActivity of another type is left alone" do
    %{id: id} = apactivity!(fake_user!(), event_json(%{"type" => "Workshop"}))

    convert_all()

    assert %Bonfire.Data.Social.APActivity{} = Repo.get(Bonfire.Data.Social.APActivity, id)
  end
end
