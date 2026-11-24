defmodule Bonfire.Gatherings.Web.EventInFeedTest do
  @moduledoc """
  A native event in a feed is shown by `Bonfire.Gatherings.Web.Preview.EventLive`, from its mixins: its name, when it happens, where, and its summary.
  """
  use Bonfire.Gatherings.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  import PhoenixTest

  alias Bonfire.Me.Fake

  test "an event in the feed shows its name, time, place and summary" do
    account = Fake.fake_account!()
    user = Fake.fake_user!(account)
    conn = conn(user: user, account: account)

    # `&` and `#` would cut the map link's query short if not encoded
    geo =
      Bonfire.Geolocate.Simulate.fake_geolocation!(user, nil, %{name: "The Old Barn & Mill #2"})

    {:ok, event} =
      Bonfire.Gatherings.Events.create(
        current_user: user,
        boundary: "public",
        event_attrs: %{
          post_content: %{name: "Harvest Supper", summary: "Bring a dish"},
          time_span: %{has_beginning: ~U[2030-09-20 18:00:00Z], has_end: ~U[2030-09-20 22:00:00Z]},
          primary_geolocation: %{geolocation_id: geo.id}
        }
      )

    conn
    |> visit("/feed")
    |> wait_async()
    |> assert_has_or_open_browser("[data-id=event_preview]", text: "Harvest Supper")
    |> assert_has_or_open_browser("[data-id=event_preview] [data-role=event_time]", text: "2030")
    |> assert_has_or_open_browser("[data-id=event_preview] [data-role=event_place]",
      text: "The Old Barn & Mill #2"
    )
    |> assert_has_or_open_browser(
      "[data-id=event_preview] a[href='https://www.openstreetmap.org/search?zoom=6&query=The+Old+Barn+%26+Mill+%232']"
    )
    |> assert_has_or_open_browser("[data-id=event_preview]", text: "Bring a dish")
    # the card leads to the event's own page
    |> assert_has_or_open_browser("[data-id=event_preview] a[href='/discussion/#{event.id}']")
  end

  test "an event's primary image is its cover, and its other media are not listed" do
    account = Fake.fake_account!()
    user = Fake.fake_user!(account)
    conn = conn(user: user, account: account)

    {:ok, cover} =
      Bonfire.Files.upload(
        Bonfire.Files.ImageUploader,
        user,
        Bonfire.Files.Simulation.image_file(),
        %{metadata: %{"primary_image" => "true"}}
      )

    {:ok, other} =
      Bonfire.Files.upload(
        Bonfire.Files.ImageUploader,
        user,
        Bonfire.Files.Simulation.image_file()
      )

    {:ok, event} =
      Bonfire.Gatherings.Events.create(
        current_user: user,
        boundary: "public",
        event_attrs: %{
          post_content: %{name: "Poster Night"},
          time_span: %{has_beginning: ~U[2030-09-20 18:00:00Z]},
          uploaded_media: [cover, other]
        }
      )

    # both are attached to the event, one of them flagged as its cover
    files = Bonfire.Common.Repo.preload(event, [files: [:media]], force: true).files
    assert length(files) == 2
    assert {%{}, [_]} = Bonfire.Files.split_primary_image(files)

    conn
    |> visit("/feed")
    |> wait_async()
    |> assert_has_or_open_browser("[data-id=event_preview] [data-id=event_cover]")
    |> refute_has("[data-id=multimedia_list]")

    # on its own page the image is a media attachment, which opens in full, not a cropped cover
    conn
    |> visit("/discussion/#{event.id}")
    |> wait_async()
    |> assert_has_or_open_browser("[data-id=multimedia_list]")
    |> refute_has("[data-id=event_cover]")
  end

  describe "an event's page, with the links it keeps in extra_info" do
    defp event_with!(user, info, place_name \\ nil) do
      place =
        if place_name do
          geo = Bonfire.Geolocate.Simulate.fake_geolocation!(user, nil, %{name: place_name})
          %{primary_geolocation: %{geolocation_id: geo.id}}
        else
          %{}
        end

      {:ok, event} =
        Bonfire.Gatherings.Events.create(
          current_user: user,
          boundary: "public",
          event_attrs:
            Map.merge(
              %{
                post_content: %{name: "Harvest Supper"},
                time_span: %{has_beginning: ~U[2030-09-20 18:00:00Z]},
                extra_info: %{info: info}
              },
              place
            )
        )

      event
    end

    test "a place named by a URL is shown as a link, a place named otherwise as a map link" do
      account = Fake.fake_account!()
      user = Fake.fake_user!(account)

      url_event = event_with!(user, %{}, "https://meet.jit.si/abc")
      named_event = event_with!(user, %{}, "The Old Barn")

      conn(user: user, account: account)
      |> visit("/discussion/#{url_event.id}")
      |> wait_async()
      |> assert_has_or_open_browser(
        "[data-layout=page] a[data-role=event_place][href='https://meet.jit.si/abc'][target=_blank][rel='noopener nofollow']",
        text: "https://meet.jit.si/abc"
      )
      |> visit("/discussion/#{named_event.id}")
      |> wait_async()
      |> assert_has_or_open_browser(
        "[data-layout=page] a[data-role=event_place][href^='https://www.openstreetmap.org/search']",
        text: "The Old Barn"
      )
    end

    test "the place and the online link are shown together in the where line" do
      account = Fake.fake_account!()
      user = Fake.fake_user!(account)

      event =
        event_with!(
          user,
          %{"online_address" => "https://meet.example.local/room"},
          "The Old Barn"
        )

      conn(user: user, account: account)
      |> visit("/discussion/#{event.id}")
      |> wait_async()
      |> assert_has_or_open_browser("[data-layout=page] [data-role=event_where]", count: 1)
      |> assert_has_or_open_browser(
        "[data-role=event_where] a[data-role=event_place]",
        text: "The Old Barn"
      )
      |> assert_has_or_open_browser(
        "[data-role=event_where] a[data-role=event_online][href='https://meet.example.local/room']"
      )
      |> assert_has("[data-role=event_online]", count: 1)
    end

    test "links to the external participation URL and the online address" do
      account = Fake.fake_account!()
      user = Fake.fake_user!(account)

      event =
        event_with!(user, %{
          "external_participation_url" => "https://tickets.example.local/e/1",
          "online_address" => "https://meet.example.local/room"
        })

      conn(user: user, account: account)
      |> visit("/discussion/#{event.id}")
      |> wait_async()
      |> assert_has_or_open_browser("[data-layout=page]", text: "Harvest Supper")
      |> assert_has_or_open_browser(
        "[data-layout=page] a[data-role=event_register][href='https://tickets.example.local/e/1'][target=_blank][rel='noopener nofollow']"
      )
      |> assert_has_or_open_browser(
        "[data-layout=page] a[data-role=event_online][href='https://meet.example.local/room'][target=_blank][rel='noopener nofollow']"
      )
    end

    test "shows neither link for an event without them" do
      account = Fake.fake_account!()
      user = Fake.fake_user!(account)
      event = event_with!(user, %{})

      conn(user: user, account: account)
      |> visit("/discussion/#{event.id}")
      |> wait_async()
      |> assert_has_or_open_browser("[data-layout=page]", text: "Harvest Supper")
      |> refute_has("[data-role=event_register]")
      |> refute_has("[data-role=event_online]")
    end
  end

  test "the event names its creator only where they are not the activity's subject, already shown as its author" do
    event = %{created: %{creator_id: "ANN", creator: %{id: "ANN", profile: %{name: "Ann"}}}}

    assert Bonfire.Gatherings.Web.Preview.EventLive.host_name(event, %{subject_id: "BOB"}) ==
             "Ann"

    refute Bonfire.Gatherings.Web.Preview.EventLive.host_name(event, %{subject_id: "ANN"})
    # with no activity (eg. a list's row), the creator
    assert Bonfire.Gatherings.Web.Preview.EventLive.host_name(event) == "Ann"
  end
end
