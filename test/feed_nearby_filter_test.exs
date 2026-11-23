defmodule Bonfire.Gatherings.FeedNearbyFilterTest do
  @moduledoc "Feeds narrowed to things whose place is near a point (the `primary_geolocation` mixin), here with events, the type that has one."
  # `@moduletag :backend` comes with this case
  use Bonfire.Gatherings.DataCase, async: true

  import Bonfire.Me.Fake
  alias Bonfire.Gatherings.Events
  alias Bonfire.Social.FeedLoader

  # Totnes
  @here %{lat: 50.4319, long: -3.6837}

  defp event!(user, name, place) do
    {:ok, event} =
      Events.create(
        current_user: user,
        boundary: "public",
        event_attrs:
          Map.merge(
            %{
              post_content: %{name: name},
              time_span: %{has_beginning: DateTime.add(DateTime.utc_now(), 7, :day)}
            },
            if(place, do: %{place: place}, else: %{})
          )
      )

    event
  end

  # a page big enough for every fixture (pages hold 2 in tests, and `feed_contains?` checks the page it's given)
  defp feed(user, filters) do
    FeedLoader.feed(:custom, Map.merge(%{time_limit: 0}, filters), current_user: user, limit: 50)
  end

  defp has?(feed, object, user), do: FeedLoader.feed_contains?(feed, object, current_user: user)

  test "within a radius of a point: places near it, not far ones; things without a place (eg. online) unless asked not to" do
    user = fake_user!()

    # about 2 km north
    near = event!(user, "near", %{name: "The Barn", lat: @here.lat + 0.018, long: @here.long})
    # about 50 km north
    far = event!(user, "far", %{name: "The Moor", lat: @here.lat + 0.45, long: @here.long})
    # no place: the only sign today of an online or global event
    nowhere = event!(user, "nowhere", nil)

    nearby = feed(user, %{nearby: %{lat: @here.lat, long: @here.long, km: 10}})
    assert has?(nearby, near, user)
    refute has?(nearby, far, user)
    assert has?(nearby, nowhere, user)

    strict =
      feed(user, %{nearby: %{lat: @here.lat, long: @here.long, km: 10, include_no_place: false}})

    assert has?(strict, near, user)
    refute has?(strict, nowhere, user)

    # a wider radius takes the far one in
    wider = feed(user, %{nearby: %{lat: @here.lat, long: @here.long, km: 60}})
    assert has?(wider, far, user)

    # east-west too, where the order of a point's axes matters: about 50 km east (a degree of longitude is about 71 km at 50°N)
    east = event!(user, "east", %{name: "The Coast", lat: @here.lat, long: @here.long + 0.7})
    refute has?(feed(user, %{nearby: %{lat: @here.lat, long: @here.long, km: 10}}), east, user)
    assert has?(feed(user, %{nearby: %{lat: @here.lat, long: @here.long, km: 60}}), east, user)
  end
end
