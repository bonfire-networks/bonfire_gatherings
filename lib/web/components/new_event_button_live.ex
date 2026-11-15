defmodule Bonfire.Gatherings.Web.NewEventButtonLive do
  @moduledoc "The New button on `/events`: opens the composer's event form, where the instance allows it."
  use Bonfire.UI.Common.Web, :stateless_component

  @doc "The instance toggle, off by default. Read on every composer render, so from Config (one key), where instance settings are mirrored, rather than `Settings.get/3`, which copies all of the app's config each time."
  def local_creation? do
    # require Bonfire.Common.Settings
    # Bonfire.Common.Settings.get([Bonfire.Gatherings.Events, :local_creation], false, :instance) == true
    require Bonfire.Common.Config
    Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :local_creation], false) == true
  end
end
