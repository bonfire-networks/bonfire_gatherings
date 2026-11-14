defmodule Bonfire.Gatherings.Repo.Migrations.APActivityEventsToEvents do
  @moduledoc """
  Backfill: events stored as APActivities become native `Bonfire.Gatherings.Event`s, keeping their pointer id. Selection and conversion live in (and are tested via) `Bonfire.Gatherings.APActivityEventsMigration`.
  """
  use Ecto.Migration
  alias EctoSparkles.DataMigration
  use DataMigration

  alias Bonfire.Gatherings.APActivityEventsMigration

  @impl DataMigration
  def base_query, do: APActivityEventsMigration.base_query()

  @impl DataMigration
  def config do
    %DataMigration.Config{batch_size: 100, throttle_ms: 100, repo: Bonfire.Common.Repo}
  end

  @impl DataMigration
  def migrate(rows), do: APActivityEventsMigration.migrate(rows)
end
