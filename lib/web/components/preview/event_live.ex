defmodule Bonfire.Gatherings.Web.Preview.EventLive do
  @moduledoc """
  The card of a native `Bonfire.Gatherings.Event` in feeds and on its page, from its mixins: its name and summary (`post_content`), when (`time_span`, shown in the event's own time zone when it has one) and where (`primary_geolocation`). It replaces `Bonfire.UI.Social.Activity.EventActivityStreamsLive`, which stays for events stored as APActivities.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Common.DatesTimes

  prop object, :any, default: nil
  prop activity, :any, default: nil
  prop showing_within, :any, default: nil
  prop viewing_main_object, :boolean, default: false
  prop permalink, :string, default: nil
  prop parent_id, :any, default: nil
  prop activity_inception, :boolean, default: false

  # the media flagged as its primary image (split from the others by `Bonfire.UI.Social.ActivityLive`, which lists the rest through `MediaLive`)
  prop primary_image, :any, default: nil

  # `:list` (the card in a column) or `:tile` (in a grid: the cover or placeholder on top, when and where, no summary)
  # prop layout, :atom, default: :list
  # listed under a heading that gives its day (the events page): the times only, no date chip
  prop date_in_heading, :boolean, default: false
  # the category the page is filtered by, left out of its badge
  prop exclude_category_id, :any, default: nil

  # (a tile is its own component, `EventTileLive`, sharing this card's parts, `EventCoverLive` and `EventWhenWhereLive`)

  @doc "Its primary image is shown as its cover, in place of the calendar placeholder."
  def primary_image_as_cover?, do: true

  @doc "What a feed loads for this card (read by the feed's preloads of `[:ui, :object_preview]` components)."
  # def preloads, do: [:post_content, :time_span, primary_geolocation: [:geolocation]]
  # with its media, which `Bonfire.UI.Social.ActivityLive` splits into the cover and the rest
  def preloads,
    do: [:post_content, :time_span, primary_geolocation: [:geolocation], files: [:media]]

  def name(object), do: e(object, :post_content, :name, nil)

  def summary(object),
    do: e(object, :post_content, :summary, nil) || e(object, :post_content, :html_body, nil)

  def starts(object),
    do: DatesTimes.wall_time(e(object, :time_span, :has_beginning, nil), timezone(object))

  def ends(object),
    do: DatesTimes.wall_time(e(object, :time_span, :has_end, nil), timezone(object))

  defp timezone(object), do: e(object, :time_span, :timezone, nil)

  @doc "The host's name: the activity subject, else the creator if loaded."
  def host_name(object, activity \\ nil) do
    host = e(activity, :subject, nil) || e(object, :created, :creator, nil)
    e(host, :profile, :name, nil) || e(host, :character, :username, nil)
  end

  def place(object) do
    geo = e(object, :primary_geolocation, :geolocation, nil)

    case Enum.reject([e(geo, :name, nil), e(geo, :mappable_address, nil)], &(&1 in [nil, ""])) do
      [] -> nil
      parts -> parts |> Enum.uniq() |> Enum.join(" - ")
    end
  end
end
