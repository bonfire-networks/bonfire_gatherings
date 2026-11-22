defmodule Bonfire.Gatherings.Workers.UnindexEnded do
  @moduledoc """
  Takes out of the search index the events that ended longer ago than `[Bonfire.Gatherings.Events, :unindex_ended_after]` (a duration, 30 days by default), so the index holds upcoming and recent events. Run daily by `Oban.Plugins.Cron`.

  Each run takes the events that crossed that line in the last week, rather than every event that ever did, so its work stays the size of a week's events; a run missed for longer than that leaves those in the index, where search drops them anyway (the events page lists upcoming events only).
  """
  use Oban.Worker, queue: :scheduled, max_attempts: 1
  import Ecto.Query
  require Bonfire.Common.Config
  alias Bonfire.Gatherings.Event

  @window to_timeout(day: 7)

  @impl Oban.Worker
  def perform(_job) do
    after_ms =
      Bonfire.Common.Config.get(
        [Bonfire.Gatherings.Events, :unindex_ended_after],
        to_timeout(day: 30)
      )

    cutoff = DateTime.add(DateTime.utc_now(), -after_ms, :millisecond)
    since = DateTime.add(cutoff, -@window, :millisecond)

    # an end in the window, or with no end a start in it (as `Events.list_past/1` counts an event with no end as ended once it starts)
    from(e in Event,
      join: ts in assoc(e, :time_span),
      where:
        (ts.has_end >= ^since and ts.has_end < ^cutoff) or
          (is_nil(ts.has_end) and ts.has_beginning >= ^since and ts.has_beginning < ^cutoff),
      # the rows, as `maybe_unindex/1` looks for a creator on what it is given
      select: e
    )
    |> Bonfire.Common.Repo.all()
    |> Enum.each(&Bonfire.Search.maybe_unindex/1)

    :ok
  end
end
