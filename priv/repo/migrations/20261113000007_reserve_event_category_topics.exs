defmodule Bonfire.Gatherings.Repo.Migrations.ReserveEventCategoryTopics do
  @moduledoc false
  use Ecto.Migration

  # reserves the usernames of the FEP-8a8e category topics and their parent (as archived topics, brought back by the first event that names them); can run again
  # def up, do: Bonfire.Gatherings.EventCategories.reserve_topics()
  # now a startup task, off the boot path (`Bonfire.Gatherings.EventCategories.run/0`, registered in `Bonfire.Gatherings.RuntimeConfig`)
  def up, do: nil
  def down, do: nil
end
