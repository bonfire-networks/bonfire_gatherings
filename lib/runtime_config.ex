defmodule Bonfire.Gatherings.RuntimeConfig do
  use Bonfire.Common.Localise
  import Bonfire.UI.Common.Modularity.DeclareHelpers

  # off: events only arrive over C2S or federation
  declare_settings(:toggle, l("Create events on this instance"),
    keys: [Bonfire.Gatherings.Events, :local_creation],
    default_value: false,
    description:
      l("Let signed-in users create events here, from the New button on the events page."),
    scope: :instance
  )

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

    # reserves the usernames of the event category topics, off the boot path, on every boot until done (`Bonfire.Gatherings.EventCategories.run/0`)
    config :bonfire_common, Bonfire.Common.StartupTasks,
      run: [reserve_event_category_topics: Bonfire.Gatherings.EventCategories]

    config :bonfire_ui_common, Bonfire.UI.Common.InputControlsLive,
      enable_fields: [title: [event: [show_by_default: true]]]

    config :bonfire, :ui,
      object_preview: [
        {Bonfire.Gatherings.Event, Bonfire.Gatherings.Web.Preview.EventLive}
      ]

    # Event-creation epic, in the same parallel stages as the `Bonfire.Poll.Questions` and `Bonfire.Posts` ones, so `SetBoundaries` runs after `Tag`.
    config :bonfire_gatherings, Bonfire.Gatherings.Events,
      # the username of a topic that the topics made for event categories (eg. `music_events`) go under, made the first time an event makes one of them; none if set to a blank string 
      categories_parent: System.get_env("EVENT_CATEGORIES_PARENT", "events"),
      epics: [
        create: [
          {Bonfire.Gatherings.Event.Create, @event_act_opts},
          # the `place` given (a name or address, geocoded here) is inserted with the event, so an event that fails leaves no place
          {Bonfire.Geolocate.Acts.PrimaryGeolocation, @event_act_opts},
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
            {Bonfire.Search.Acts.Queue, @event_act_opts},
            # ties an incoming AP object to the event, and over C2S sends the client's own document; events made here are not sent yet, as there is no `Events.ap_publish_activity`
            {Bonfire.Social.Acts.Federate, @event_act_opts}
          ],
          {Bonfire.Tags.Acts.AutoBoost, @event_act_opts}
        ]
      ]
  end
end
