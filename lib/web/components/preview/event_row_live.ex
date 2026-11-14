defmodule Bonfire.Gatherings.Web.Preview.EventRowLive do
  @moduledoc """
  An event as a row, for a list (the events page's list view): a square cover (or placeholder) on the left, and beside it, as tall as the square, its categories and labels, name, when and where, and its summary as plain text, clamped to fit. Built from the same parts as `Bonfire.Gatherings.Web.Preview.EventLive` (the card in feeds) and `EventTileLive`.

  A `custom_preview` too, as `EventTileLive` is.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Gatherings.Web.Preview.EventLive
  alias Bonfire.Gatherings.Web.Preview.EventCoverLive

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

  @doc "Its summary as plain text, for a clamped line."
  def summary_text(object) do
    case EventLive.summary(object) do
      text when is_binary(text) and text != "" -> Bonfire.Common.Text.text_only(text)
      _ -> nil
    end
  end

  defdelegate cover(primary_image, object), to: Bonfire.Gatherings.Web.Preview.EventTileLive
  defdelegate badge_names(object, exclude_id), to: EventCoverLive
end
