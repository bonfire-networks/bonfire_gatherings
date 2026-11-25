defmodule Bonfire.Gatherings.Web.EventsLayoutSwitchLive do
  @moduledoc """
  The layout switch of `/events`: list, tiles or the map, as radios in a form sending `set_layout`. With `filters`, the Filters button of the tile and map views sits before it.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  @doc "The current layout: \"list\", \"tile\" or \"map\"."
  prop value, :string, default: "list"

  @doc "Whether the map is offered."
  prop maps, :boolean, default: false

  @doc "Whether the Filters button shows (tile and map views)."
  prop filters, :boolean, default: false

  @doc "Whether the filters are open, for the button's `aria-expanded`."
  prop filters_open, :boolean, default: false
end
