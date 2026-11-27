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

  @doc "Splits its media into the cover and the media to list. In a feed or a list: the primary image, else the first image (a remote event's banner arrives as an attachment, not flagged), and nothing listed beside the card. On the event's own page (`viewing_main_object`): no cover, all its media listed, so the full image can be opened."
  def split_media(files, viewing_main_object \\ false)

  def split_media(files, true), do: {nil, files}

  def split_media(files, _viewing_main_object) do
    {cover, _rest} = Bonfire.Files.split_cover_image(files)
    {cover, []}
  end

  @doc "What a feed loads for this card (read by the feed's preloads of `[:ui, :object_preview]` components)."
  # def preloads, do: [:post_content, :time_span, primary_geolocation: [:geolocation]]
  # with its media, which `Bonfire.UI.Social.ActivityLive` splits into the cover and the rest
  def preloads,
    do: [
      :post_content,
      :time_span,
      primary_geolocation: [:geolocation],
      files: [:media]
    ]

  @doc "What the event's own page loads besides `preloads/0`: its links (`extra_info`), which feeds don't show."
  def extra_preloads, do: [:extra_info]

  def name(object), do: e(object, :post_content, :name, nil)

  # the description is the body; the `summary` is shown only for an event with no body, as a remote event's `summary` is often a machine-made when-and-where text for Mastodon (Gancio, Mobilizon, WordPress Event Bridge), not its description
  # TODO: show a real summary too, as a lead above the description on the event's page, hiding one that repeats the description's opening (as those machine-made ones do), or only for local events
  def summary(object) do
    case e(object, :post_content, :html_body, nil) do
      body when body in [nil, ""] -> e(object, :post_content, :summary, nil)
      body -> body
    end
  end

  def starts(object),
    do: DatesTimes.wall_time(e(object, :time_span, :has_beginning, nil), timezone(object))

  def ends(object),
    do: DatesTimes.wall_time(e(object, :time_span, :has_end, nil), timezone(object))

  @doc "Where the event is booked or joined, if its organiser gave one (from `extra_info`, which is not loaded for you)."
  def participation_url(object), do: link_url(object, "external_participation_url")

  @doc "The event's online link, if it has one (from `extra_info`, which is not loaded for you)."
  def online_address(object), do: link_url(object, "online_address")

  @doc "The link to open for a place that is named by a web address (eg. `https://meet.jit.si/abc`), `nil` for any other place."
  def place_link(place), do: Bonfire.Common.URIs.web_link(place)

  # checked again as shown, though it was when stored
  defp link_url(object, key),
    do:
      object |> e(:extra_info, :info, nil) |> Bonfire.Gatherings.Event.web_urls() |> Map.get(key)

  defp timezone(object), do: e(object, :time_span, :timezone, nil)

  # @doc "The host's name: the activity subject, else the creator if loaded."
  # def host_name(object, activity \\ nil) do
  #   host = e(activity, :subject, nil) || e(object, :created, :creator, nil)
  #   e(host, :profile, :name, nil) || e(host, :character, :username, nil)
  # end

  @doc "The host's name, for a preview that shows no author (eg. a tile): the activity's subject, else the creator, whichever is loaded (no preload)."
  def host_or_creator_name(object, activity \\ nil) do
    host = e(activity, :subject, nil) || e(object, :created, :creator, nil)
    e(host, :profile, :name, nil) || e(host, :character, :username, nil)
  end

  @doc "The creator's name, if loaded, where they are not the activity's subject (shown already as its author). Compares ids only, so needs no preload."
  def host_name(object, activity \\ nil) do
    creator = e(object, :created, :creator, nil)
    creator_id = e(object, :created, :creator_id, nil) || id(creator)

    if creator_id && not Bonfire.UI.Social.ActivityLive.creator_is_subject?(creator_id, activity),
      do: e(creator, :profile, :name, nil) || e(creator, :character, :username, nil)
  end

  def place(object) do
    geo = e(object, :primary_geolocation, :geolocation, nil)

    case Enum.reject([e(geo, :name, nil), e(geo, :mappable_address, nil)], &(&1 in [nil, ""])) do
      [] -> nil
      parts -> parts |> Enum.uniq() |> Enum.join(" - ")
    end
  end
end
