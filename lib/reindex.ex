defmodule Bonfire.Gatherings.Reindex do
  @moduledoc """
  (Re)indexes events into the search index, in batches, eg. those made before events were indexed.

  Implements `EctoSparkles.DataMigration` (so it reuses the batched, keyset-paginated, throttled runner) and registers as a `Bonfire.Common.ReindexModule` so it runs as part of a full search backfill via `Bonfire.Search.reindex_all/1`, as `Bonfire.Posts.Reindex` does for posts.
  """
  @behaviour EctoSparkles.DataMigration
  @behaviour Bonfire.Common.ReindexModule
  import Ecto.Query
  alias EctoSparkles.DataMigration

  @impl Bonfire.Common.ReindexModule
  def reindex_module, do: __MODULE__

  @impl Bonfire.Common.ReindexModule
  def reindex(opts \\ []), do: DataMigration.Runner.run(__MODULE__, opts)

  # every event, local or remote: the runner adds `where id > ^last_id` and `order_by id` on this first binding
  @impl DataMigration
  def base_query(_opts \\ []) do
    from(main_object in Bonfire.Gatherings.Event, as: :main_object)
  end

  @impl DataMigration
  def config do
    # `first_id`: lowest ULID string (Needle.UID-castable), as in `Bonfire.Posts.Reindex`
    %DataMigration.Config{
      batch_size: 50,
      throttle_ms: 2000,
      repo: Bonfire.Common.Repo,
      first_id: "00000000000000000000000000"
    }
  end

  # `maybe_index/3` picks each event's index (public or closed) from its boundary
  @impl DataMigration
  def migrate(events) do
    events
    |> Bonfire.Common.Repo.maybe_preload([
      :post_content,
      created: [creator: [:profile, :character]],
      primary_geolocation: :geolocation
    ])
    |> Enum.each(&Bonfire.Search.maybe_index(&1, nil, []))
  end
end
