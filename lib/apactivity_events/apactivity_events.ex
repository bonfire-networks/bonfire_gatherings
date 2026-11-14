# was `Bonfire.Social.Events` in `bonfire_social`
defmodule Bonfire.Gatherings.APActivityEvents do
  @moduledoc """
  Deprecated, until the native refactor: events stored as APActivities, from before `Bonfire.Gatherings.Events` claimed the `Event` type (moved here from `bonfire_social` as it was). Native events are listed by `Bonfire.Gatherings.Events.list_upcoming/1`.

  Context for event objects (ActivityStreams `Event`, e.g. federated from Mobilizon/Gancio).

  Owns the event feed entry point and the pure ActivityStreams accessors/parsers shared by the UI (the `/events` page, the agenda preview, and the full event card). Display concerns (labels, icons, colours, formatting) stay in the UI layer; the FEP-8a8e category vocabulary lives in `Bonfire.Gatherings.EventCategories`.

  Events are backed by `Bonfire.Data.Social.APActivity` rows whose `json` column holds the AS2 `Event`. The `:events` feed preset (see `runtime_config.ex`) and its "Events Feed" preload rule already SQL-load that object (incl. `json`) and the subject, so callers should go through `feed/1` rather than querying `APActivity` directly.
  """

  # `feed/1` is commented out: with `bonfire_gatherings` enabled, the `:events` preset's `"Event"` resolves to native events (`Bonfire.Common.Types.object_type/2`), so it could no longer list APActivity ones, and nothing called it after the old `/events` page went.

  # use Bonfire.Common.Utils
  # import Ecto.Query, only: [from: 2]

  # alias Bonfire.Data.Social.APActivity

  # @doc """
  # The `:events` feed, paginated, with each activity's `APActivity` object (carrying the AS2 `json`) attached.
  #
  # The feed itself is loaded with a light `:with_subject` preload (so the event host shows) — the richer object preloads (`:with_object_more` et al.) inner-join the object's typed sub-tables and silently drop `APActivity` events from the results, so instead we batch-load the `APActivity` rows here and attach them onto each `activity.object`. Keeping this query in the context (rather than the UI view) is why the view stays query-free.
  #
  # Accepts the usual feed opts (`current_user:`, `paginate:`, …). Pass `categories:` (a list of FEP-8a8e category keys) to filter to those categories.
  #
  # Deprecated: events are native `Bonfire.Gatherings.Event`s when `bonfire_gatherings` is enabled, listed by `Bonfire.Gatherings.Events.list_upcoming/1`; this lists only events stored as APActivities (when it is not, or before they are converted). The AS2 accessors that were here moved to the fallback card, `Bonfire.UI.Social.Activity.EventActivityStreamsLive`.
  # """
  # def feed(opts) do
  #   {categories, opts} = Keyword.pop(opts, :categories)
  #
  #   filters =
  #     case List.wrap(categories) do
  #       [] -> %{feed_name: :events}
  #       cats -> %{feed_name: :events, object_categories: cats}
  #     end
  #
  #   opts = Keyword.put_new(opts, :preload, [:with_subject])
  #
  #   case Bonfire.Social.FeedActivities.feed(filters, opts) do
  #     %{edges: edges} = result when is_list(edges) ->
  #       %{result | edges: attach_objects(edges)}
  #
  #     other ->
  #       other
  #   end
  # end
  #
  # # Batch-load the `APActivity` rows (which carry the AS2 `json`) and set each onto its `activity.object` (the feed only resolves it to a bare Needle pointer).
  # defp attach_objects(edges) do
  #   objects = load_objects(edges)
  #
  #   Enum.map(edges, fn edge ->
  #     with %{} = object <- Map.get(objects, e(edge, :activity, :object_id, nil)),
  #          activity when not is_nil(activity) <- e(edge, :activity, nil) do
  #       Map.put(edge, :activity, Map.put(activity, :object, object))
  #     else
  #       _ -> edge
  #     end
  #   end)
  # end
  #
  # defp load_objects(edges) do
  #   ids =
  #     edges
  #     |> Enum.map(&e(&1, :activity, :object_id, nil))
  #     |> Enum.reject(&is_nil/1)
  #     |> Enum.uniq()
  #
  #   if ids == [] do
  #     %{}
  #   else
  #     from(a in APActivity, where: a.id in ^ids)
  #     |> Bonfire.Common.Repo.all()
  #     |> Map.new(&{&1.id, &1})
  #   end
  # end

  # `object_field/2`, `title/1`, `parse_time/1` (there `event_time/1`), `start_time/1`, `end_time/1` (there `event_end_time/1`), `location_name/1`, `source_url/1` and `source_host/1` moved to `Bonfire.UI.Social.Activity.EventActivityStreamsLive`, the fallback event card, their only user
end
