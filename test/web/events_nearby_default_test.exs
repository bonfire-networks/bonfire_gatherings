defmodule Bonfire.Gatherings.Web.EventsNearbyDefaultTest do
  @moduledoc """
  The "Events near me by default" setting: Discover (`/events`, in all its views) starts with the Nearby filter on, at the radius the setting holds (in the viewer's units, 50 for an instance), when the viewer has a saved location. My events ignores it, and so does a viewer with no saved location. A radius picked in the Nearby row is remembered as the setting.
  """
  use Bonfire.Gatherings.ConnCase, async: false
  import PhoenixTest

  alias Bonfire.Common.Settings
  alias Bonfire.Gatherings.Events

  # Totnes
  @here "50.432,-3.684"
  @lat 50.432
  @long -3.684
  # a degree of latitude is about 111.2 km
  @km 1 / 111.2

  setup do
    # pages hold 2 in tests, and each of these lists up to 5
    Process.put([:bonfire, :default_pagination_limit], 10)
    account = fake_account!()
    creator = fake_user!(account)
    {:ok, account: account, creator: creator}
  end

  defp hours(n), do: DateTime.add(DateTime.utc_now(), n * 3600, :second)

  defp event!(user, name, place) do
    {:ok, event} =
      Events.create(
        current_user: user,
        boundary: "public",
        event_attrs:
          Map.merge(
            %{post_content: %{name: name}, time_span: %{has_beginning: hours(48)}},
            if(place, do: %{place: place}, else: %{})
          )
      )

    event
  end

  # a place this many km north of the saved location
  defp north!(user, name, km),
    do: event!(user, name, %{name: name <> " place", lat: @lat + km * @km, long: @long})

  defp viewer!(settings \\ []) do
    user = fake_user!(fake_account!(), %{location: nil})

    Enum.reduce(settings, user, fn {keys, value}, user ->
      {:ok, _} = Settings.put(keys, value, current_user: user, scope: :user)
      Bonfire.Common.Repo.maybe_preload(user, :settings, force: true)
    end)
  end

  defp located(settings \\ []), do: viewer!([{[Bonfire.Geolocate, :location], @here} | settings])

  defp as(user), do: conn(user: user)

  defp page(user, path) do
    user |> as() |> visit(path) |> wait_async()
  end

  defp events!(creator) do
    north!(creator, "Near Barn", 2)
    north!(creator, "Mid Hall", 35)
    north!(creator, "Out Hall", 45)
    north!(creator, "Far Moor", 80)
    event!(creator, "Online Chat", nil)
    :ok
  end

  describe "the default" do
    test "with a saved location the instance default of 50 km applies, keeping online events; with no saved location everything is listed",
         %{creator: creator} do
      events!(creator)

      # control: no saved location, no filter
      viewer!()
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Far Moor")
      |> assert_has("[data-id=event_preview]", text: "Near Barn")

      located()
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> assert_has("[data-id=event_preview]", text: "Mid Hall")
      |> assert_has("[data-id=event_preview]", text: "Online Chat")
      |> refute_has("[data-id=event_preview]", text: "Far Moor")
      # the Nearby row shows it
      |> assert_has("[data-row=nearby]", text: "Within 50 km")
    end

    test "My events ignores it", %{creator: creator} do
      events!(creator)
      user = located()
      # the viewer's own far event, which My events lists
      north!(user, "My Far Gig", 80)

      user
      |> page("/events")
      |> refute_has("[data-id=event_preview]", text: "My Far Gig")

      user
      |> page("/events/my")
      |> assert_has("[data-id=event_preview]", text: "My Far Gig")
      |> refute_has("[data-row=nearby]", text: "Within 50 km")
    end

    test "Anywhere lists everything", %{creator: creator} do
      events!(creator)

      located([{[Bonfire.Gatherings.Events, :default_nearby_radius], "anywhere"}])
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Far Moor")
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
    end

    test "a user's own radius wins over the instance's", %{creator: creator} do
      events!(creator)

      located([{[Bonfire.Gatherings.Events, :default_nearby_radius], "10"}])
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> assert_has("[data-id=event_preview]", text: "Online Chat")
      |> refute_has("[data-id=event_preview]", text: "Mid Hall")
    end

    test "the number is in the viewer's units: 25 for an imperial viewer is 25 mi, about 40 km",
         %{creator: creator} do
      events!(creator)

      located([
        {:measurement_units, :imperial},
        {[Bonfire.Gatherings.Events, :default_nearby_radius], "25"}
      ])
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Mid Hall")
      |> refute_has("[data-id=event_preview]", text: "Out Hall")
      |> assert_has("[data-row=nearby]", text: "Within 25 mi")
    end
  end

  describe "the setting" do
    test "is on the user's settings page, and saving it changes the page", %{creator: creator} do
      events!(creator)
      user = located()

      user
      |> as()
      |> visit("/settings/user/bonfire_gatherings")
      |> assert_has("*", text: "Events near me by default")
      |> select("Events near me by default", option: "Anywhere")

      user
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Far Moor")
    end
  end

  describe "remembering" do
    defp choose_radius(session, radius) do
      session
      |> click_button("[data-role=open_modal]", "More filters")
      |> unwrap(fn view ->
        view
        |> Phoenix.LiveViewTest.element("[data-row=nearby] form[phx-change]")
        |> Phoenix.LiveViewTest.render_change(%{"radius" => radius, "include_no_place" => "true"})
      end)
      |> click_button("Apply filters")
      |> wait_async()
    end

    test "a radius picked in the Nearby row on Discover is the next visit's start; Anywhere too",
         %{creator: creator} do
      events!(creator)
      user = located()

      user
      |> page("/events")
      |> choose_radius("10")
      |> refute_has("[data-id=event_preview]", text: "Mid Hall")

      user
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Near Barn")
      |> refute_has("[data-id=event_preview]", text: "Mid Hall")
      |> assert_has("[data-row=nearby]", text: "Within 10 km")
      |> choose_radius("")
      |> assert_has("[data-id=event_preview]", text: "Far Moor")

      user
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Far Moor")
    end

    test "a radius picked on My events is not remembered", %{creator: creator} do
      events!(creator)
      user = located()
      north!(user, "My Far Gig", 80)

      user
      |> page("/events/my")
      |> choose_radius("10")

      user
      |> page("/events")
      |> assert_has("[data-id=event_preview]", text: "Mid Hall")
      |> assert_has("[data-row=nearby]", text: "Within 50 km")
    end
  end
end
