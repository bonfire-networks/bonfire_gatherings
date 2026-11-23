defmodule Bonfire.Gatherings.Settings.NearbyDefaultSettingLive do
  @moduledoc """
  "Events near me by default": the radius Discover's events start within, around the viewer's saved location. An instance's default (in `config :bonfire_gatherings, Bonfire.Gatherings.Events`), and each user's choice (the settings cascade).

  The setting holds the radius as the number shown, in the viewer's units (the `:measurement_units` setting, as the Nearby filter row's choices are), or `"anywhere"` for no default filter.
  """
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Settings

  alias Bonfire.Geolocate.FeedFilterNearbyLive, as: Nearby

  @keys [Bonfire.Gatherings.Events, :default_nearby_radius]
  @anywhere "anywhere"

  declare_settings(:select, l("Events near me by default"),
    keys: [Bonfire.Gatherings.Events, :default_nearby_radius],
    options:
      [{"anywhere", l("Anywhere")}] ++
        Enum.map(Bonfire.Geolocate.FeedFilterNearbyLive.radii(), fn radius ->
          {radius, l("%{radius} km or mi", radius: radius)}
        end),
    default_value: nil,
    icon: "ph:map-pin-duotone",
    description:
      l(
        "How far from your saved location the events page starts, in kilometres, or miles if your measurement units are imperial. Events online or with no place are kept. You can widen it from the events page."
      ),
    scope: :user,
    id: "events_default_nearby",
    label_name: l("Events near me by default")
  )

  @doc "The radius setting in kilometres, or nil for Anywhere (or a value that is not a radius)."
  def radius_km(context) do
    case radius(Settings.get(@keys, nil, context)) do
      radius when is_number(radius) and radius > 0 -> Nearby.to_km(radius, Nearby.units(context))
      _ -> nil
    end
  end

  defp radius(radius) when is_number(radius), do: radius

  defp radius(radius) when is_binary(radius) do
    case Float.parse(radius) do
      {radius, ""} -> radius
      _ -> nil
    end
  end

  defp radius(_), do: nil

  @doc "The Nearby filter that Discover starts with: around the viewer's saved location (never geocoded here) at the radius setting, keeping events with no place; nil for Anywhere or with no saved location."
  def filter(context) do
    with km when is_number(km) <- radius_km(context),
         %{lat: lat, long: long} <- Nearby.viewer_location(context) do
      %{lat: lat, long: long, km: km, include_no_place: true}
    else
      _ -> nil
    end
  end

  @doc "Saves the radius of a Nearby filter (nil, or with no radius, is Anywhere) as the user's own setting."
  def remember(user, nearby) do
    value =
      case nearby do
        %{km: km} when is_number(km) -> Nearby.from_km(km, Nearby.units(user))
        _ -> @anywhere
      end

    Settings.put(@keys, value, current_user: user, scope: :user)
  end
end
