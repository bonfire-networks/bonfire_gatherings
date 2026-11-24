defmodule Bonfire.Gatherings.Web.Preview.EventPlaceholderLive do
  @moduledoc "What stands in for an event's cover when it has no image: a wash of its main topic's swatch (with the topic's icon), else the neutral grey with a calendar. Shared by `EventCoverLive` and `EventRowLive`, which give it their own shape through `class`."
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Gatherings.Web.Preview.EventCoverLive

  prop object, :any, default: nil
  # the category the page is filtered by, left out when picking the main topic
  prop exclude_category_id, :any, default: nil
  # its shape (and borders)
  prop class, :css_class, default: nil
  prop icon_class, :css_class, default: "size-10"
end
