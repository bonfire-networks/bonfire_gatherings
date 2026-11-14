defmodule Bonfire.Gatherings.Web.Preview.EventTileLive do
  @moduledoc """
  An event as a tile, for a grid: the cover or placeholder on top with the date chip, then its name, when and where, without its summary. Built from the same parts as `Bonfire.Gatherings.Web.Preview.EventLive`, the card in a list.

  It is also a `custom_preview` (as `Bonfire.UI.Social.FeedLive` and `ActivityLive` take one), so a feed can show its events as tiles: `custom_preview={Bonfire.Gatherings.Web.Preview.EventTileLive}`. Then it gets what `ActivityLive` gives a custom preview, and finds its cover in the event's files itself.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Gatherings.Web.Preview.EventLive

  prop object, :any, default: nil
  prop permalink, :string, default: nil
  # given by the events page, which split the files already; else found in the event's files
  prop primary_image, :any, default: nil
  # listed under a heading that gives its day (the events page): the times only, no date chip
  prop date_in_heading, :boolean, default: false
  # the category the page is filtered by, left out of its badge
  prop exclude_category_id, :any, default: nil

  # what `ActivityLive` gives a `custom_preview` (not used by a tile)
  prop activity, :any, default: nil
  prop activity_component_id, :any, default: nil
  prop reply_count, :any, default: nil
  prop date_ago, :any, default: nil
  prop participants, :any, default: nil
  prop cw, :any, default: nil
  prop rank, :any, default: nil

  def preloads, do: EventLive.preloads()

  @doc "The image shown as its cover: the one given, else the one flagged in its files."
  def cover(nil, object) do
    {primary_image, _} = Bonfire.Files.split_primary_image(e(object, :files, nil))
    primary_image
  end

  def cover(primary_image, _object), do: primary_image
end
