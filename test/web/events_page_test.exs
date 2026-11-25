defmodule Bonfire.Gatherings.Web.EventsPageTest do
  @moduledoc """
  The `/events` page lists upcoming native events (not yet ended, earliest start first), and `/events/category/:ref` those tagged with a topic. It replaces `Bonfire.UI.Social.EventsLive`, which listed APActivity events.
  """
  use Bonfire.Gatherings.ConnCase, async: false
  import PhoenixTest
  import Bonfire.Classify.Simulate

  alias Bonfire.Gatherings.Events

  setup do
    account = fake_account!()
    me = fake_user!(account)
    {:ok, conn: conn(user: me, account: account), me: me}
  end

  defp hours(n), do: DateTime.add(DateTime.utc_now(), n * 3600, :second)

  defp event!(user, name, starts, ends, extra \\ %{}) do
    {:ok, event} =
      Events.create(
        current_user: user,
        boundary: "public",
        event_attrs:
          Map.merge(
            %{post_content: %{name: name}, time_span: %{has_beginning: starts, has_end: ends}},
            extra
          )
      )

    event
  end

  test "lists an upcoming event, with its primary image as its cover and its other media not listed, and not one that has ended",
       %{conn: conn, me: me} do
    {:ok, cover} =
      Bonfire.Files.upload(
        Bonfire.Files.ImageUploader,
        me,
        Bonfire.Files.Simulation.image_file(),
        %{metadata: %{"primary_image" => "true"}}
      )

    {:ok, other} =
      Bonfire.Files.upload(Bonfire.Files.ImageUploader, me, Bonfire.Files.Simulation.image_file())

    event!(me, "Harvest Supper", hours(48), hours(50), %{uploaded_media: [cover, other]})
    event!(me, "Last Year's Fair", hours(-72), hours(-70))

    conn
    |> visit("/events")
    |> assert_has("[data-id=event_preview]", text: "Harvest Supper")
    |> refute_has("[data-id=event_preview]", text: "Last Year's Fair")
    |> assert_has("[data-id=event_preview] [data-id=event_cover]")
    |> refute_has("[data-id=multimedia_list]")
  end

  test "a card shows the event's online link beside its place, which a feed card does not load",
       %{
         conn: conn,
         me: me
       } do
    geo = Bonfire.Geolocate.Simulate.fake_geolocation!(me, nil, %{name: "The Old Barn"})

    event!(me, "Harvest Supper", hours(48), hours(50), %{
      primary_geolocation: %{geolocation_id: geo.id},
      extra_info: %{info: %{"online_address" => "https://meet.example.local/room"}}
    })

    conn
    |> visit("/events")
    |> wait_async()
    |> assert_has("[data-id=event_preview] [data-role=event_where] [data-role=event_place]",
      text: "The Old Barn"
    )
    |> assert_has(
      "[data-id=event_preview] [data-role=event_where] a[data-role=event_online][href='https://meet.example.local/room'][target=_blank][rel='noopener nofollow']"
    )
    |> visit("/feed")
    |> wait_async()
    |> assert_has("[data-id=event_preview] [data-role=event_place]", text: "The Old Barn")
    |> refute_has("[data-role=event_online]")
  end

  test "lists the earliest start first", %{conn: conn, me: me} do
    event!(me, "Second Thing", hours(72), nil)
    event!(me, "First Thing", hours(24), nil)

    # the rendered page, to compare the positions of the two
    {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events")

    assert [_, after_first] = String.split(html, "First Thing", parts: 2)
    assert after_first =~ "Second Thing"
  end

  test "a topic's page lists only the events tagged with it, and the chips are the categories of the listed events",
       %{conn: conn, me: me} do
    # the chips are cached for the instance, so not from an earlier test's events
    Bonfire.Gatherings.Events.category_facets(:upcoming, cache: :reset)

    topic = fake_category!(me, nil, %{type: :topic, name: "Jazz"})
    past_topic = fake_category!(me, nil, %{type: :topic, name: "Pottery"})

    event!(me, "Jazz Night", hours(24), nil, %{tags: [topic]})
    event!(me, "Pottery Class", hours(30), nil)
    event!(me, "Last Kiln Day", hours(-72), hours(-70), %{tags: [past_topic]})

    conn
    |> visit("/events/category/#{topic.character.username}")
    |> assert_has("[data-id=event_preview]", text: "Jazz Night")
    |> refute_has("[data-id=event_preview]", text: "Pottery Class")

    # a chip for each category an upcoming event has, and none for one only a past event has
    conn
    |> visit("/events")
    |> wait_async()
    |> assert_has(
      "[data-id=events_categories] a[href='/events/category/#{topic.character.username}']",
      text: "Jazz"
    )
    |> refute_has("[data-id=events_categories] a", text: "Pottery")
    # nor the 36 FEP-8a8e values that no event has
    |> refute_has("[data-id=events_categories] a", text: "Meditation")

    # the past list has no chips for now
    # conn
    # |> visit("/events/past")
    # |> wait_async()
    # |> refute_has("[data-id=events_categories]")
    # the past list's chips are the categories of the past events (counted and cached apart)
    Bonfire.Gatherings.Events.category_facets(:past, cache: :reset)

    conn
    |> visit("/events/past")
    |> wait_async()
    # |> assert_has("[data-id=events_categories] a[href='/events/category/#{past_topic.character.username}']",
    #   text: "Pottery"
    # )
    # to the category's past events, as the list is of past ones
    |> assert_has(
      "[data-id=events_categories] a[href='/events/category/#{past_topic.character.username}/past']",
      text: "Pottery"
    )
    |> assert_has("[data-id=events_categories] a[href='/events/past']", text: "All")
    |> refute_has("[data-id=events_categories] a", text: "Jazz")
  end

  test "a topic's page also lists the events of its subtopics, as a group's feed has its topics'",
       %{
         conn: conn,
         me: me
       } do
    arts = fake_category!(me, nil, %{type: :topic, name: "Arts"})
    theatre = fake_category!(me, arts, %{type: :topic, name: "Theatre"})

    event!(me, "Opening Night", hours(24), nil, %{tags: [theatre]})
    event!(me, "Pottery Class", hours(30), nil)

    conn
    |> visit("/events/category/#{arts.character.username}")
    |> assert_has("[data-id=event_preview]", text: "Opening Night")
    |> refute_has("[data-id=event_preview]", text: "Pottery Class")
  end

  test "events are grouped under a heading per day, and their cards show only the time, or all day",
       %{conn: conn, me: me} do
    # two, as a page holds two in tests
    event!(me, "Morning Swim", ~U[2030-09-20 08:00:00Z], ~U[2030-09-20 09:00:00Z])
    event!(me, "Market Day", ~U[2030-09-21 00:00:00Z], nil)

    {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events")
    doc = Floki.parse_document!(html)

    # one heading per day, in order, each before its events
    # the weekday, then the date (with its year, as 2030 is not this year)
    assert [["Friday", "September 20, 2030"], ["Saturday", "September 21, 2030"]] ==
             doc
             |> Floki.find("[data-role=events_day]")
             |> Enum.map(fn h -> h |> Floki.find("span") |> Enum.map(&String.trim(Floki.text(&1))) end)

    conn
    |> visit("/events")
    # the time, not the date again
    |> assert_has("[data-id=event_preview] [data-role=event_time]", text: "8:00 AM")
    |> refute_has("[data-id=event_preview] [data-role=event_time]", text: "2030")
    |> refute_has("[data-id=event_preview] [data-role=event_date_chip]")
    |> assert_has("[data-id=event_preview] [data-role=event_time]", text: "All day")
  end

  test "a card's badge names its categories and labels, less the one the page is filtered by",
       %{conn: conn, me: me} do
    topic = fake_category!(me, nil, %{type: :topic, name: "Jazz"})

    {:ok, label} =
      Bonfire.Classify.Categories.get_or_create_topic(
        %{
          name: "Family friendly",
          username: "family_friendly_#{System.unique_integer([:positive])}",
          type: :label
        },
        me
      )

    event!(me, "Kids Jazz", hours(24), nil, %{tags: [topic, label]})
    event!(me, "Untagged Thing", hours(30), nil)

    conn
    |> visit("/events")
    |> assert_has("[data-id=event_preview] [data-role=event_badge]", text: "Jazz")
    |> assert_has("[data-id=event_preview] [data-role=event_badge]", text: "Family friendly")
    # untagged: no badge
    |> refute_has("[data-id=event_preview] [data-role=event_badge]", text: "Event")

    conn
    |> visit("/events/category/#{topic.character.username}")
    |> assert_has("[data-id=event_preview] [data-role=event_badge]", text: "Family friendly")
    |> refute_has("[data-id=event_preview] [data-role=event_badge]", text: "Jazz")
  end

  test "events filter by a label, and by a category and a label together", %{conn: conn, me: me} do
    # the chips are cached for the instance, so not from an earlier test's events
    Bonfire.Gatherings.Events.category_facets(:upcoming, cache: :reset)

    jazz = fake_category!(me, nil, %{type: :topic, name: "Jazz"})

    {:ok, family} =
      Bonfire.Classify.Categories.get_or_create_topic(
        %{
          name: "Family friendly",
          username: "family_friendly_#{System.unique_integer([:positive])}",
          type: :label
        },
        me
      )

    event!(me, "Kids Jazz", hours(24), nil, %{tags: [jazz, family]})
    event!(me, "Late Jazz", hours(30), nil, %{tags: [jazz]})

    # the label alone
    conn
    |> visit("/events/label/#{family.character.username}")
    |> assert_has("[data-id=event_preview]", text: "Kids Jazz")
    |> refute_has("[data-id=event_preview]", text: "Late Jazz")

    # the category and the label: only events with both
    conn
    |> visit("/events/category/#{jazz.character.username}/label/#{family.character.username}")
    |> assert_has("[data-id=event_preview]", text: "Kids Jazz")
    |> refute_has("[data-id=event_preview]", text: "Late Jazz")

    # on the category's page, a label chip keeps the category
    conn
    |> visit("/events/category/#{jazz.character.username}")
    |> wait_async()
    |> assert_has(
      "[data-id=events_labels] a[href='/events/category/#{jazz.character.username}/label/#{family.character.username}']"
    )
  end

  describe "layout" do
    test "a user who chose tiles sees the events as tiles", %{me: me} do
      event!(me, "Harvest Supper", hours(48), nil)
      account = fake_account!()

      tiler =
        Bonfire.Common.Utils.current_user(
          Bonfire.Common.Settings.put(
            [Bonfire.Gatherings.Events, :custom_preview],
            Bonfire.Gatherings.Web.Preview.EventTileLive,
            current_user: fake_user!(account)
          )
        )

      conn(user: tiler, account: account)
      |> visit("/events")
      |> assert_has("[data-id=event_preview][data-layout=tile]", text: "Harvest Supper")
      # a tile shows no author, so with no place it names the host instead
      |> assert_has("[data-id=event_preview][data-layout=tile] [data-role=event_host]",
        text: me.profile.name
      )
      |> refute_has("[data-id=event_preview][data-layout=tile] [data-role=event_place]")
    end

    defp place_event!(me, name, place_name, info) do
      geo = Bonfire.Geolocate.Simulate.fake_geolocation!(me, nil, %{name: place_name})

      event!(me, name, hours(48), nil, %{
        primary_geolocation: %{geolocation_id: geo.id},
        extra_info: %{info: info}
      })
    end

    test "a list row has its time above its name and its place below it", %{
      conn: conn,
      me: me
    } do
      place_event!(me, "Barn Dance", "The Old Barn", %{
        "online_address" => "https://meet.example.local/room"
      })

      conn
      |> visit("/events")
      |> wait_async()
      |> assert_has("[data-layout=list] [data-role=event_when] time[data-role=event_time]",
        count: 1
      )
      |> refute_has("[data-layout=list] [data-role=event_where] [data-role=event_time]")
      |> assert_has("[data-layout=list] [data-role=event_where] [data-role=event_place]",
        text: "The Old Barn"
      )

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events")
      {:ok, doc} = Floki.parse_document(html)

      # in document order: the time, the name, the place, then "Online"
      roles =
        doc
        |> Floki.find("[data-layout=list] *")
        |> Enum.map(fn
          {"h2", _, _} -> "name"
          node -> node |> Floki.attribute("data-role") |> List.first()
        end)
        |> Enum.filter(&(&1 in ["event_time", "name", "event_place", "event_online"]))

      assert roles == ["event_time", "name", "event_place", "event_online"]
    end

    test "a list row shows a line of the event's description with Read more, and none without one",
         %{conn: conn, me: me} do
      event!(me, "Harvest Supper", hours(48), nil, %{
        post_content: %{name: "Harvest Supper", summary: "Bring a dish to share"}
      })

      event!(me, "Barn Dance", hours(72), nil)

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview]", text: "Barn Dance")
      |> assert_has("[data-layout=list] [data-role=event_summary]", count: 1)
      |> assert_has("[data-layout=list] [data-role=event_summary]",
        text: "Bring a dish to share"
      )
      |> assert_has("[data-layout=list] [data-role=event_summary] button", text: "Read more")
    end

    test "a list row of a remote event does not name its server" do
      html =
        Phoenix.LiveViewTest.render_component(
          &Bonfire.Gatherings.Web.Preview.EventRowLive.render/1,
          __context__: %{},
          permalink: "/events/far-away",
          object: %{
            post_content: %{name: "Far Away Fair"},
            peered: %{canonical_uri: "https://remote.example.local/pub/events/1"}
          }
        )

      assert html =~ "Far Away Fair"
      refute html =~ "event_origin"
      refute html =~ "remote.example.local"
    end

    test "a list row shows a URL place as a link with the online link, a plain place as the text with none",
         %{conn: conn, me: me} do
      place_event!(me, "Video Call", "https://meet.jit.si/abc", %{
        "online_address" => "https://meet.example.local/room"
      })

      place_event!(me, "Barn Dance", "The Old Barn", %{})

      conn
      |> visit("/events")
      |> wait_async()
      |> assert_has(
        "[data-layout=list] [data-role=event_where] a[data-role=event_place][href='https://meet.jit.si/abc'][target=_blank][rel='noopener nofollow']"
      )
      |> assert_has(
        "[data-layout=list] [data-role=event_where] a[data-role=event_online][href='https://meet.example.local/room']"
      )
      |> assert_has("[data-layout=list] [data-role=event_where] span[data-role=event_place]",
        text: "The Old Barn"
      )
      |> assert_has("[data-layout=list] [data-role=event_online]", count: 1)
    end

    test "a tile shows the online link beside the place, and a map link with none", %{me: me} do
      place_event!(me, "Video Call", "The Old Barn", %{
        "online_address" => "https://meet.example.local/room"
      })

      place_event!(me, "Barn Dance", "The Old Mill", %{})
      account = fake_account!()

      tiler =
        Bonfire.Common.Utils.current_user(
          Bonfire.Common.Settings.put(
            [Bonfire.Gatherings.Events, :custom_preview],
            Bonfire.Gatherings.Web.Preview.EventTileLive,
            current_user: fake_user!(account)
          )
        )

      conn(user: tiler, account: account)
      |> visit("/events")
      |> wait_async()
      |> assert_has(
        "[data-layout=tile] [data-role=event_where] a[data-role=event_online][href='https://meet.example.local/room'][target=_blank][rel='noopener nofollow']"
      )
      |> assert_has(
        "[data-layout=tile] a[data-role=event_place][href^='https://www.openstreetmap.org/search']",
        text: "The Old Mill"
      )
      |> assert_has("[data-layout=tile] [data-role=event_online]", count: 1)
    end

    test "choosing tiles in the dropdown saves it, so the next visit is in tiles", %{
      conn: conn,
      me: me
    } do
      event!(me, "Harvest Supper", hours(48), nil)

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview][data-layout=list]")
      |> within("[data-id=events_layout]", &choose(&1, "Tiles"))
      |> assert_has("[data-id=event_preview][data-layout=tile]")

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview][data-layout=tile]")
    end

    test "the map page shows the events' places, each with its name, place and link, and the saved view stays the list",
         %{conn: conn, me: me} do
      # maps need a tiles key (not left to the `.env`)
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")

      geo =
        Bonfire.Geolocate.Simulate.fake_geolocation!(me, nil, %{
          name: "The Old Barn",
          lat: 45.07,
          long: 7.69
        })

      event =
        event!(me, "Harvest Supper", hours(48), nil, %{
          primary_geolocation: %{geolocation_id: geo.id}
        })

      # {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, "/events")
      #
      # html =
      #   view
      #   |> Phoenix.LiveViewTest.element("[data-id=events_layout]")
      #   |> Phoenix.LiveViewTest.render_change(%{"layout" => "map"})
      # the map has its own page, which the layout dropdown goes to
      # conn
      # |> visit("/events")
      # |> assert_has("a[data-role=events_map_link][href='/events/map']")
      conn
      |> visit("/events")
      |> within("[data-id=events_layout]", &choose(&1, "Map"))
      |> assert_path("/events/map")
      # the map takes the right sidebar's width, as tiles do
      |> refute_has("#widgets-drawer")

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events/map")

      [popup] =
        html
        |> Floki.parse_document!()
        |> Floki.find("[data-id=events_map] leaflet-marker")
        |> Enum.map(&(Floki.attribute(&1, "popup") |> List.first()))

      assert popup =~ "Harvest Supper"
      assert popup =~ "The Old Barn"
      assert popup =~ "/discussion/#{event.id}"

      doc = Floki.parse_document!(html)

      # the map is drawn around the events' places (the map's JS fits its view to `points`, and has no view without them, so draws no tiles)
      assert [[45.07, 7.69]] =
               doc
               |> Floki.attribute("[data-id=events_map] leaflet-map", "points")
               |> List.first()
               |> Jason.decode!()

      # its hook sends nothing as it moves, as the events map does not load the places in view (they would replace the events)
      assert Floki.find(doc, "[data-id=events_map] leaflet-map[live-bounds]") == []

      # the map fills its box, rather than the map's default height
      assert [class] = Floki.attribute(doc, "[data-id=events_map] [data-id=map]", "class")
      assert class =~ "h-full"
      refute class =~ "250px"

      # not saved: a new visit is in the list again
      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview][data-layout=list]")
    end

    test "the layout dropdown offers the map to signed-in users, not to guests", %{
      conn: conn,
      me: me
    } do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")
      event!(me, "Harvest Supper", hours(48), nil)

      conn
      |> visit("/events")
      |> assert_has("[data-id=events_layout]", text: "Map")

      conn()
      |> visit("/events")
      |> assert_has("[data-id=events_layout]", text: "Tiles")
      |> refute_has("[data-id=events_layout]", text: "Map")
    end

    test "a guest is asked to sign in to see the events map, and gets no map", %{me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")
      event!(me, "Harvest Supper", hours(48), nil)

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn(), "/events/map")
      doc = Floki.parse_document!(html)

      assert [_] = Floki.find(doc, "[data-id=events_map] [data-id=map_signed_out]")
      assert Floki.find(doc, "[data-id=events_map] leaflet-map") == []
    end

    test "with no upcoming event that has a place, the map is empty, and shows no other places",
         %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")
      # a place that no event is at
      Bonfire.Geolocate.Simulate.fake_geolocation!(me, nil, %{name: "Not an Event Venue"})
      event!(me, "Harvest Supper", hours(48), nil)

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events/map")
      doc = Floki.parse_document!(html)

      assert Floki.find(doc, "[data-id=events_map] leaflet-map") != []
      assert Floki.find(doc, "[data-id=events_map] leaflet-marker") == []

      assert [] =
               doc
               |> Floki.attribute("[data-id=events_map] leaflet-map", "points")
               |> List.first()
               |> Jason.decode!()

      refute html =~ "Not an Event Venue"
    end

    test "without a Mapbox key, maps come from the styles' server; without either, the dropdown offers no map, and the map page says maps are not set up",
         %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "")
      event!(me, "Harvest Supper", hours(48), nil)

      # the styles' server (eg. OpenFreeMap) is enough
      Process.put(
        [:bonfire_geolocate, Bonfire.Geolocate, :map_styles_url],
        "https://tiles.example.local/styles/"
      )

      conn
      |> visit("/events")
      |> assert_has("[data-id=events_layout]", text: "Map")

      conn
      |> visit("/events/map")
      |> assert_has("[data-id=events_map] leaflet-map")

      # neither
      Process.put([:bonfire_geolocate, Bonfire.Geolocate, :map_styles_url], "")

      conn
      |> visit("/events")
      |> assert_has("[data-id=events_layout]", text: "Tiles")
      |> refute_has("[data-id=events_layout]", text: "Map")

      conn
      |> visit("/events/map")
      |> assert_has("[data-id=events_map] [data-id=map_unavailable]")
      |> refute_has("[data-id=events_map] leaflet-map")
    end

    test "with no choice, the configured default applies", %{conn: conn, me: me} do
      event!(me, "Harvest Supper", hours(48), nil)
      # the flavour's default preview component
      Process.put(
        [:bonfire_gatherings, Bonfire.Gatherings.Events, :custom_preview],
        Bonfire.Gatherings.Web.Preview.EventTileLive
      )

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview][data-layout=tile]")
      # the tiles take the right sidebar's width
      |> refute_has("#widgets-drawer")
    end
  end

  test "a subtopic's chip is in its parent's dropdown chip, not at the top level", %{
    conn: conn,
    me: me
  } do
    Bonfire.Gatherings.Events.category_facets(:upcoming, cache: :reset)

    arts = fake_category!(me, nil, %{type: :topic, name: "Arts"})
    theatre = fake_category!(me, arts, %{type: :topic, name: "Theatre"})

    event!(me, "Opening Night", hours(24), nil, %{tags: [theatre]})

    conn
    |> visit("/events")
    |> wait_async()
    |> assert_has("[data-id=events_categories] [data-role=chip_dropdown]", text: "Arts")
    |> assert_has(
      "[data-id=events_categories] [data-role=chip_dropdown] a[href='/events/category/#{theatre.character.username}']",
      text: "Theatre"
    )
    |> refute_has("[data-id=events_categories] > a", text: "Theatre")
  end

  test "the labels of the listed events are chips of their own, apart from the categories", %{
    conn: conn,
    me: me
  } do
    Bonfire.Gatherings.Events.category_facets(:upcoming, cache: :reset)

    topic = fake_category!(me, nil, %{type: :topic, name: "Concerts"})

    # an event label, under the "Events" label as the ingest makes them
    {:ok, label} =
      Bonfire.Classify.Categories.get_or_create_topic(
        %{
          name: "Family friendly",
          username: "family_friendly_#{System.unique_integer([:positive])}",
          type: :label,
          parent_category: Bonfire.Gatherings.EventCategories.events_label()
        },
        me
      )

    event!(me, "Kids Gig", hours(24), nil, %{tags: [topic, label]})

    conn
    |> visit("/events")
    |> wait_async()
    |> assert_has("[data-id=events_categories] a", text: "Concerts")
    |> refute_has("[data-id=events_categories] a", text: "Family friendly")
    |> assert_has("[data-id=events_labels] a", text: "Family friendly")
    |> refute_has("[data-id=events_labels] a", text: "Concerts")
    # nor the labels' parents (the "Events" label, the top "Labels"), which every labelled event counts towards
    |> refute_has(
      "[data-id=events_labels] a[href*='#{Bonfire.Gatherings.EventCategories.events_label_id()}']"
    )
    |> refute_has("[data-id=events_labels] a[href*='7CATEG0RYTHATC0NTA1N1ABE1S']")
  end

  test "a chip is shown only to those who may see its category", %{conn: conn} do
    Bonfire.Gatherings.Events.category_facets(:upcoming, cache: :reset)

    member_account = fake_account!()
    member = fake_user!(member_account)
    hidden = fake_group!(member, %{name: "Secret Club", visibility: "members:private"})

    event!(member, "Secret Gathering", hours(24), nil, %{tags: [hidden]})

    # its member sees the chip
    conn(user: member, account: member_account)
    |> visit("/events")
    |> wait_async()
    |> assert_has("[data-id=events_categories] a", text: "Secret Club")

    # someone else does not, though the event's category is counted for everyone
    conn
    |> visit("/events")
    |> wait_async()
    |> refute_has("[data-id=events_categories] a", text: "Secret Club")
  end

  test "an unknown topic is not found", %{conn: conn} do
    conn
    |> visit("/events/category/no_such_topic_#{System.unique_integer([:positive])}")
    |> refute_has("[data-id=event_preview]")
  end

  # test "says so when there are no upcoming events", %{conn: conn} do
  #   conn
  #   |> visit("/events")
  #   |> assert_has("[data-id=events_empty]")
  # end
  # no upcoming events sends to the past ones, which say so when there are none either
  test "with no upcoming events, goes to the past ones, and says so when there are none", %{
    conn: conn
  } do
    conn
    |> visit("/events")
    |> assert_path("/events/past")
    |> assert_has("[data-id=flash_info]", text: "There are no upcoming events")
    |> assert_has("[data-id=events_empty]")
  end

  test "with no upcoming events, lists past ones, most recent first", %{conn: conn, me: me} do
    event!(me, "Older Fair", hours(-170), hours(-168))
    event!(me, "Recent Supper", hours(-26), hours(-24))

    {:ok, _view, html} =
      case Phoenix.LiveViewTest.live(conn, "/events") do
        {:error, {:live_redirect, %{to: to}}} -> Phoenix.LiveViewTest.live(conn, to)
        {:error, {:redirect, %{to: to}}} -> Phoenix.LiveViewTest.live(conn, to)
        other -> other
      end

    assert [_, after_recent] = String.split(html, "Recent Supper", parts: 2)
    assert after_recent =~ "Older Fair"
  end

  test "with an upcoming event, stays on the upcoming ones", %{conn: conn, me: me} do
    event!(me, "Harvest Supper", hours(48), hours(50))
    event!(me, "Recent Supper", hours(-26), hours(-24))

    conn
    |> visit("/events")
    |> assert_path("/events")
    |> refute_has("[data-id=flash_info]", text: "There are no upcoming events")
    |> assert_has("[data-id=event_preview]", text: "Harvest Supper")
    |> refute_has("[data-id=event_preview]", text: "Recent Supper")
  end

  test "a stranger is not shown an event made for mentioned people only; its creator is", %{
    conn: conn,
    me: me
  } do
    {:ok, _} =
      Events.create(
        current_user: me,
        boundary: "mentions",
        event_attrs: %{
          post_content: %{name: "Secret Supper"},
          time_span: %{has_beginning: hours(24), has_end: nil}
        }
      )

    event!(me, "Open Supper", hours(48), nil)

    account = fake_account!()
    stranger = fake_user!(account)

    # control: the creator sees both
    conn
    |> visit("/events")
    |> assert_has("[data-id=event_preview]", text: "Secret Supper")
    |> assert_has("[data-id=event_preview]", text: "Open Supper")

    conn(user: stranger, account: account)
    |> visit("/events")
    |> assert_has("[data-id=event_preview]", text: "Open Supper")
    |> refute_has("[data-id=event_preview]", text: "Secret Supper")
  end

  test "load more lists the events after the first page, once each, in the order of their start dates",
       %{conn: conn, me: me} do
    # pages hold 2 in tests; created out of order, so the order of the start dates is not the order of the ids
    event!(me, "Third Thing", hours(72), nil)
    event!(me, "Fifth Thing", hours(120), nil)
    event!(me, "First Thing", hours(24), nil)
    event!(me, "Fourth Thing", hours(96), nil)
    event!(me, "Second Thing", hours(48), nil)

    {:ok, view, html} = Phoenix.LiveViewTest.live(conn, "/events")
    assert [_, after_first] = String.split(html, "First Thing", parts: 2)
    assert after_first =~ "Second Thing"
    refute html =~ "Third Thing"

    view
    |> Phoenix.LiveViewTest.element("button", "Load more")
    |> Phoenix.LiveViewTest.render_click()

    view
    |> Phoenix.LiveViewTest.element("button", "Load more")
    |> Phoenix.LiveViewTest.render_click()

    html = Phoenix.LiveViewTest.render(view)
    names = Regex.scan(~r/(First|Second|Third|Fourth|Fifth) Thing/, html)

    assert names |> Enum.map(&hd/1) |> Enum.uniq() ==
             ["First Thing", "Second Thing", "Third Thing", "Fourth Thing", "Fifth Thing"]

    assert html |> Floki.parse_document!() |> Floki.find("[data-id=event_preview]") |> length() ==
             5
  end

  describe "feed filters" do
    # the list view's filters are the customize-feed widget in the sidebar, as on the feeds: its "More filters" opens the editor
    defp open_filters(session) do
      session
      |> wait_async()
      |> click_button("[data-role=open_modal]", "More filters")
    end

    # the tile and map views have no sidebar: a Filters button opens the same widget inline
    defp open_inline_filters(session) do
      session
      |> wait_async()
      |> click_button("[data-role=toggle_filters]", "Filters")
      |> click_button("[data-role=events_filters] [data-role=open_modal]", "More filters")
    end

    defp apply_filters(session) do
      session
      |> click_button("Apply filters")
      |> wait_async()
    end

    test "the list view has the customize-feed widget in the sidebar and no Filters button, with the rows that cannot change a list of events hidden",
         %{conn: conn, me: me} do
      event!(me, "Harvest Supper", hours(48), hours(50))

      conn
      |> visit("/events")
      # control: the page lists
      |> assert_has("[data-id=event_preview]", text: "Harvest Supper")
      |> assert_has("[data-role=feed_preferences_widget]")
      |> refute_has("[data-role=toggle_filters]")
      # events are not replies, nor group activities, but they are shared as boosts
      |> refute_has("[data-role=feed_override_toggle][name='scope[group_activity]']")
      |> refute_has("[data-role=feed_override_toggle][name='scope[replies]']")
      |> assert_has("[data-role=feed_override_toggle][name='scope[boosts]']")
      # Happening and Nearby are above "More filters", and not in it
      |> assert_has("[data-role=feed_top_filters] [data-row=happening]")
      |> assert_has("[data-role=feed_top_filters] [data-row=nearby]")
      |> open_filters()
      |> refute_has("[data-role=feed_advanced_filters_wrapper] [data-row=happening]")
      |> refute_has("[data-role=feed_advanced_filters_wrapper] [data-row=nearby]")
      |> assert_has("[data-role=feed_advanced_filters_wrapper] [data-row=time_range]")
      |> refute_has("[data-row=object_types]")
      |> refute_has("[data-row=activity_types]")
      |> refute_has("[data-row=media_types]")
    end

    test "choosing a value in the Happening row above \"More filters\" narrows the list at once, with no Apply",
         %{conn: conn, me: me} do
      event!(me, "Running Fair", hours(-1), hours(1))
      event!(me, "Later Supper", hours(48), hours(50))

      conn
      |> visit("/events")
      |> wait_async()
      # control: both are listed before choosing
      |> assert_has("[data-id=event_preview]", text: "Running Fair")
      |> assert_has("[data-id=event_preview]", text: "Later Supper")
      |> refute_has("[data-role=feed_top_filters] [data-role=apply_filters]")
      |> unwrap(fn view ->
        view
        |> Phoenix.LiveViewTest.element(
          "[data-role=feed_top_filters] [data-row=happening] form[phx-change]"
        )
        |> Phoenix.LiveViewTest.render_change(%{"happening" => "current"})
      end)
      |> wait_async()
      |> assert_has("[data-id=event_preview]", text: "Running Fair")
      |> refute_has("[data-id=event_preview]", text: "Later Supper")
    end

    test "the Happening and Nearby rows are above \"More filters\" in the tile view too, with the Nearby row's location hook and place input",
         %{conn: conn, me: me} do
      event!(me, "Harvest Supper", hours(48), hours(50))

      conn
      |> visit("/events")
      |> within("[data-id=events_layout]", &choose(&1, "Tiles"))
      |> assert_has("[data-id=event_preview][data-layout=tile]", text: "Harvest Supper")
      |> wait_async()
      |> click_button("[data-role=toggle_filters]", "Filters")
      |> assert_has(
        "[data-role=events_filters] [data-role=feed_top_filters] [data-row=happening]"
      )
      |> assert_has("[data-role=events_filters] [data-role=feed_top_filters] [data-row=nearby]")
      |> assert_has("[data-row=nearby] [data-role=detect_location]")
      |> assert_has("[data-row=nearby] input[name=place]")
      |> assert_has("[data-row=nearby] [phx-hook]")
      |> click_button("[data-role=events_filters] [data-role=open_modal]", "More filters")
      |> refute_has("[data-role=feed_advanced_filters_wrapper] [data-row=happening]")
      |> refute_has("[data-role=feed_advanced_filters_wrapper] [data-row=nearby]")
    end

    test "the tile view has a Filters button that opens the same widget inline, and its Nearby row narrows the list",
         %{conn: conn, me: me} do
      {:ok, _} =
        Bonfire.Common.Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
          current_user: me,
          scope: :user
        )

      event!(me, "Near Barn", hours(24), nil, %{
        place: %{name: "The Barn", lat: 50.45, long: -3.684}
      })

      event!(me, "Far Moor", hours(48), nil, %{
        place: %{name: "The Moor", lat: 50.88, long: -3.684}
      })

      conn
      |> visit("/events")
      # chosen in the layout dropdown, which saves it (as the viewer's other settings stay)
      |> within("[data-id=events_layout]", &choose(&1, "Tiles"))
      |> assert_has("[data-id=event_preview][data-layout=tile]", text: "Far Moor")
      |> refute_has("[data-role=feed_preferences_widget]")
      |> open_inline_filters()
      |> assert_has("[data-role=events_filters] [data-role=feed_preferences_widget]")
      |> unwrap(fn view ->
        view
        |> Phoenix.LiveViewTest.element("[data-row=nearby] form[phx-change]")
        |> Phoenix.LiveViewTest.render_change(%{"radius" => "10", "include_no_place" => "true"})
      end)
      |> apply_filters()
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> refute_has("[data-id=event_preview]", text: "Far Moor")
    end

    test "the map view has a Filters button, and a radius leaves the near event's marker and drops the far one",
         %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")

      {:ok, _} =
        Bonfire.Common.Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
          current_user: me,
          scope: :user
        )

      event!(me, "Near Barn", hours(24), nil, %{
        place: %{name: "The Barn", lat: 50.45, long: -3.684}
      })

      event!(me, "Far Moor", hours(48), nil, %{
        place: %{name: "The Moor", lat: 50.88, long: -3.684}
      })

      markers = fn session ->
        session
        |> unwrap(fn view ->
          html = Phoenix.LiveViewTest.render(view)
          send(self(), {:markers, marker_popups(html)})
          html
        end)
        |> then(fn session ->
          assert_received {:markers, popups}
          {session, popups}
        end)
      end

      {session, popups} = conn |> visit("/events/map") |> wait_async() |> markers.()
      # control: both are on the map before choosing
      assert popups =~ "Near Barn"
      assert popups =~ "Far Moor"

      {_session, popups} =
        session
        |> open_inline_filters()
        |> unwrap(fn view ->
          view
          |> Phoenix.LiveViewTest.element("[data-row=nearby] form[phx-change]")
          |> Phoenix.LiveViewTest.render_change(%{"radius" => "10", "include_no_place" => "true"})
        end)
        |> apply_filters()
        |> markers.()

      assert popups =~ "Near Barn"
      refute popups =~ "Far Moor"
    end

    defp marker_popups(html) do
      html
      |> Floki.parse_document!()
      |> Floki.find("[data-id=events_map] leaflet-marker")
      |> Enum.flat_map(&Floki.attribute(&1, "popup"))
      |> Enum.join(" ")
    end

    # the map shows upcoming events only, so it has no time menu
    test "the map view shows no Past choice; the list and tile views do", %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")
      event!(me, "Harvest Supper", hours(48), nil)

      conn
      |> visit("/events")
      |> assert_has("[data-role=events_time_menu] a", text: "Past")

      conn
      |> visit("/events/map")
      |> refute_has("[data-role=events_time_menu]")
    end

    test "choosing a radius in the Nearby row lists only the events within it, with the ones with no place; a far one comes back with a wider radius",
         %{conn: conn, me: me} do
      # Totnes, saved as the viewer's location
      {:ok, _} =
        Bonfire.Common.Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
          current_user: me,
          scope: :user
        )

      # about 2 km and about 50 km north
      event!(me, "Near Barn", hours(24), nil, %{
        place: %{name: "The Barn", lat: 50.45, long: -3.684}
      })

      event!(me, "Far Moor", hours(48), nil, %{
        place: %{name: "The Moor", lat: 50.88, long: -3.684}
      })

      choose_radius = fn session, radius ->
        session
        |> unwrap(fn view ->
          view
          |> Phoenix.LiveViewTest.element("[data-row=nearby] form[phx-change]")
          |> Phoenix.LiveViewTest.render_change(%{
            "radius" => radius,
            "include_no_place" => "true"
          })
        end)
        |> apply_filters()
      end

      conn
      |> visit("/events")
      # control: both are listed before choosing
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> assert_has("[data-id=event_preview]", text: "Far Moor")
      |> open_filters()
      |> choose_radius.("10")
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> refute_has("[data-id=event_preview]", text: "Far Moor")
      |> choose_radius.("60")
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> assert_has("[data-id=event_preview]", text: "Far Moor")
    end

    test "the sort row offers Soonest first, which is the page's own order: the day headings show with it, and not with another sort",
         %{conn: conn, me: me} do
      event!(me, "Second Thing", hours(72), nil)
      event!(me, "First Thing", hours(24), nil)

      conn
      |> visit("/events")
      |> wait_async()
      |> assert_has("select[name=feed_order] option[value=starts_at][selected]",
        text: "Soonest first"
      )
      |> assert_has("[data-role=events_day]")
      |> select("Sort", option: "Newest first")
      |> wait_async()
      |> assert_has("[data-id=event_preview]", text: "First Thing")
      |> assert_has("[data-id=event_preview]", text: "Second Thing")
      |> refute_has("[data-role=events_day]")
      |> select("Sort", option: "Soonest first")
      |> wait_async()
      |> assert_has("[data-role=events_day]")
    end

    test "the map's filters have no sort row, and its markers stay in start order whatever sort is sent; the list's sidebar keeps the row",
         %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")

      geo =
        Bonfire.Geolocate.Simulate.fake_geolocation!(me, nil, %{
          name: "The Barn",
          lat: 45.07,
          long: 7.69
        })

      place = %{primary_geolocation: %{geolocation_id: geo.id}}
      event!(me, "Second Thing", hours(72), nil, place)
      event!(me, "First Thing", hours(24), nil, place)

      conn
      |> visit("/events")
      |> wait_async()
      |> assert_has("[data-role=feed_preferences_widget] select[name=feed_order]")

      conn
      |> visit("/events/map")
      |> wait_async()
      |> open_inline_filters()
      |> assert_has("[data-role=events_filters] [data-role=feed_preferences_widget]")
      |> refute_has("select[name=feed_order]")

      {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, "/events/map")
      html = Phoenix.LiveViewTest.render_hook(view, "set_feed_order", %{"feed_order" => "oldest"})

      # (created in the other order, so a sort by creation would put Second Thing first)
      popups =
        html
        |> Floki.parse_document!()
        |> Floki.find("[data-id=events_map] leaflet-marker")
        |> Enum.flat_map(&Floki.attribute(&1, "popup"))

      assert [first, second] = popups
      assert first =~ "First Thing"
      assert second =~ "Second Thing"
    end
  end

  describe "my events" do
    defp other_user!, do: fake_user!(fake_account!())

    defp follow!(me, other), do: {:ok, _} = Bonfire.Social.Graph.Follows.follow(me, other)

    defp tab_labels(html, row) do
      html
      |> Floki.parse_document!()
      |> Floki.find("[data-role=#{row}] [role=tab]")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
    end

    # the choices of the Upcoming / Past chip menu
    defp time_labels(html) do
      html
      |> Floki.parse_document!()
      |> Floki.find("[data-role=events_time_menu] a")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
    end

    test "the top tabs are Discover and My events, and the time menu Upcoming and Past; guests get no My events, and are sent to sign in from its page",
         %{conn: conn, me: me} do
      # an upcoming event, so Discover stays on its upcoming list
      event!(me, "Harvest Supper", hours(48), nil)

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events")
      assert tab_labels(html, "events_tabs") == ["Discover", "My events"]
      assert time_labels(html) == ["Upcoming", "Past"]

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events/my/past")
      assert tab_labels(html, "events_tabs") == ["Discover", "My events"]

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn(), "/events")
      assert tab_labels(html, "events_tabs") == ["Discover"]
      assert time_labels(html) == ["Upcoming", "Past"]

      guest_status = conn() |> Phoenix.ConnTest.get("/events/my") |> Map.fetch!(:status)
      assert guest_status in [301, 302]
    end

    test "on the map, the tabs keep the map (Discover and My events), and the map has no time menu",
         %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")
      event!(me, "Harvest Supper", hours(48), nil)

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events/map")
      assert time_labels(html) == []

      conn
      |> visit("/events/map")
      |> click_link("[data-role=events_tabs] a", "My events")
      |> assert_path("/events/my/map")
      |> click_link("[data-role=events_tabs] a", "Discover")
      |> assert_path("/events/map")

      # control: on the list view the same links do not end in /map
      conn
      |> visit("/events")
      |> assert_has("[data-role=events_tabs] a[href='/events/my']")
      |> refute_has("[data-role=events_tabs] a[href$='/map']")
      |> refute_has("[data-role=events_time_menu] a[href$='/map']")

      conn
      |> visit("/events/map")
      |> assert_has("[data-role=events_tabs] a[href='/events/my/map']")
    end

    test "lists the upcoming events of people I follow and my own, not those of a stranger (which Discover lists)",
         %{conn: conn, me: me} do
      friend = other_user!()
      stranger = other_user!()
      follow!(me, friend)

      event!(friend, "Friend Gathering", hours(24), nil)
      event!(me, "My Own Gathering", hours(48), nil)
      event!(stranger, "Stranger Gathering", hours(30), nil)

      # control: discover lists all three
      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview]", text: "Stranger Gathering")
      |> assert_has("[data-id=event_preview]", text: "Friend Gathering")

      conn
      |> visit("/events/my")
      |> wait_async()
      |> assert_has("[data-id=event_preview]", text: "Friend Gathering")
      |> assert_has("[data-id=event_preview]", text: "My Own Gathering")
      |> refute_has("[data-id=event_preview]", text: "Stranger Gathering")
      |> assert_has("[data-role=events_day]")
    end

    test "the category chips on My events are those of my own list: a stranger's category is a chip on Discover only, a followed person's on both",
         %{conn: conn, me: me} do
      friend = other_user!()
      stranger = other_user!()
      follow!(me, friend)

      strangers_topic = fake_category!(stranger, nil, %{type: :topic, name: "Strangerjazz"})
      friends_topic = fake_category!(friend, nil, %{type: :topic, name: "Friendpottery"})

      event!(stranger, "Stranger Gig", hours(30), nil, %{tags: [strangers_topic]})
      event!(friend, "Friend Class", hours(24), nil, %{tags: [friends_topic]})

      # the chips are cached, so not from an earlier test's events
      Events.category_facets(:upcoming, cache: :reset)
      Events.category_facets_my(me, :upcoming, cache: :reset)

      # positive first: Discover has the stranger's category
      conn
      |> visit("/events")
      |> wait_async()
      |> assert_has("[data-id=events_categories] a", text: "Strangerjazz")
      |> assert_has("[data-id=events_categories] a", text: "Friendpottery")

      conn
      |> visit("/events/my")
      |> wait_async()
      |> assert_has("[data-id=events_categories] a", text: "Friendpottery")
      |> refute_has("[data-id=events_categories] a", text: "Strangerjazz")
    end

    test "/events/my/past lists my past events and those of people I follow, not upcoming ones or a stranger's",
         %{conn: conn, me: me} do
      friend = other_user!()
      stranger = other_user!()
      follow!(me, friend)

      event!(friend, "Friend Old Fair", hours(-72), hours(-70))
      event!(me, "My Old Fair", hours(-96), hours(-94))
      event!(stranger, "Stranger Old Fair", hours(-48), hours(-46))
      event!(me, "My Next Fair", hours(48), nil)

      conn
      |> visit("/events/past")
      |> assert_has("[data-id=event_preview]", text: "Stranger Old Fair")

      conn
      |> visit("/events/my/past")
      |> wait_async()
      |> assert_has("[data-id=event_preview]", text: "Friend Old Fair")
      |> assert_has("[data-id=event_preview]", text: "My Old Fair")
      |> refute_has("[data-id=event_preview]", text: "Stranger Old Fair")
      |> refute_has("[data-id=event_preview]", text: "My Next Fair")
    end

    test "with no upcoming events, My events says so and stays, where Discover goes to the past ones",
         %{conn: conn, me: me} do
      event!(me, "My Old Fair", hours(-96), hours(-94))

      conn
      |> visit("/events/my")
      |> wait_async()
      |> assert_path("/events/my")
      |> assert_has("[data-id=events_empty]", text: "No upcoming events")

      # control: Discover, with no upcoming events, goes to the past ones
      conn
      |> visit("/events")
      |> assert_path("/events/past")
    end

    test "load more on My events lists the events after the first page, once each, in the order of their start dates",
         %{conn: conn, me: me} do
      friend = other_user!()
      follow!(me, friend)

      event!(friend, "Third Thing", hours(72), nil)
      event!(me, "Fifth Thing", hours(120), nil)
      event!(friend, "First Thing", hours(24), nil)
      event!(me, "Fourth Thing", hours(96), nil)
      event!(friend, "Second Thing", hours(48), nil)

      {:ok, view, html} = Phoenix.LiveViewTest.live(conn, "/events/my")
      assert [_, after_first] = String.split(html, "First Thing", parts: 2)
      assert after_first =~ "Second Thing"
      refute html =~ "Third Thing"

      for _ <- 1..2,
          do:
            view
            |> Phoenix.LiveViewTest.element("button", "Load more")
            |> Phoenix.LiveViewTest.render_click()

      html = Phoenix.LiveViewTest.render(view)
      names = Regex.scan(~r/(First|Second|Third|Fourth|Fifth) Thing/, html)

      assert names |> Enum.map(&hd/1) |> Enum.uniq() ==
               ["First Thing", "Second Thing", "Third Thing", "Fourth Thing", "Fifth Thing"]

      assert html |> Floki.parse_document!() |> Floki.find("[data-id=event_preview]") |> length() ==
               5
    end

    test "the Filters panel works on My events: a radius lists only the events within it", %{
      conn: conn,
      me: me
    } do
      {:ok, _} =
        Bonfire.Common.Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
          current_user: me,
          scope: :user
        )

      friend = other_user!()
      follow!(me, friend)

      event!(friend, "Near Barn", hours(24), nil, %{
        place: %{name: "The Barn", lat: 50.45, long: -3.684}
      })

      event!(me, "Far Moor", hours(48), nil, %{
        place: %{name: "The Moor", lat: 50.88, long: -3.684}
      })

      conn
      |> visit("/events/my")
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> assert_has("[data-id=event_preview]", text: "Far Moor")
      |> open_filters()
      |> unwrap(fn view ->
        view
        |> Phoenix.LiveViewTest.element("[data-row=nearby] form[phx-change]")
        |> Phoenix.LiveViewTest.render_change(%{"radius" => "10", "include_no_place" => "true"})
      end)
      |> apply_filters()
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> refute_has("[data-id=event_preview]", text: "Far Moor")
    end

    test "an event made by one followed person and boosted by another is listed once", %{
      conn: conn,
      me: me
    } do
      friend = other_user!()
      booster = other_user!()
      follow!(me, friend)
      follow!(me, booster)

      event = event!(friend, "Shared Gathering", hours(24), nil)
      {:ok, _} = Bonfire.Social.Boosts.boost(booster, event.id)
      {:ok, _} = Bonfire.Social.Boosts.boost(me, event.id)

      {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, "/events/my")
      html = Phoenix.LiveViewTest.render(view)

      assert html |> Floki.parse_document!() |> Floki.find("[data-id=event_preview]") |> length() ==
               1
    end

    test "an event a followed person boosted is listed, and turning Boosts off in the widget hides it",
         %{conn: conn, me: me} do
      friend = other_user!()
      stranger = other_user!()
      follow!(me, friend)

      event = event!(stranger, "Shared Gathering", hours(24), nil)
      event!(friend, "Friend Own Gathering", hours(48), nil)
      {:ok, _} = Bonfire.Social.Boosts.boost(friend, event.id)

      conn
      |> visit("/events/my")
      |> wait_async()
      |> assert_has("[data-id=event_preview]", text: "Shared Gathering")
      |> assert_has("[data-id=event_preview]", text: "Friend Own Gathering")
      |> unwrap(fn view ->
        view
        |> Phoenix.LiveViewTest.element("[data-role=feed_override_toggle][name='scope[boosts]']")
        |> Phoenix.LiveViewTest.render_click()
      end)
      |> wait_async()
      |> assert_has("[data-id=event_preview]", text: "Friend Own Gathering")
      |> refute_has("[data-id=event_preview]", text: "Shared Gathering")
    end

    test "the chips and the tabs keep to My events and its time", %{conn: conn, me: me} do
      Events.category_facets(:upcoming, cache: :reset)
      topic = fake_category!(me, nil, %{type: :topic, name: "Jazz"})
      event!(me, "Jazz Night", hours(24), nil, %{tags: [topic]})

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events/my")
      doc = Floki.parse_document!(html)
      hrefs = doc |> Floki.find("[data-role=events_time_menu] a") |> Floki.attribute("href")
      assert hrefs == ["/events/my", "/events/my/past"]

      conn
      |> visit("/events/my")
      |> wait_async()
      |> assert_has("[data-id=events_categories] a[href^='/events/my/category/']")

      conn
      |> visit("/events/my/category/#{topic.character.username}")
      |> wait_async()
      |> assert_has("[data-id=event_preview]", text: "Jazz Night")
    end
  end
end
