defmodule Bonfire.Gatherings.Web.CreateEventTest do
  @moduledoc "Creating an event from the composer."
  use Bonfire.Gatherings.ConnCase, async: false
  use Bonfire.Common.Utils
  import Bonfire.Common.Config, only: [repo: 0]
  import PhoenixTest

  alias Bonfire.Gatherings.Events
  alias Bonfire.Gatherings.LiveHandler
  alias Bonfire.Gatherings.Web.CreateEventLive

  defp allow_creating(allowed?),
    do: Process.put([:bonfire_gatherings, Bonfire.Gatherings.Events, :local_creation], allowed?)

  defp socket(user),
    do: %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, __context__: %{current_user: user}, flash: %{}}
    }

  defp params(overrides \\ %{}) do
    Map.merge(
      %{
        "post" => %{
          "post_content" => %{"name" => "Repair café", "html_body" => "Bring a broken lamp"}
        },
        "starts_at" => "2030-06-01T16:00:00.000Z",
        "ends_at" => "2030-06-01T18:00:00.000Z",
        "timezone" => "Europe/Rome",
        "place" => "Via Baltea 3, Torino",
        "to_boundaries" => ["public"]
      },
      overrides
    )
  end

  defp named(user, name) do
    %{edges: events} = Events.list_upcoming(current_user: user)

    events
    |> repo().maybe_preload([:post_content, :time_span, primary_geolocation: [:geolocation]])
    |> Enum.filter(&(e(&1, :post_content, :name, nil) == name))
  end

  setup do
    on_exit(fn ->
      Process.delete([:bonfire_gatherings, Bonfire.Gatherings.Events, :local_creation])
    end)

    %{user: fake_user!()}
  end

  test "creates the event, with its times in UTC, the browser's time zone and the place typed", %{
    user: user
  } do
    allow_creating(true)

    {:noreply, _} = LiveHandler.handle_event("create_event", params(), socket(user))

    assert [event] = named(user, "Repair café")
    assert DateTime.compare(event.time_span.has_beginning, ~U[2030-06-01 16:00:00Z]) == :eq
    assert DateTime.compare(event.time_span.has_end, ~U[2030-06-01 18:00:00Z]) == :eq
    assert event.time_span.timezone == "Europe/Rome"
    assert event.primary_geolocation.geolocation.name == "Via Baltea 3, Torino"
  end

  test "refuses no name, no start, or an end before the start, creating nothing", %{user: user} do
    allow_creating(true)

    for bad <- [
          %{"post" => %{"post_content" => %{"name" => " "}}},
          %{"starts_at" => ""},
          %{"ends_at" => "2030-06-01T15:00:00.000Z"}
        ] do
      LiveHandler.handle_event("create_event", params(bad), socket(user))
    end

    %{edges: events} = Events.list_upcoming(current_user: user)
    assert events == []
  end

  test "creates nothing where the instance has not switched creating events on, even if the handler is called",
       %{user: user} do
    allow_creating(false)

    LiveHandler.handle_event("create_event", params(), socket(user))

    assert named(user, "Repair café") == []
  end

  test "the New button on /events and the composer's Event type are there only once the instance allows it" do
    account = fake_account!()
    user = fake_user!(account)
    conn = conn(user: user, account: account)

    allow_creating(false)
    refute CreateEventLive.smart_input_tray?()
    conn |> visit("/events") |> refute_has("#events_header_new")

    allow_creating(true)
    assert CreateEventLive.smart_input_tray?()

    assert CreateEventLive in Bonfire.UI.Common.SmartInput.LiveHandler.tray_types(nil)

    conn |> visit("/events") |> assert_has("#events_header_new", text: "New")
  end
end
