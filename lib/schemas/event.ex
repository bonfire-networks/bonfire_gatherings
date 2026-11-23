defmodule Bonfire.Gatherings.Event do
  @moduledoc """
  A native Event. A `Needle.Virtual` (a DB view over the shared pointers table, filtered by `table_id`) with no columns of its own: every field lives in a reusable mixin (`post_content` for name, summary and body, `time_span` for when, `primary_geolocation` for where, and so on), so deleting it through its pointer keeps it restorable.

  Its associations are injected via `config :bonfire_gatherings, Bonfire.Gatherings.Event, code: …` in `config/bonfire_data.exs`.
  """
  use Needle.Virtual,
    otp_app: :bonfire_gatherings,
    table_id: "7EVENTSANDGATHER1NGS0F0VR0",
    source: "bonfire_gatherings_event"

  alias Bonfire.Gatherings.Event
  alias Needle.Changesets

  virtual_schema do
  end

  # def changeset(event \\ %Event{}, params), do: Changesets.cast(event, params, [])
  # the links an event keeps in the `info` map of its `extra_info` mixin, as {the key stored, the key it may be given as}
  @url_keys [
    {"external_participation_url", :external_participation_url},
    {"online_address", :online_address}
  ]

  @doc "Casts the event's own mixins: when (`time_span`, with a beginning required), where (`primary_geolocation`, optional) and its links (`extra_info`, see `web_urls/1`). Name, summary and body go through `Bonfire.Social.PostContents`, as for a post."
  def changeset(event \\ %Event{}, params) do
    event
    |> Changesets.cast(sanitize_extra_info(params), [])
    |> Ecto.Changeset.cast_assoc(:time_span, required: true, with: &time_span_changeset/2)
    |> Ecto.Changeset.cast_assoc(:primary_geolocation,
      with: &Bonfire.Geolocate.PrimaryGeolocation.changeset/2
    )
    |> Ecto.Changeset.cast_assoc(:extra_info, with: &Bonfire.Data.Identity.ExtraInfo.changeset/2)
  end

  @doc """
  The links among `info` (an `extra_info` map, with atom or string keys) that may be kept: the external participation URL and the online address, each only if it is an `http` or `https` URL with a host. Returns them with string keys; anything else is left out.
  """
  def web_urls(info) when is_map(info) do
    for {key, atom_key} <- @url_keys,
        url = Map.get(info, key) || Map.get(info, atom_key),
        web_url?(url),
        into: %{},
        do: {key, url}
  end

  def web_urls(_), do: %{}

  @doc "The stored keys of the links `web_urls/1` keeps."
  def url_keys, do: Enum.map(@url_keys, &elem(&1, 0))

  defp web_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _ ->
        false
    end
  end

  defp web_url?(_), do: false

  # only the valid links are kept, and no `extra_info` row is made when none is left
  defp sanitize_extra_info(params) when is_map(params) do
    key = if Map.has_key?(params, "extra_info"), do: "extra_info", else: :extra_info

    case Map.get(params, key) do
      %{} = extra ->
        info = Map.get(extra, :info) || Map.get(extra, "info") || %{}
        others = info |> Map.drop(Enum.flat_map(@url_keys, &Tuple.to_list/1))
        info = Map.merge(others, web_urls(info))

        if info == %{} and is_nil(Map.get(extra, :summary) || Map.get(extra, "summary")),
          do: Map.delete(params, key),
          else:
            Map.put(params, key, %{
              info: info,
              summary: Map.get(extra, :summary) || Map.get(extra, "summary")
            })

      _ ->
        params
    end
  end

  defp sanitize_extra_info(params), do: params

  # an event needs a start, while the shared mixin leaves it optional for other types
  defp time_span_changeset(span, params) do
    span
    |> Bonfire.Data.Time.TimeSpan.changeset(params)
    |> Ecto.Changeset.validate_required([:has_beginning])
  end
end

defmodule Bonfire.Gatherings.Event.Migration do
  @moduledoc false
  import Needle.Migration
  alias Bonfire.Gatherings.Event

  def migrate_event(), do: migrate_virtual(Event)
end
