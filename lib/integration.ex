defmodule Bonfire.Gatherings.Integration do
  use Bonfire.Common.Config
  alias Bonfire.Common.Utils
  import Untangle

  def repo, do: Config.repo()
end
