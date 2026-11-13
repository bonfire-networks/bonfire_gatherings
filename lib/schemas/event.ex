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
  @doc "Casts the event's own mixins: when (`time_span`, with a beginning required) and where (`primary_geolocation`, optional). Name, summary and body go through `Bonfire.Social.PostContents`, as for a post."
  def changeset(event \\ %Event{}, params) do
    event
    |> Changesets.cast(params, [])
    |> Ecto.Changeset.cast_assoc(:time_span, required: true, with: &time_span_changeset/2)
    |> Ecto.Changeset.cast_assoc(:primary_geolocation,
      with: &Bonfire.Geolocate.PrimaryGeolocation.changeset/2
    )
  end

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
