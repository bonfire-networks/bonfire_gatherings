defmodule Bonfire.Gatherings.APActivityEventsMigration do
  @moduledoc """
  The one-off conversion of events stored as APActivities (their AS2 `Event` json) into native `Bonfire.Gatherings.Event`s, run by a DataMigration. Kept in `lib/` (as `Bonfire.Articles.PostsToArticlesMigration` is) so it can be tested.

  An event keeps its pointer id, so what is keyed on it stays: its activity and feed rows, tags, boundary, creator, and the AP object pointing at it. It gets its own mixins from the json (post content, time span with its zone, and its place when the nested Place became a Geolocation), its pointer moves to the Event table, and its APActivity row is removed. One with no start is left as it is, as an event needs one.
  """
  import Ecto.Query
  alias Bonfire.Common.Repo

  @apactivity_table_id "30NF1REAPACTTAB1ENVMBER0NE"
  @event_table_id "7EVENTSANDGATHER1NGS0F0VR0"

  @doc "The APActivities whose json is an `Event` with a start (the object itself, or wrapped in an activity)."
  def base_query do
    from(a in "bonfire_data_social_apactivity",
      join: pp in "pointers_pointer",
      on: pp.id == a.id,
      where: pp.table_id == ^Needle.ULID.dump!(@apactivity_table_id),
      where: fragment("coalesce(?->'object'->>'type', ?->>'type') = 'Event'", a.json, a.json),
      where:
        not is_nil(
          fragment("coalesce(?->'object'->>'startTime', ?->>'startTime')", a.json, a.json)
        ),
      select: %{id: a.id, json: a.json}
    )
  end

  @doc "Converts each of `rows` (from `base_query/0`), one transaction each, in the repo given as `opts[:repo]` (a migration passes the one it runs on), else the normal one."
  def migrate(rows, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    Enum.each(rows, &convert(&1, repo))
  end

  defp convert(%{id: id, json: json}, repo) do
    {:ok, ulid} = Needle.ULID.load(id)
    event = event_json(json)

    repo.transaction(fn ->
      put_post_content(ulid, event, repo)
      put_time_span(ulid, event, repo)
      put_place(ulid, event["location"])

      repo.update_all(from(pp in "pointers_pointer", where: pp.id == ^id),
        set: [table_id: Needle.ULID.dump!(@event_table_id)]
      )

      repo.delete_all(from(a in "bonfire_data_social_apactivity", where: a.id == ^id))

      # removing a pointable's row marks its pointer deleted (Needle's delete trigger), which would hide the event it now is
      repo.update_all(from(pp in "pointers_pointer", where: pp.id == ^id), set: [deleted_at: nil])
    end)
  end

  defp event_json(%{"object" => %{"type" => "Event"} = event}), do: event
  defp event_json(event), do: event

  # sanitised here, as ingest does for remote content; not through `PostContents.ap_receive_attrs_prepare/4`, which can fetch the actors it mentions
  defp put_post_content(id, event, repo) do
    struct(Bonfire.Data.Social.PostContent, id: id)
    |> Bonfire.Data.Social.PostContent.changeset(%{
      name: event["name"],
      summary: event["summary"],
      html_body: Bonfire.Common.Text.maybe_sane_html(event["content"])
    })
    |> repo.insert(on_conflict: :nothing, conflict_target: :id)
  end

  defp put_time_span(id, event, repo) do
    zone = event["timezone"]

    %Bonfire.Data.Time.TimeSpan{id: id}
    |> Bonfire.Data.Time.TimeSpan.changeset(%{
      has_beginning: Bonfire.Common.DatesTimes.to_date_time(event["startTime"]),
      has_end: Bonfire.Common.DatesTimes.to_date_time(event["endTime"]),
      # an unknown zone is dropped rather than leaving the event behind
      timezone: if(is_binary(zone) and Tzdata.zone_exists?(zone), do: zone)
    })
    |> repo.insert(on_conflict: :nothing, conflict_target: :id)
  end

  # the Geolocation the nested ingest made of the Place, if it had an id
  defp put_place(id, [first | _]), do: put_place(id, first)

  # the reference `Bonfire.Social.APActivities.reference_nested_objects/1` left in the json carries the Geolocation's pointer
  defp put_place(id, %{"pointer_id" => geo_id}) when is_binary(geo_id),
    do: Bonfire.Geolocate.PrimaryGeolocations.set(id, geo_id)

  defp put_place(id, %{"id" => ap_id}), do: put_place(id, ap_id)

  defp put_place(id, ap_id) when is_binary(ap_id) do
    with {:ok, %{pointer_id: geo_id}} when is_binary(geo_id) <-
           ActivityPub.Object.get_cached(ap_id: ap_id) do
      Bonfire.Geolocate.PrimaryGeolocations.set(id, geo_id)
    end
  end

  defp put_place(_id, _), do: nil
end
