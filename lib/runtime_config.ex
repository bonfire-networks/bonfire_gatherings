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
      # the FEP-8a8e event categories, in the order the chips show them: each key with the name and the icon its topic is made with, `parent: "KEY"` to put its topic under another category's, and `label: true` to make it a label rather than a topic (the icon is saved in the topic's own settings then, as its `[:ui, :icon]`, and a name only seeds the topic's: once made, it is the topic's own). An icon must be one of the compiled set (`Bonfire.UI.Common.IconPickerLive.curated_icons/0` lists the ones offered for topics).
      categories: [
        MUSIC: [name: l("Music"), icon: "ph:music-notes-fill", parent: "ARTS"],
        ARTS: [name: l("Arts"), icon: "ph:palette-fill"],
        FOOD_DRINK: [name: l("Food & Drink"), icon: "ph:fork-knife-fill"],
        PARTY: [name: l("Party"), icon: "ph:confetti-fill", label: true],
        FESTIVALS: [name: l("Festivals"), icon: "ph:confetti-fill", label: true],
        COMMUNITY: [name: l("Community"), icon: "ph:users-three-fill"],
        MEETING: [name: l("Meeting"), icon: "ph:users-fill", label: true],
        MOVEMENTS_POLITICS: [
          name: l("Movements & Politics"),
          icon: "ph:megaphone-fill",
          parent: "COMMUNITY"
        ],
        SPORTS: [name: l("Sports"), icon: "ph:soccer-ball-fill", parent: "OUTDOORS_ADVENTURE"],
        LEARNING: [name: l("Learning"), icon: "ph:graduation-cap-fill"],
        SCIENCE_TECH: [name: l("Science & Tech"), icon: "ph:flask-fill", parent: "LEARNING"],
        FILM_MEDIA: [name: l("Film & Media"), icon: "ph:film-slate-fill", parent: "ARTS"],
        PERFORMING_VISUAL_ARTS: [
          name: l("Performing & Visual Arts"),
          icon: "ph:mask-happy-fill",
          parent: "ARTS"
        ],
        THEATRE: [name: l("Theatre"), icon: "ph:ticket-fill", parent: "ARTS"],
        GAMES: [name: l("Games"), icon: "ph:game-controller-fill", parent: "COMMUNITY"],
        NETWORKING: [name: l("Networking"), icon: "ph:handshake-fill", parent: "COMMUNITY"],
        BUSINESS: [name: l("Business"), icon: "ph:briefcase-fill", label: true],
        CAUSES: [name: l("Causes"), icon: "ph:hand-heart-fill"],
        CLIMATE_ENVIRONMENT: [
          name: l("Climate & Environment"),
          icon: "ph:leaf-fill",
          parent: "CAUSES"
        ],
        MEDITATION_WELLBEING: [
          name: l("Meditation & Wellbeing"),
          icon: "ph:flower-lotus-fill",
          parent: "CAUSES"
        ],
        OUTDOORS_ADVENTURE: [name: l("Outdoors & Adventure"), icon: "ph:mountains-fill"],
        FAMILY_EDUCATION: [
          name: l("Family & Education"),
          icon: "ph:baby-fill",
          parent: "LEARNING"
        ],
        LANGUAGE_CULTURE: [
          name: l("Language & Culture"),
          icon: "ph:translate-fill",
          parent: "LEARNING"
        ],
        LGBTQ: [name: l("LGBTQ"), icon: "ph:rainbow-fill", parent: "CAUSES"],
        INCLUSIVE_SPACES: [
          name: l("Inclusive Spaces"),
          icon: "ph:hands-clapping-fill",
          label: true
        ],
        CRAFTS: [name: l("Crafts"), icon: "ph:scissors-fill", parent: "ARTS"],
        CREATIVE_JAM: [name: l("Creative Jam"), icon: "ph:sparkle-fill", parent: "LEARNING"],
        DIY_MAKER_SPACES: [
          name: l("DIY & Maker Spaces"),
          icon: "ph:wrench-fill",
          parent: "COMMUNITY"
        ],
        WORKSHOPS_SKILL_SHARING: [
          name: l("Workshops & Skill-sharing"),
          icon: "ph:hammer-fill",
          parent: "LEARNING"
        ],
        FASHION_BEAUTY: [name: l("Fashion & Beauty"), icon: "ph:t-shirt-fill", label: true],
        PHOTOGRAPHY: [name: l("Photography"), icon: "ph:camera-fill", parent: "ARTS"],
        BOOK_CLUBS: [name: l("Book Clubs"), icon: "ph:books-fill", parent: "COMMUNITY"],
        COMEDY: [name: l("Comedy"), icon: "ph:smiley-fill", parent: "ARTS"],
        PETS: [name: l("Pets"), icon: "ph:paw-print-fill", label: true],
        SPIRITUALITY_RELIGION_BELIEFS: [
          name: l("Spirituality & Beliefs"),
          icon: "ph:yin-yang-fill",
          parent: "CAUSES"
        ],
        AUTO_BOAT_AIR: [name: l("Auto, Boat & Air"), icon: "ph:car-fill", label: true]
      ],
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
