defmodule Bonfire.Gatherings.Web.Preview.EventWhenWhereLive do
  @moduledoc "When an event is (in its own time zone) and where. Shared by `Bonfire.Gatherings.Web.Preview.EventLive` and `EventTileLive`."
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Common.DatesTimes
  alias Bonfire.Gatherings.Web.Preview.EventLive

  prop object, :any, default: nil
  # under a heading that gives the day (the events page): the times only, or "All day"
  prop time_only, :boolean, default: false
  # the time shown elsewhere (on the cover, in the date chip's place): the place only
  prop show_time, :boolean, default: true
end
