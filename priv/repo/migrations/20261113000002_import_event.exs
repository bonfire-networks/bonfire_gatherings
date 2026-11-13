defmodule Bonfire.Gatherings.Repo.Migrations.ImportEvent do
  @moduledoc false
  use Ecto.Migration
  require Bonfire.Gatherings.Event.Migration

  # a virtual is created on the way up and dropped on the way down by `migrate_virtual`
  def up, do: Bonfire.Gatherings.Event.Migration.migrate_event()
  def down, do: Bonfire.Gatherings.Event.Migration.migrate_event()
end
