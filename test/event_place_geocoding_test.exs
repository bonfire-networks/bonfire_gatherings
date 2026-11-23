defmodule Bonfire.Gatherings.EventPlaceGeocodingTest do
  @moduledoc "A place given as text when an event is created is geocoded, so the event shows on the map. The geocoder is replaced by a stub, as the real one is an external service, so this runs alone."
  use Bonfire.Gatherings.DataCase, async: false

  import Bonfire.Me.Fake
  alias Bonfire.Common.Repo
  alias Bonfire.Gatherings.Event
  alias Bonfire.Gatherings.Events

  setup do
    :meck.new(Bonfire.Geolocate.Geocode, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Bonfire.Geolocate.Geocode) end)
    :ok
  end

  defp create_with_place!(place) do
    assert {:ok, event} =
             Events.create(
               current_user: fake_user!(),
               boundary: "public",
               event_attrs: %{
                 post_content: %{name: "Open house"},
                 time_span: %{has_beginning: ~U[2030-06-01 18:00:00.000000Z]},
                 place: place
               }
             )

    Event |> Repo.get!(event.id) |> Repo.preload(primary_geolocation: :geolocation)
  end

  test "a place given as an address is geocoded, and its point stored longitude first" do
    :meck.expect(Bonfire.Geolocate.Geocode, :coordinates, fn _query ->
      {:ok, %{lat: 50.4319, lon: -3.6837}}
    end)

    event = create_with_place!("The Mansion, Totnes")

    assert %{
             primary_geolocation: %{
               geolocation: %{
                 mappable_address: "The Mansion, Totnes",
                 geom: %{coordinates: {-3.6837, 50.4319}}
               }
             }
           } = event

    assert :meck.num_calls(Bonfire.Geolocate.Geocode, :coordinates, ["The Mansion, Totnes"]) == 1
  end

  for {label, place} <- [{"a non-place name", "Online"}, {"a URL", "https://meet.jit.si/x"}] do
    test "#{label} given as the place is kept as text, but not geocoded" do
      :meck.expect(Bonfire.Geolocate.Geocode, :coordinates, fn _query ->
        {:ok, %{lat: 50.4319, lon: -3.6837}}
      end)

      place = unquote(place)
      event = create_with_place!(place)

      assert %{primary_geolocation: %{geolocation: %{name: ^place, geom: nil}}} = event
      assert :meck.num_calls(Bonfire.Geolocate.Geocode, :coordinates, :_) == 0
    end
  end
end
