defmodule Bonfire.Gatherings.Repo.Migrations.APActivityEventsToEvents do
  @moduledoc """
  Backfill: events stored as APActivities become native `Bonfire.Gatherings.Event`s, keeping their pointer id. Selection and conversion live in (and are tested via) `Bonfire.Gatherings.APActivityEventsMigration`.
  """
  use Ecto.Migration
  alias EctoSparkles.DataMigration

  alias Bonfire.Gatherings.APActivityEventsMigration

  # what `use DataMigration` sets, which is not used here so that `up/0` can hand the runner this migration's repo
  @behaviour DataMigration
  @disable_ddl_transaction true
  @disable_migration_lock true

  # the migration's own repo, so the conversion acts on the database being migrated
  def up, do: DataMigration.Runner.run(__MODULE__, repo: repo())

  def down, do: :ok

  @impl DataMigration
  def base_query, do: APActivityEventsMigration.base_query()

  @impl DataMigration
  def config do
    %DataMigration.Config{batch_size: 100, throttle_ms: 100, repo: Bonfire.Common.Repo}
  end

  @impl DataMigration
  def migrate(rows, opts), do: APActivityEventsMigration.migrate(rows, opts)
end
