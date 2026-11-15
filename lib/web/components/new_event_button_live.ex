defmodule Bonfire.Gatherings.Web.NewEventButtonLive do
  @moduledoc "The New button on `/events`: opens the composer's event form, where the instance allows it."
  use Bonfire.UI.Common.Web, :stateless_component

  @doc "The instance toggle, off by default."
  def local_creation? do
    require Bonfire.Common.Settings
    Bonfire.Common.Settings.get([Bonfire.Gatherings.Events, :local_creation], false, :instance) == true
  end
end
