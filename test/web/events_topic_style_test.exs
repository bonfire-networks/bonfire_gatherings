defmodule Bonfire.Gatherings.Web.EventsTopicStyleTest do
  @moduledoc """
  The colour and icon of a topic (`Bonfire.Classify.Appearance`) on the `/events` page: on its chip, on the badge of the cards of its events, and as the colour of a card that has no image.
  """
  use Bonfire.Gatherings.ConnCase, async: false
  import PhoenixTest
  import Bonfire.Classify.Simulate
  use Bonfire.Common.Utils
  use Bonfire.Common.Repo

  alias Bonfire.Classify.Appearance
  alias Bonfire.Common.Swatches
  alias Bonfire.Gatherings.Events
  alias Bonfire.Gatherings.Web.Preview.EventCoverLive

  setup do
    account = fake_account!()
    me = fake_user!(account)
    # the chips are cached for the instance, so not from an earlier test's events
    Events.category_facets(:upcoming, cache: :reset)
    {:ok, conn: conn(user: me, account: account), me: me}
  end

  defp hours(n), do: DateTime.add(DateTime.utc_now(), n * 3600, :second)

  defp event!(user, name, extra \\ %{}) do
    {:ok, event} =
      Events.create(
        current_user: user,
        boundary: "public",
        event_attrs:
          Map.merge(
            %{
              post_content: %{name: name},
              time_span: %{has_beginning: hours(24), has_end: hours(26)}
            },
            extra
          )
      )

    event
  end

  defp topic!(me, name, opts \\ []) do
    topic = fake_category!(me, opts[:parent], %{type: :topic, name: name})

    if swatch = opts[:colour],
      do: {:ok, _} = Appearance.set_colour(topic, swatch, current_user: me)

    if icon = opts[:icon], do: {:ok, _} = Appearance.set_icon(topic, icon, current_user: me)
    topic
  end

  # the topic of a FEP-8a8e category (already reserved, archived, by the fixtures), brought back as an event that names it does
  defp music_topic!(me, opts \\ []) do
    {:ok, topic} =
      Bonfire.Classify.Categories.get_or_create_topic(
        %{name: "Music", username: "music_events"},
        me
      )

    # its moderators administer it, not the one who brought it back
    if swatch = opts[:colour],
      do: {:ok, _} = Appearance.set_colour(topic, swatch, skip_boundary_check: true)

    topic
  end

  describe "the chips" do
    test "a chip has its topic's swatch and icon; a topic with neither has the hashed swatch and no icon",
         %{conn: conn, me: me} do
      jazz = topic!(me, "Jazz", colour: "violet", icon: "ph:music-notes-fill")
      pottery = topic!(me, "Pottery")
      event!(me, "Jazz Night", %{tags: [jazz]})
      event!(me, "Pottery Class", %{tags: [pottery]})

      conn
      |> visit("/events")
      |> assert_has("[data-id=events_categories] a.topic-violet [iconify='ph:music-notes-fill']")
      |> assert_has("[data-id=events_categories] a.topic-violet", text: "Jazz")
      |> assert_has(
        "[data-id=events_categories] a.#{Swatches.class(Swatches.from_seed(id(pottery)))}",
        text: "Pottery"
      )
      |> refute_has(
        "[data-id=events_categories] a[href='/events/category/#{pottery.character.username}'] [iconify]"
      )
    end

    test "a label's chip shows its icon in place of the tag", %{conn: conn, me: me} do
      {:ok, label} =
        Bonfire.Classify.Categories.get_or_create_topic(
          %{
            name: "Family friendly",
            username: "family_friendly_#{System.unique_integer([:positive])}",
            type: :label
          },
          me
        )

      {:ok, _} = Appearance.set_icon(label, "ph:baby-fill", current_user: me)
      event!(me, "Kids Day", %{tags: [label]})

      conn
      |> visit("/events")
      |> assert_has("[data-id=events_labels] a [iconify='ph:baby-fill']")
      |> refute_has("[data-id=events_labels] a [iconify='ph:tag-fill']")
    end
  end

  describe "a topic's uploaded image" do
    # uploads are resized with vips, which CI doesn't have
    @tag Bonfire.Common.RuntimeConfig.skip_in_ci()
    test "is never shown on a chip or a badge: the picked icon, else the neutral one",
         %{conn: conn, me: me} do
      with_icon = topic!(me, "Jazz", icon: "ph:music-notes-fill")
      image_only = topic!(me, "Pottery")

      for topic <- [with_icon, image_only] do
        {:ok, avatar} =
          Bonfire.Files.Simulation.fake_upload(
            Bonfire.Files.Simulation.image_file(),
            Bonfire.Files.IconUploader,
            me
          )

        {:ok, _} =
          Bonfire.Classify.Categories.update(me, topic, %{
            "profile" => %{"icon" => avatar, "icon_id" => avatar.id}
          })
      end

      event!(me, "Jazz Night", %{tags: [with_icon]})
      event!(me, "Pottery Class", %{tags: [image_only]})

      conn
      |> visit("/events")
      # the icon, for the one that picked one
      |> assert_has("[data-id=events_categories] a [iconify='ph:music-notes-fill']")
      |> assert_has(
        "[data-id=event_preview] [data-role=event_badge] [iconify='ph:music-notes-fill']"
      )
      # the one with only an image is there by name, with no picture
      |> assert_has("[data-id=events_categories] a", text: "Pottery")
      |> assert_has("[data-id=event_preview] [data-role=event_badge]", text: "Pottery")
      |> refute_has("[data-id=events_categories] a img")
      |> refute_has("[data-id=event_preview] [data-role=event_badge] img")
      |> refute_has("[data-id=events_labels] img")
    end
  end

  describe "a card's badge" do
    test "shows the topic's icon before its name, and only the name for a topic with no icon",
         %{conn: conn, me: me} do
      jazz = topic!(me, "Jazz", icon: "ph:music-notes-fill")
      pottery = topic!(me, "Pottery")
      event!(me, "Jazz Night", %{tags: [jazz]})
      event!(me, "Pottery Class", %{tags: [pottery]})

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview] [data-role=event_badge]", text: "Jazz")
      |> assert_has(
        "[data-id=event_preview] [data-role=event_badge] [iconify='ph:music-notes-fill']"
      )
      |> assert_has("[data-id=event_preview] [data-role=event_badge]", text: "Pottery")
      # the one icon on the page is Jazz's
      |> refute_has("[data-id=event_preview] [data-role=event_badge] [iconify='ph:tag-fill']")
    end

    test "badge_names/2 gives the name, icon and swatch of what is loaded, and only the name when settings are not",
         %{me: me} do
      jazz = topic!(me, "Jazz", colour: "teal", icon: "ph:music-notes-fill")
      event = event!(me, "Jazz Night", %{tags: [jazz]})

      with_settings =
        repo().maybe_preload(event, tags: [:profile] ++ Appearance.preloads())

      assert [%{name: "Jazz", icon: "ph:music-notes-fill", colour: "teal"}] =
               EventCoverLive.badge_names(with_settings)

      # tags loaded with their names only, as a feed that preloaded `tags: [:profile]` has them: no icon and no raise
      names_only = repo().maybe_preload(event, tags: [:profile])

      assert [%{name: "Jazz", icon: nil}] = EventCoverLive.badge_names(names_only)

      # tags not loaded at all: nothing, so the badge says "Event"
      assert [] = EventCoverLive.badge_names(repo().reload(event))
    end
  end

  describe "a row of the list view with no image" do
    test "has a placeholder in the swatch and icon of its main topic, and the neutral one with no topic",
         %{conn: conn, me: me} do
      music = music_topic!(me, colour: "violet")
      {:ok, _} = Appearance.set_icon(music, "ph:music-notes-fill", skip_boundary_check: true)
      event!(me, "Gig Night", %{tags: [music]})
      event!(me, "Untagged Thing", %{})

      conn
      |> visit("/events")
      |> assert_has("[data-layout=list] [data-role=event_placeholder].topic-violet")
      |> assert_has(
        "[data-layout=list] [data-role=event_placeholder] [iconify='ph:music-notes-fill']"
      )
      # only the tagged one has its colour, the other is neutral (control)
      |> assert_has("[data-layout=list] [data-role=event_placeholder].topic-violet", count: 1)
      |> assert_has("[data-layout=list] [data-role=event_placeholder].bg-base-200", count: 1)
      |> assert_has("[data-layout=list] [data-role=event_placeholder]", count: 2)
    end

    # control: the same topic and colour, but with an image, so no square
    @tag Bonfire.Common.RuntimeConfig.skip_in_ci()
    test "an event with an image has no square, though its topic has a colour", %{
      conn: conn,
      me: me
    } do
      music = music_topic!(me, colour: "violet")

      {:ok, cover} =
        Bonfire.Files.upload(
          Bonfire.Files.ImageUploader,
          me,
          Bonfire.Files.Simulation.image_file(),
          %{metadata: %{"primary_image" => "true"}}
        )

      event!(me, "Gig With Poster", %{tags: [music], uploaded_media: [cover]})

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview][data-layout=list]", text: "Gig With Poster")
      |> refute_has("[data-layout=list] [data-role=event_placeholder]")
      |> refute_has("[data-layout=list] .topic-violet")
    end
  end

  # a row (the list's default) has its own placeholder, tested above, so these show the events as tiles
  describe "a card with no image" do
    setup do
      Process.put(
        [:bonfire_gatherings, Bonfire.Gatherings.Events, :custom_preview],
        Bonfire.Gatherings.Web.Preview.EventTileLive
      )

      :ok
    end

    test "takes the swatch of its topic, or the hashed one when it has none (its parent is not loaded on the page, so its colour is not inherited)",
         %{conn: conn, me: me} do
      parent = topic!(me, "Gigs", colour: "red")
      child = topic!(me, "Folk gigs", parent: parent)
      event!(me, "Folk Night", %{tags: [child]})

      hashed = Swatches.from_seed(child.id)

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview] [data-role=event_placeholder].topic-#{hashed}")

      # control: a topic with its own colour shows it
      own = topic!(me, "Own colour gigs", colour: "violet", parent: parent)
      event!(me, "Own Night", %{tags: [own]})

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview] [data-role=event_placeholder].topic-violet")
    end

    test "is neutral with no topic, and so is one tagged only with the topic the page is filtered by",
         %{conn: conn, me: me} do
      jazz = topic!(me, "Jazz", colour: "violet")
      event!(me, "Untagged Thing", %{})
      event!(me, "Jazz Night", %{tags: [jazz]})

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview] [data-role=event_placeholder].topic-violet")
      # the one with no topic keeps the neutral placeholder
      |> assert_has("[data-id=event_preview] [data-role=event_placeholder].bg-base-200")

      conn
      |> visit("/events/category/#{jazz.character.username}")
      |> assert_has("[data-id=event_preview]", text: "Jazz Night")
      |> refute_has("[data-id=event_preview] [data-role=event_placeholder].topic-violet")
      |> assert_has("[data-id=event_preview] [data-role=event_placeholder].bg-base-200")
    end

    test "uses the event's FEP category if it has one, else the first of its topics",
         %{conn: conn, me: me} do
      zebra = topic!(me, "Zebra", colour: "blue")
      music = music_topic!(me, colour: "violet")
      # the FEP category is the main one though it comes second
      event!(me, "Zebra Concert", %{tags: [zebra, music]})

      conn
      |> visit("/events")
      |> assert_has("[data-id=event_preview] [data-role=event_placeholder].topic-violet")
      |> refute_has("[data-id=event_preview] [data-role=event_placeholder].topic-blue")
    end

    test "uses the main one among the others on a page filtered by a topic", %{conn: conn, me: me} do
      zebra = topic!(me, "Zebra", colour: "blue")
      music = music_topic!(me, colour: "violet")
      event!(me, "Zebra Concert", %{tags: [zebra, music]})

      conn
      |> visit("/events/category/music_events")
      |> assert_has("[data-id=event_preview] [data-role=event_placeholder].topic-blue")
    end

    test "a card whose tags are not loaded shows the neutral placeholder, without raising",
         %{me: me} do
      jazz = topic!(me, "Jazz", colour: "violet")
      event = event!(me, "Jazz Night", %{tags: [jazz]}) |> repo().reload()

      html =
        Phoenix.LiveViewTest.render_component(
          &Bonfire.Gatherings.Web.Preview.EventCoverLive.render/1,
          object: event,
          primary_image: nil,
          __context__: %{}
        )

      assert html =~ "event_placeholder"
      assert html =~ "bg-base-200"
      refute html =~ "topic-violet"
    end
  end

  describe "the events map's markers" do
    defp placed_event!(me, name, extra \\ %{}) do
      geo =
        Bonfire.Geolocate.Simulate.fake_geolocation!(me, nil, %{
          name: "Place of #{name}",
          lat: 45.07,
          long: 7.69
        })

      event!(me, name, Map.put(extra, :primary_geolocation, %{geolocation_id: geo.id}))
    end

    test "map_markers/1 gives a marker the swatch class and icon of its event's main topic, and neither with no topic",
         %{me: me} do
      jazz = topic!(me, "Jazz", colour: "violet", icon: "ph:music-notes-fill")
      tagged = placed_event!(me, "Jazz Night", %{tags: [jazz]})
      untagged = placed_event!(me, "Untagged Thing")

      events =
        repo().maybe_preload(
          [tagged, untagged],
          Bonfire.Gatherings.Web.Preview.EventLive.preloads() ++
            [tags: [:profile, :character, :settings]]
        )

      markers = Bonfire.Gatherings.Web.EventsLive.map_markers(events)

      assert %{class: "topic-violet", icon: "ph:music-notes-fill"} =
               Enum.find(markers, &(&1.name =~ "Jazz Night"))

      plain = Enum.find(markers, &(&1.name =~ "Untagged Thing"))
      refute Map.get(plain, :class)
      refute Map.get(plain, :icon)
    end

    test "the rendered map carries them on the marker, and an untagged event's marker has none",
         %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")
      jazz = topic!(me, "Jazz", colour: "violet", icon: "ph:music-notes-fill")
      placed_event!(me, "Jazz Night", %{tags: [jazz]})
      placed_event!(me, "Untagged Thing")

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events/map")

      markers =
        html |> Floki.parse_document!() |> Floki.find("[data-id=events_map] leaflet-marker")

      by_name = fn name ->
        Enum.find(markers, &(Floki.attribute(&1, "popup") |> List.first() =~ name))
      end

      assert Floki.attribute(by_name.("Jazz Night"), "marker-class") == ["topic-violet"]
      assert Floki.attribute(by_name.("Jazz Night"), "marker-icon") == ["ph:music-notes-fill"]
      assert Floki.attribute(by_name.("Untagged Thing"), "marker-class") == []
      assert Floki.attribute(by_name.("Untagged Thing"), "marker-icon") == []
      assert Floki.attribute(by_name.("Untagged Thing"), "marker-image") == []
    end

    defp upload_icon!(me, topic) do
      {:ok, avatar} =
        Bonfire.Files.Simulation.fake_upload(
          Bonfire.Files.Simulation.image_file(),
          Bonfire.Files.IconUploader,
          me
        )

      {:ok, _} =
        Bonfire.Classify.Categories.update(me, topic, %{
          "profile" => %{"icon" => avatar, "icon_id" => avatar.id}
        })
    end

    # uploads are resized with vips, which CI doesn't have
    @tag Bonfire.Common.RuntimeConfig.skip_in_ci()
    test "a marker never has the topic's image, with an icon picked or not, on the rendered map",
         %{conn: conn, me: me} do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")
      with_icon = topic!(me, "Jazz", colour: "violet", icon: "ph:music-notes-fill")
      image_only = topic!(me, "Pottery", colour: "violet")
      upload_icon!(me, with_icon)
      upload_icon!(me, image_only)
      placed_event!(me, "Jazz Night", %{tags: [with_icon]})
      placed_event!(me, "Pottery Class", %{tags: [image_only]})

      {:ok, _view, html} = Phoenix.LiveViewTest.live(conn, "/events/map")

      markers =
        html |> Floki.parse_document!() |> Floki.find("[data-id=events_map] leaflet-marker")

      by_name = fn name ->
        Enum.find(markers, &(Floki.attribute(&1, "popup") |> List.first() =~ name))
      end

      # positive first: both markers are there, the one with an icon carrying it and its swatch
      assert Floki.attribute(by_name.("Jazz Night"), "marker-icon") == ["ph:music-notes-fill"]
      assert Floki.attribute(by_name.("Pottery Class"), "marker-class") == ["topic-violet"]
      assert Floki.attribute(by_name.("Pottery Class"), "marker-icon") == []
      assert Floki.attribute(by_name.("Pottery Class"), "marker-image") == []
      assert Floki.attribute(by_name.("Jazz Night"), "marker-image") == []
    end

    @tag Bonfire.Common.RuntimeConfig.skip_in_ci()
    test "map_markers/1 gives a marker its topic's icon and swatch, and never an image key",
         %{me: me} do
      with_icon = topic!(me, "Jazz", icon: "ph:music-notes-fill")
      image_only = topic!(me, "Pottery")
      plain_topic = topic!(me, "Chess")
      upload_icon!(me, with_icon)
      upload_icon!(me, image_only)

      events =
        repo().maybe_preload(
          [
            placed_event!(me, "Jazz Night", %{tags: [with_icon]}),
            placed_event!(me, "Pottery Class", %{tags: [image_only]}),
            placed_event!(me, "Chess Club", %{tags: [plain_topic]})
          ],
          Bonfire.Gatherings.Web.Preview.EventLive.preloads() ++
            [tags: [:profile, :character, :settings]]
        )

      markers = Bonfire.Gatherings.Web.EventsLive.map_markers(events)
      find = fn name -> Enum.find(markers, &(&1.name =~ name)) end

      assert %{icon: "ph:music-notes-fill"} = find.("Jazz Night")
      refute Map.has_key?(find.("Pottery Class"), :icon)

      for name <- ["Jazz Night", "Pottery Class", "Chess Club"],
          do: refute(Map.has_key?(find.(name), :image))
    end
  end
end
