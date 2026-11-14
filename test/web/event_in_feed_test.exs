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

    geo = Bonfire.Geolocate.Simulate.fake_geolocation!(user, nil, %{name: "The Old Barn"})

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
      text: "The Old Barn"
    )
    |> assert_has_or_open_browser("[data-id=event_preview]", text: "Bring a dish")
    # the card leads to the event's own page
    |> assert_has_or_open_browser("[data-id=event_preview] a[href='/discussion/#{event.id}']")
  end

  test "an event's primary image is its cover, and its other media are listed" do
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
    |> assert_has_or_open_browser("[data-id=multimedia_list]")
  end
end
