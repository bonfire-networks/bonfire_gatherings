# was `Bonfire.UI.Social.EventCategoryIconLive` in `bonfire_ui_social`
defmodule Bonfire.Gatherings.Web.EventCategoryIconLive do
  @moduledoc """
  The icon of a topic or label, in the colour of its swatch (`Bonfire.Classify.Appearance`): the topic's own `[:ui, :icon]` setting, which the topics made for the FEP-8a8e categories are given when they are made (`Bonfire.Gatherings.EventCategories.reserve_topics/0`). Nothing is shown for a topic with no icon.

  The icon is drawn from the compiled icon set by name, so a name has to be one of those (`Bonfire.UI.Common.IconPickerLive` builds the ones it offers). `colored={false}` inherits the surrounding text colour (e.g. inside a coloured badge).
  """
  use Bonfire.UI.Common.Web, :stateless_component

  # the icon's name (eg. `ph:music-notes-fill`), nil for none
  prop icon, :string, default: nil
  # the swatch's name (eg. `violet`), nil for none
  prop colour, :string, default: nil
  prop class, :css_class, default: "size-5"
  prop colored, :boolean, default: true

  @doc "The classes that give the icon its swatch's ink."
  def ink_class(colour, colored?)

  def ink_class(colour, true) when not is_nil(colour),
    do: ["topic-ink", Bonfire.Common.Swatches.class(colour)]

  def ink_class(_colour, _colored?), do: []
end
