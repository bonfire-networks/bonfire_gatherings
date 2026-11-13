defmodule Bonfire.Gatherings.RuntimeConfig do
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  # so `EctoActs.Begin/Work/Commit` in the epic resolve to `Bonfire.Ecto.Acts.*`
  alias Bonfire.Ecto.Acts, as: EctoActs

  @event_act_opts [on: :event, attrs: :event_attrs]

  @doc """
  NOTE: you can override this default config in your app's `runtime.exs`, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs()` line
  """
  def config do
    import Config

    # config :bonfire_gatherings,
    #   modularity: :disabled

    # Event-creation epic, in the same parallel stages as the `Bonfire.Poll.Questions` and `Bonfire.Posts` ones, so `SetBoundaries` runs after `Tag`. No `Federate` step yet: events made here stay local until their ActivityPub mapping is decided.
    config :bonfire_gatherings, Bonfire.Gatherings.Events,
      epics: [
        create: [
          {Bonfire.Gatherings.Event.Create, @event_act_opts},
          [
            # name, summary and body, sanitised, with tags extracted
            {Bonfire.Social.Acts.PostContents, @event_act_opts},
            # an event starts a thread, so comments on it are replies
            {Bonfire.Social.Acts.Threaded, @event_act_opts}
          ],
          [
            {Bonfire.Files.Acts.URLPreviews, @event_act_opts}
          ],
          {Bonfire.Tag.Acts.Tag, @event_act_opts},
          [
            {Bonfire.Boundaries.Acts.SetBoundaries, @event_act_opts},
            {Bonfire.Files.Acts.AttachMedia, @event_act_opts},
            {Bonfire.Social.Acts.Activity, @event_act_opts},
            {Bonfire.Me.Acts.Caretaker, @event_act_opts},
            {Bonfire.Me.Acts.Creator, @event_act_opts}
          ],
          EctoActs.Begin,
          EctoActs.Work,
          EctoActs.Commit,
          [
            {Bonfire.Search.Acts.Queue, @event_act_opts}
            # {Bonfire.Social.Acts.Federate, @event_act_opts}
          ],
          {Bonfire.Tags.Acts.AutoBoost, @event_act_opts}
        ]
      ]
  end
end
