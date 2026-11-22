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

  test "lists an upcoming event, with its primary image as its cover and its other media listed, and not one that has ended",
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
    |> assert_has("[data-id=multimedia_list]")
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
    assert ["Friday, September 20, 2030", "Saturday, September 21, 2030"] ==
             doc |> Floki.find("[data-role=events_day]") |> Enum.map(&String.trim(Floki.text(&1)))

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
      geo = Bonfire.Geolocate.Simulate.fake_geolocation!(me, nil, %{name: "The Old Barn"})

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

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events/map")

      [popup] =
        html
        |> Floki.parse_document!()
        |> Floki.find("[data-id=events_map] leaflet-marker")
        |> Enum.map(&(Floki.attribute(&1, "popup") |> List.first()))

      assert popup =~ "Harvest Supper"
      assert popup =~ "The Old Barn"
      assert popup =~ "/discussion/#{event.id}"

      # not saved: a new visit is in the list again
      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview][data-layout=list]")
    end

    test "without a maps key, the dropdown offers no map, and the map page says maps are not set up",
         %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "")
      event!(me, "Harvest Supper", hours(48), nil)

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
end
