defmodule Bonfire.Gatherings.FeedWithinBoundsFilterTest do
  @moduledoc "Feeds narrowed to things whose place is inside a bounding box (the `within_bounds` filter of `Bonfire.Geolocate.FeedFilters`), here with events, the type that has a place."
  # `@moduletag :backend` comes with this case
  use Bonfire.Gatherings.DataCase, async: true

  import Bonfire.Me.Fake
  import ExUnit.CaptureLog
  alias Bonfire.Gatherings.Events
  alias Bonfire.Social.FeedLoader

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

  defp feed(user, filters) do
    FeedLoader.feed(:custom, Map.merge(%{time_limit: 0}, filters), current_user: user, limit: 50)
  end

  defp has?(feed, object, user), do: FeedLoader.feed_contains?(feed, object, current_user: user)

  defp box(south, west, north, east), do: %{south: south, west: west, north: north, east: east}

  test "inside the box, not outside it (north-south and east-west); things with no place are left out" do
    user = fake_user!()

    # a box around Devon: 50.0 to 51.0 north, 4.0 to 3.0 west
    inside = event!(user, "inside", %{name: "The Barn", lat: 50.5, long: -3.5})
    north = event!(user, "north", %{name: "The Moor", lat: 51.5, long: -3.5})
    east = event!(user, "east", %{name: "The Coast", lat: 50.5, long: -2.5})
    west = event!(user, "west", %{name: "The Reef", lat: 50.5, long: -4.5})
    nowhere = event!(user, "nowhere", nil)

    feed = feed(user, %{within_bounds: box(50.0, -4.0, 51.0, -3.0)})

    assert has?(feed, inside, user)
    refute has?(feed, north, user)
    refute has?(feed, east, user)
    refute has?(feed, west, user)
    refute has?(feed, nowhere, user)

    # a box that takes the east one in
    wider = feed(user, %{within_bounds: box(50.0, -4.0, 51.0, -2.0)})
    assert has?(wider, east, user)
    refute has?(wider, west, user)
  end

  test "a box over the antimeridian takes both sides of it, and a box a whole turn wide every longitude" do
    user = fake_user!()

    fiji = event!(user, "fiji", %{name: "Suva", lat: -18.1, long: 178.4})
    samoa = event!(user, "samoa", %{name: "Apia", lat: -13.8, long: -171.8})
    # the other side of the world
    chile = event!(user, "chile", %{name: "Santiago", lat: -33.4, long: -70.6})

    # as the map reports it past the edge: 170 to 190 degrees east (-170 once wrapped)
    over = feed(user, %{within_bounds: box(-30.0, 170.0, 0.0, 190.0)})
    assert has?(over, fiji, user)
    assert has?(over, samoa, user)
    refute has?(over, chile, user)

    all_longitudes = feed(user, %{within_bounds: box(-40.0, -200.0, 0.0, 200.0)})
    assert has?(all_longitudes, fiji, user)
    assert has?(all_longitudes, chile, user)
  end

  test "the filter is consumed by its own module, not left for the generic filtering to warn about" do
    user = fake_user!()
    event!(user, "inside", %{name: "The Barn", lat: 50.5, long: -3.5})

    log =
      capture_log(fn ->
        feed(user, %{within_bounds: box(50.0, -4.0, 51.0, -3.0)})
        feed(user, %{within_bounds: %{has_place: true}})
      end)

    refute log =~ "not a recognised filter"
    refute log =~ "within_bounds"
  end

  test "with no box, only the things that have a place" do
    user = fake_user!()

    placed = event!(user, "placed", %{name: "The Barn", lat: 50.5, long: -3.5})
    nowhere = event!(user, "nowhere", nil)

    feed = feed(user, %{within_bounds: %{has_place: true}})
    assert has?(feed, placed, user)
    refute has?(feed, nowhere, user)

    # control: without the filter both are listed
    all = feed(user, %{})
    assert has?(all, placed, user)
    assert has?(all, nowhere, user)
  end
end
