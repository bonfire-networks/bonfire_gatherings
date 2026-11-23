defmodule Bonfire.Gatherings.Web.Preview.EventCoverLive do
  @moduledoc "The top of an event's card or tile: its primary image as the cover (or a placeholder), the \"Event\" badge, and the date chip. Shared by `Bonfire.Gatherings.Web.Preview.EventLive` and `EventTileLive`."
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Common.DatesTimes

  prop object, :any, default: nil
  prop primary_image, :any, default: nil

  # the shape of the cover and of the placeholder, eg. `aspect-[3/1]` and `h-24` in a list, `aspect-[4/3]` for both in a tile
  prop cover_class, :css_class, default: "aspect-[3/1]"
  prop placeholder_class, :css_class, default: "h-24"
  # where the date chip sits (the tile puts it at the top, its title being at the bottom)
  prop chip_position_class, :css_class, default: "bottom-3 left-3"

  # under a heading that gives the day (the events page), no date chip
  prop show_date_chip, :boolean, default: true
  # the category the page is filtered by, left out of the badge
  prop exclude_category_id, :any, default: nil
  # the badge (its categories and labels) on the cover; a row shows it beside the cover instead
  prop show_badge, :boolean, default: true

  @doc """
  What the badge names: the categories and labels among the event's tags, if they are loaded (the events page preloads them; a feed may have), less `exclude_id`. Never loads them. Hashtags (named, with no profile) are left out. Empty when none, and the badge then says "Event".

  Each is `%{id: …, name: …, icon: …, colour: …, category?: …}`: the topic's icon and swatch (`Bonfire.Classify.Appearance`) where its settings are loaded, else nil, and whether it is one of the FEP-8a8e categories.
  """
  def badge_names(object, exclude_id \\ nil) do
    case e(object, :tags, nil) do
      tags when is_list(tags) ->
        for tag <- tags,
            id(tag) != exclude_id,
            name = e(tag, :profile, :name, nil),
            is_binary(name) and name != "",
            uniq: true,
            do: %{
              id: id(tag),
              name: name,
              icon: appearance(:icon, tag),
              colour: if(appearance(:settings_loaded?, tag), do: appearance(:colour, tag)),
              category?: Bonfire.Gatherings.EventCategories.key_of_topic(tag) != nil
            }

      _not_loaded ->
        []
    end
  end

  @doc "The topic that gives the card its colour and icon: the main one of those the badge names (the event's FEP-8a8e category if it has one, else the first). nil when there is none, or when the page is filtered by the only one."
  def main_topic(object, exclude_id \\ nil) do
    names = badge_names(object, exclude_id)
    Enum.find(names, & &1.category?) || List.first(names)
  end

  # the topic's colour and icon, where `bonfire_classify` is there to give them
  defp appearance(fun, tag),
    do: maybe_apply(Bonfire.Classify.Appearance, fun, [tag], fallback_return: nil)

  # laid over the cover (eg. the tile's title)
  slot default
end
