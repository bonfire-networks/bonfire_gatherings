defmodule Bonfire.Gatherings.Web.EventsMapBoundsTest do
  @moduledoc """
  The events map loads the events of the area in view, not the list's first page: on opening, one query (the events near the viewer's saved location, with the map centred there, else the soonest events that have a place, the map fitted to them), then one per pan or zoom, capped by `map_limit`, and for a view wider than `map_wide_longitude` the soonest events with a place instead of a box. The map tells its page the bounds only after the user moves it (what the hook sends is the map's `map_moved` event, which JS cannot be run to check here).
  """
  use Bonfire.Gatherings.ConnCase, async: false
  import PhoenixTest
  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Bonfire.Common.Settings
  alias Bonfire.Gatherings.Events

  # Totnes
  @here "50.432,-3.684"
  @lat 50.432
  @long -3.684
  # a degree of latitude is about 111.2 km
  @km 1 / 111.2

  setup do
    # maps need a tiles key (not left to the `.env`)
    Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")
    creator = fake_user!(fake_account!())
    {:ok, creator: creator}
  end

  defp hours(n), do: DateTime.add(DateTime.utc_now(), n * 3600, :second)

  defp event!(user, name, starts_in_hours, place) do
    {:ok, event} =
      Events.create(
        current_user: user,
        boundary: "public",
        event_attrs:
          Map.merge(
            %{post_content: %{name: name}, time_span: %{has_beginning: hours(starts_in_hours)}},
            if(place, do: %{place: place}, else: %{})
          )
      )

    event
  end

  # a place this many km north of the saved location
  defp north!(user, name, km, starts_in_hours \\ 48),
    do:
      event!(user, name, starts_in_hours, %{
        name: name <> " place",
        lat: @lat + km * @km,
        long: @long
      })

  defp viewer!(location? \\ false) do
    user = fake_user!(fake_account!(), %{location: nil})

    if location? do
      {:ok, _} =
        Settings.put([Bonfire.Geolocate, :location], @here, current_user: user, scope: :user)

      Bonfire.Common.Repo.maybe_preload(user, :settings, force: true)
    else
      user
    end
  end

  defp open(user), do: Phoenix.LiveViewTest.live(conn(user: user), "/events/map")

  defp popups(html_or_view) do
    html =
      if is_binary(html_or_view),
        do: html_or_view,
        else: Phoenix.LiveViewTest.render(html_or_view)

    html
    |> Floki.parse_document!()
    |> Floki.find("[data-id=events_map] leaflet-marker")
    |> Enum.map(&(Floki.attribute(&1, "popup") |> List.first()))
    # the event's name is what the popup's link holds
    |> Enum.map(fn popup -> Regex.run(~r{<strong>(.*?)</strong>}, popup) |> List.last() end)
    |> Enum.sort()
  end

  defp moved(view, south, west, north, east) do
    view
    |> Phoenix.LiveViewTest.with_target("[data-id=map]")
    |> Phoenix.LiveViewTest.render_hook("map_moved", %{
      "south" => south,
      "west" => west,
      "north" => north,
      "east" => east
    })

    # the component sends its page a message, which is handled before this renders
    Phoenix.LiveViewTest.render(view)
  end

  # the queries the events' feed makes, as they run
  defp count_feed_queries(fun) do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    handler = "events-map-queries-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:bonfire, :common, :repo, :query],
      fn _event, _measurements, meta, _ -> Agent.update(agent, &[meta.query | &1]) end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler)
    queries = Agent.get(agent, & &1)
    {result, Enum.count(queries, &feed_query?/1)}
  end

  defp feed_query?(sql), do: sql =~ "ORDER BY" and sql =~ "has_beginning" and sql =~ "LIMIT"

  describe "opening the map" do
    test "with no saved location: the soonest upcoming events that have a place, in one query, the map fitted to their markers",
         %{creator: creator} do
      Process.put([:bonfire_gatherings, Bonfire.Gatherings.Events, :map_limit], 2)

      # an online one is the soonest, and has no place
      event!(creator, "Online Chat", 5, nil)
      north!(creator, "Soon Barn", 2, 24)
      north!(creator, "Later Hall", 90, 48)
      north!(creator, "Last Moor", 40, 72)

      {{:ok, _view, html}, queries} = count_feed_queries(fn -> open(viewer!()) end)

      # the cap, in start order, with no online event
      assert popups(html) == ["Later Hall", "Soon Barn"]

      doc = Floki.parse_document!(html)
      # the map reports where it is, once the user has moved it
      assert [_] = Floki.find(doc, "[data-id=events_map] leaflet-map[report-bounds]")
      assert [] = Floki.find(doc, "[data-id=events_map] leaflet-map[live-bounds]")
      # fitted to the markers, not to a place
      assert [] = Floki.attribute(doc, "[data-id=events_map] leaflet-map", "fit-bounds")

      assert [[_, _], [_, _]] =
               doc
               |> Floki.attribute("[data-id=events_map] leaflet-map", "points")
               |> List.first()
               |> Jason.decode!()

      # one query to open (the page is rendered twice: for the browser's first load, and connected)
      assert queries == 2
    end

    test "with a saved location: the events within the default radius, the map centred there at the radius' extent",
         %{creator: creator} do
      north!(creator, "Near Barn", 2)
      north!(creator, "Mid Hall", 35)
      north!(creator, "Far Moor", 80)
      event!(creator, "Online Chat", 5, nil)

      {{:ok, _view, html}, queries} = count_feed_queries(fn -> open(viewer!(true)) end)

      assert popups(html) == ["Mid Hall", "Near Barn"]

      # the view that holds the 50 km radius around the saved location
      assert [fit] =
               html
               |> Floki.parse_document!()
               |> Floki.attribute("[data-id=events_map] leaflet-map", "fit-bounds")

      assert [[south, west], [north, east]] = Jason.decode!(fit)
      assert_in_delta (south + north) / 2, @lat, 0.001
      assert_in_delta (west + east) / 2, @long, 0.001
      # 50 km each way, about 0.45 degrees of latitude
      assert_in_delta north - south, 2 * 50 * @km, 0.01
      assert east - west > north - south

      assert queries == 2
    end

    test "with the radius set to Anywhere, a saved location does not narrow it", %{
      creator: creator
    } do
      north!(creator, "Near Barn", 2, 24)
      north!(creator, "Far Moor", 80, 48)

      user = viewer!(true)

      {:ok, _} =
        Settings.put([Bonfire.Gatherings.Events, :default_nearby_radius], "anywhere",
          current_user: user,
          scope: :user
        )

      user = Bonfire.Common.Repo.maybe_preload(user, :settings, force: true)
      {:ok, _view, html} = open(user)

      assert popups(html) == ["Far Moor", "Near Barn"]

      assert [] =
               html
               |> Floki.parse_document!()
               |> Floki.attribute("[data-id=events_map] leaflet-map", "fit-bounds")
    end
  end

  describe "moving the map" do
    test "the events in the box replace those shown, in one query, and a box with nothing in it shows none",
         %{creator: creator} do
      north!(creator, "Near Barn", 2)
      north!(creator, "Far Moor", 80)
      event!(creator, "Online Chat", 5, nil)

      # opens near the saved location, where the far one is out of the radius
      {:ok, view, html} = open(viewer!(true))
      assert popups(html) == ["Near Barn"]

      # panned to the far one: the box is the area now, not the radius
      far_lat = @lat + 80 * @km

      {{html, queries}, log} =
        with_log(fn ->
          count_feed_queries(fn ->
            moved(view, far_lat - 0.1, @long - 0.2, far_lat + 0.1, @long + 0.2)
          end)
        end)

      assert popups(html) == ["Far Moor"]
      assert queries == 1
      # the filter is consumed by its module, not left for the generic filtering to warn about
      refute log =~ "not a recognised filter"

      # and back over the near one, east-west too: a box to its east holds neither
      assert popups(moved(view, @lat, @long - 0.2, @lat + 0.1, @long + 0.2)) == ["Near Barn"]
      assert popups(moved(view, @lat, @long + 0.5, @lat + 0.1, @long + 0.9)) == []
    end

    test "the cap applies, to the soonest in the box", %{creator: creator} do
      Process.put([:bonfire_gatherings, Bonfire.Gatherings.Events, :map_limit], 2)

      north!(creator, "Third Barn", 3, 72)
      north!(creator, "First Barn", 1, 24)
      north!(creator, "Second Barn", 2, 48)

      {:ok, view, _html} = open(viewer!())

      assert popups(moved(view, @lat - 1, @long - 1, @lat + 1, @long + 1)) == [
               "First Barn",
               "Second Barn"
             ]
    end

    test "a view wider than the threshold takes the soonest events with a place, wherever they are, not a box",
         %{creator: creator} do
      Process.put([:bonfire_gatherings, Bonfire.Gatherings.Events, :map_limit], 2)

      event!(creator, "Online Chat", 5, nil)
      north!(creator, "Soon Barn", 2, 24)

      event!(creator, "Faraway Reef", 48, %{name: "Reef place", lat: -18.1, long: 178.4})
      north!(creator, "Last Moor", 40, 72)

      {:ok, view, _html} = open(viewer!())

      # the whole world (more than 180 degrees of longitude)
      assert popups(moved(view, -80, -180, 80, 180)) == ["Faraway Reef", "Soon Barn"]

      # control: a box under the threshold keeps to its own area
      assert popups(moved(view, @lat - 1, @long - 1, @lat + 1, @long + 1)) == [
               "Last Moor",
               "Soon Barn"
             ]
    end

    test "a message that is not a box changes nothing", %{creator: creator} do
      north!(creator, "Near Barn", 2)
      {:ok, view, html} = open(viewer!(true))
      assert popups(html) == ["Near Barn"]

      assert popups(moved(view, "north", nil, 1, 2)) == ["Near Barn"]
    end
  end
end
