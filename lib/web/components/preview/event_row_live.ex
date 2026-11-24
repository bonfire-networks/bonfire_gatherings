defmodule Bonfire.Gatherings.Web.Preview.EventRowLive do
  @moduledoc """
  An event as a row in the events list: its cover on top when the row is narrow, else on the right half, faded into the row (a placeholder when it has no image).

  A `custom_preview` too, as `EventTileLive` is.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Gatherings.Web.Preview.EventLive
  alias Bonfire.Gatherings.Web.Preview.EventCoverLive
  alias Bonfire.Gatherings.Web.Preview.EventPlaceholderLive
  alias Bonfire.Common.DatesTimes

  prop object, :any, default: nil
  prop permalink, :string, default: nil
  prop primary_image, :any, default: nil
  # listed under a heading that gives its day (the events page): the times only, no date chip
  prop date_in_heading, :boolean, default: false
  # the category the page is filtered by, left out of its badge
  prop exclude_category_id, :any, default: nil

  # what `ActivityLive` gives a `custom_preview` (not used by a row)
  prop activity, :any, default: nil
  prop activity_component_id, :any, default: nil
  prop reply_count, :any, default: nil
  prop date_ago, :any, default: nil
  prop participants, :any, default: nil
  prop cw, :any, default: nil
  prop rank, :any, default: nil

  def preloads, do: EventLive.preloads()

  @doc "Started and not ended; never true without an end."
  def happening_now?(object, now \\ DateTime.utc_now()) do
    with %DateTime{} = starts <- e(object, :time_span, :has_beginning, nil),
         %DateTime{} = ends <- e(object, :time_span, :has_end, nil) do
      DateTime.compare(starts, now) != :gt and DateTime.compare(now, ends) != :gt
    else
      _ -> false
    end
  end

  @doc "The creator's name, if loaded, where they are not the activity's subject (`EventLive.host_name/2`)."
  def host_name(object, activity \\ nil), do: EventLive.host_name(object, activity)

  # @doc "The host of a remote event, else nil."
  # def origin(object) do
  #   case e(object, :peered, :canonical_uri, nil) do
  #     uri when is_binary(uri) and uri != "" -> Bonfire.Common.URIs.base_domain(uri)
  #     _ -> nil
  #   end
  # end

  defdelegate cover(primary_image, object), to: Bonfire.Gatherings.Web.Preview.EventTileLive
  defdelegate badge_names(object, exclude_id), to: EventCoverLive
end
