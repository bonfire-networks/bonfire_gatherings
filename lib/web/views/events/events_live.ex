defmodule Bonfire.Gatherings.Web.EventsLive do
  @moduledoc """
  The `/events` page: upcoming events (not yet ended, earliest start first, `Bonfire.Gatherings.Events.list_upcoming/1`), shown with their cards (`Bonfire.Gatherings.Web.Preview.EventLive`), a page at a time. `/events/category/:category_ref` lists those tagged with a topic.

  It replaces `Bonfire.UI.Social.EventsLive`, which listed APActivity events through the `:events` feed.
  """
  use Bonfire.UI.Common.Web, :surface_live_view

  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Gatherings.Events
  alias Bonfire.Gatherings.Settings.NearbyDefaultSettingLive, as: NearbyDefault
  alias Bonfire.Gatherings.Web.Preview.EventLive

  declare_extension(
    "Gatherings",
    icon: "bi:app",
    description: l("Organisation of events"),
    # default_nav: [
    #   Bonfire.Gatherings.Web.HomeLive,
    #   Bonfire.Gatherings.Web.AboutLive
    # ]
    # the events page in the main nav (where `:bonfire_gatherings` is in `:ui, :default_nav_extensions`)
    default_nav: [
      Bonfire.Gatherings.Web.EventsLive
    ]
  )

  declare_nav_link(l("Events"),
    icon: "ph:calendar-blank-fill",
    page: "events",
    href: "/events"
  )

  on_mount {LivePlugs,
            [
              Bonfire.UI.Me.LivePlugs.LoadCurrentUser,
              Bonfire.UI.Me.LivePlugs.LoadCurrentUserCircles
            ]}

  def mount(_params, _session, socket) do
    preview = event_preview(socket)

    {:ok,
     assign(socket,
       page: "events",
       # page_title: l("Upcoming events"),
       # as on the old `/events` page, with its sidebar widget
       page_title: l("Discover Events"),
       sidebar_widgets: sidebar_widgets(:upcoming, false, %{}),
       page_header_icon: "ph:calendar-blank-fill",
       page_header_aside: [{Bonfire.Gatherings.Web.NewEventButtonLive, []}],
       no_index: true,
       back: true,
       tags: nil,
       # the category chips (FEP-8a8e), from the old `/events` page
       # categories: Bonfire.Gatherings.EventCategories.all(),
       # the chips are the categories of the listed events (`load_chips/1`), not a fixed list
       category_chips: Phoenix.LiveView.AsyncResult.ok([]),
       selected_category: nil,
       selected_category_id: nil,
       category_ref: nil,
       selected_label_id: nil,
       label_ref: nil,
       event_preview: preview,
       maps_enabled: maps_enabled?(),
       # the search box, only with a search index (`Events.search/2`), on upcoming lists
       search_available: Events.search_available?(),
       search: nil,
       # tiles take the width of the right sidebar
       without_secondary_widgets: tiles?(preview),
       time: :upcoming,
       # the events of the people I follow and my own (`/events/my`), not all known events
       my: false,
       # what the viewer applied in the feed filter editor (Happening, Posted, sort order, Nearby), on top of the list's own defaults (`editor_filters/2`)
       filters: default_filters(socket),
       filters_open: false,
       base_path: "/events",
       events: [],
       page_info: nil,
       # the map: the box the user has moved it to (nil until they do), and the view it opens on (around the viewer's saved location, if there is one)
       map_bounds: nil,
       map_fit: nil
     )}
  end

  # the controls that cannot change a list of events: replies (the events are not replies to anything listed), group activities, and the rows for the types of object, activity and media (everything listed is an event). Boosts stay, as events are shared by boosting them
  @hidden_filters [:replies, :group_activity, :object_types, :activity_types, :media_types]

  @doc "The props of the customize-feed widget (`Bonfire.UI.Social.WidgetCustomizeFeedLive`), as the sidebar and the inline panel of the tile and map views both render it: the list's own order and what the viewer applied, with no `event_target`, so the page itself receives what it sends."
  def customize_props(time, my?, filters, map? \\ false) do
    [
      id: "events_feed_preferences",
      feed_name: if(my?, do: :my, else: :events),
      feed_filters: editor_filters(time, filters, map?),
      # a saved feed would not keep the page's own query
      can_save: false,
      # the markers of a map have no order, so no sort row there
      hide_filters: if(map?, do: [:sort_by | @hidden_filters], else: @hidden_filters),
      # when and where are what people narrow events by: shown above "More filters"
      top_sections: [:happening, :nearby]
    ]
  end

  @doc "The sidebar's widgets: the customize-feed widget, and the topics."
  def sidebar_widgets(time, my?, filters) do
    widgets = [
      {Bonfire.UI.Social.WidgetCustomizeFeedLive, customize_props(time, my?, filters)},
      {Bonfire.Tag.Web.WidgetTagsLive, []}
    ]

    [users: [secondary: widgets], guests: [secondary: widgets]]
  end

  @doc "Whether the page is the map view."
  def map_view?(live_action), do: live_action in [:map, :my_map]

  @doc "Whether the page is of My events (the events of the people I follow and my own)."
  def my_view?(live_action), do: live_action in [:my, :my_past, :my_map]

  @doc "Whether the filters show on the page itself, as there is no sidebar to hold them: the tile and map views."
  def inline_filters?(live_action, preview), do: map_view?(live_action) or tiles?(preview)

  # a topic's own path, `/events/category/<username or id>`: found with the visitor's read boundary, so one they may not read is "not found" like one that does not exist (as on the page this replaces). The param is not called `category`, which is the FEP-8a8e key.
  # def handle_params(%{"category_ref" => ref}, _uri, socket) do
  #   case maybe_apply(
  #          Bonfire.Classify.Categories,
  #          :get,
  #          [ref, [[:default], current_user: current_user(socket)]],
  #          fallback_return: {:error, :not_found}
  #        ) do
  #     {:ok, category} ->
  #       {:noreply,
  #        socket
  #        |> assign(selected_category: category_of_username(ref), selected_category_id: category.id)
  #        # |> show([category.id], "/events/category/#{ref}")}
  #        # with the events of its subtopics, as a group's feed has its topics' (`Bonfire.Classify.LiveHandler`, `group_feed_ids/2`)
  #        |> show([category.id | subtopic_ids(category, socket)], "/events/category/#{ref}")}
  #     _ -> raise Bonfire.Fail, :not_found
  #   end
  # end
  #
  # def handle_params(_params, _uri, socket), do: {:noreply, show(socket, nil, "/events")}

  # by a category (with its subtopics' events, as a group's feed has its topics'), a label, or both (events in both)
  def handle_params(params, _uri, socket) do
    category = params["category_ref"] && find_category!(params["category_ref"], socket)
    label = params["label_ref"] && find_category!(params["label_ref"], socket)

    tag_groups =
      [
        category && [category.id | subtopic_ids(category, socket)],
        label && [label.id]
      ]
      |> Enum.reject(&is_nil/1)

    {:noreply,
     socket
     |> assign(
       selected_category: params["category_ref"] && category_of_username(params["category_ref"]),
       selected_category_id: id(category),
       category_ref: params["category_ref"],
       selected_label_id: id(label),
       label_ref: params["label_ref"],
       # the map, as tiles, takes the width of the right sidebar
       without_secondary_widgets:
         map_view?(socket.assigns.live_action) or tiles?(socket.assigns.event_preview),
       # searched only on the upcoming list, with an index
       search:
         if(
           socket.assigns.search_available and
             socket.assigns.live_action not in [:past, :my_past, :map, :my_map],
           do: blank_to_nil(params["search"])
         )
     )
     |> show(
       if(tag_groups != [], do: tag_groups),
       filter_path(
         params["category_ref"],
         params["label_ref"],
         :upcoming,
         my_view?(socket.assigns.live_action),
         map_view?(socket.assigns.live_action)
       )
     )}
  end

  # a category or label the visitor may see, by username or id, else "not found"
  defp find_category!(ref, socket) do
    case maybe_apply(
           Bonfire.Classify.Categories,
           :get,
           [ref, [[:default], current_user: current_user(socket)]],
           fallback_return: {:error, :not_found}
         ) do
      {:ok, category} -> category
      _ -> raise Bonfire.Fail, :not_found
    end
  end

  @doc """
  The events' places as map markers (`Bonfire.Geolocate.MapLive` takes them), one per event with a place that has coordinates; each popup is its name, place and a link to it, as HTML, escaped (names come from anyone).
  """
  def map_markers(events, exclude_category_id \\ nil) do
    for event <- events,
        geo when not is_nil(geo) <- [e(event, :primary_geolocation, :geolocation, nil)],
        %{lat: lat, long: long} when is_number(lat) and is_number(long) <- [
          maybe_apply(Bonfire.Geolocate.Geolocations, :populate_coordinates, [geo],
            fallback_return: geo
          )
        ] do
      esc = &(&1 |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string())

      %{
        lat: lat,
        long: long,
        name:
          "<a href=\"#{esc.(path(event))}\"><strong>#{esc.(EventLive.name(event) || l("Untitled event"))}</strong></a>" <>
            if(place = EventLive.place(event), do: "<br>#{esc.(place)}", else: "")
      }
      |> Map.merge(topic_pin(event, exclude_category_id))
    end
  end

  # the colour (as the swatch's CSS class) and icon of the event's main topic, as the card has them (`EventCoverLive.main_topic/2`); only the keys it has, so a marker with none is the default one
  defp topic_pin(event, exclude_category_id) do
    case Bonfire.Gatherings.Web.Preview.EventCoverLive.main_topic(event, exclude_category_id) do
      nil ->
        %{}

      topic ->
        %{
          class: Bonfire.Common.Swatches.class(topic.colour),
          icon: topic.icon
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
    end
  end

  @doc "What a chip's link names its category or label by: its username, else its id."
  def chip_ref(category), do: e(category, :character, :username, nil) || id(category)

  @doc "The topic's own icon (`Bonfire.Classify.Appearance`), nil when it has none."
  def chip_icon(category),
    do: maybe_apply(Bonfire.Classify.Appearance, :icon, [category], fallback_return: nil)

  @doc "The swatch name of the topic (its own, its parent's, else the one hashed from its id)."
  def chip_colour(category),
    do: maybe_apply(Bonfire.Classify.Appearance, :colour, [category], fallback_return: nil)

  @doc "The CSS class of the topic's swatch, nil without one."
  def chip_swatch_class(category), do: Bonfire.Common.Swatches.class(chip_colour(category))

  @doc "The path of a filtered list: by a category, a label, or both, upcoming or past, of all events or (`my?`) of the viewer's."
  def filter_path(category_ref, label_ref, time, my? \\ false, map? \\ false) do
    # the map shows the upcoming events only
    "/events" <>
      if(my?, do: "/my", else: "") <>
      if(category_ref, do: "/category/#{category_ref}", else: "") <>
      if(label_ref, do: "/label/#{label_ref}", else: "") <>
      if(map? and time != :past, do: "/map", else: time_suffix(time))
  end

  @doc "The chips that are categories (what kind of event: topics and groups), in the chip bar."
  def topic_chips(chips), do: Enum.reject(List.wrap(chips), &(e(&1, :type, nil) == :label))

  @doc """
  The category chips as the bar shows them: `{category, subtopics}` for each top-level one (whose parent is not among the chips), with its subtopics among the chips (shown in its dropdown). The parent of all the event categories (`categories_parent`, eg. `events`) is not a chip ("All" is), so its children are top-level.
  """
  def nested_topic_chips(chips) do
    require Bonfire.Common.Config

    root = Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :categories_parent], nil)

    chips =
      topic_chips(chips)
      |> Enum.reject(&(root not in [nil, ""] and e(&1, :character, :username, nil) == root))

    ids = MapSet.new(chips, & &1.id)
    parent_id = &e(&1, :tree, :parent_id, nil)

    for chip <- chips, parent_id.(chip) not in ids do
      {chip, Enum.filter(chips, &(parent_id.(&1) == chip.id))}
    end
  end

  @doc "The chips that are labels (what an event is about), apart from the categories."
  # def label_chips(chips), do: Enum.filter(List.wrap(chips), &(e(&1, :type, nil) == :label))
  # without the labels' parents (the "Events" label, the top "Labels"), which the facets count every labelled event towards, as "All" stands for them
  def label_chips(chips) do
    roots = [
      Bonfire.Gatherings.EventCategories.events_label_id(),
      maybe_apply(Bonfire.Label.Labels, :top_label_id, [], fallback_return: nil)
    ]

    Enum.filter(List.wrap(chips), &(e(&1, :type, nil) == :label and id(&1) not in roots))
  end

  # (was a `layout` assign, `:list` or `:tile`; `:layout` is reserved by Phoenix, and the choice is now the preview component itself, as a feed's `custom_preview` is)
  # @list_preview Bonfire.Gatherings.Web.Preview.EventLive
  # a row: a square cover with its text beside it (`EventLive` stays the card in feeds)
  @list_preview Bonfire.Gatherings.Web.Preview.EventRowLive
  @tile_preview Bonfire.Gatherings.Web.Preview.EventTileLive

  # the component each event is shown with: the user's choice, else the flavour's (`config :bonfire_gatherings, Bonfire.Gatherings.Events, custom_preview: Bonfire.Gatherings.Web.Preview.EventTileLive`), else the card in a list
  defp event_preview(socket) do
    require Bonfire.Common.Config

    to_preview(
      Bonfire.Common.Settings.get([Bonfire.Gatherings.Events, :custom_preview], nil,
        current_user: current_user(socket)
      ) ||
        Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :custom_preview], @list_preview)
    )
  end

  # the dropdown's values, or a module (only the two known ones, as a setting is user input)
  defp to_preview(preview)
       when preview in [
              @tile_preview,
              "tile",
              "Elixir.Bonfire.Gatherings.Web.Preview.EventTileLive"
            ],
       do: @tile_preview

  defp to_preview(_), do: @list_preview

  @doc "Whether events are shown as tiles (in a grid)."
  def tiles?(preview), do: preview == @tile_preview

  @doc "The layout dropdown's menu, as `Bonfire.UI.Groups.GroupFilterMenusLive` takes it."
  # def layout_menus(preview) do
  #   [
  #     # an icon already used elsewhere, so in the compiled set (`GroupFilterMenusLive` renders it from a string)
  #     {:layout, "events_layout_menu", "ph:list-bullets", [{"list", l("List")}, {"tile", l("Tiles")}],
  #      if(tiles?(preview), do: "tile", else: "list"), "list", l("Layout")}
  #   ]
  # end
  #
  # def layout_form(preview),
  #   do: Phoenix.Component.to_form(%{"layout" => if(tiles?(preview), do: "tile", else: "list")})
  # with the map too (a page of its own, not saved), checked on the map page
  # the map only where maps can be drawn (`maps_enabled?/0`)
  def layout_menus(preview, live_action \\ nil, maps? \\ true) do
    [
      # an icon already used elsewhere, so in the compiled set (`GroupFilterMenusLive` renders it from a string)
      {:layout, "events_layout_menu", "ph:list-bullets",
       [{"list", l("List")}, {"tile", l("Tiles")}] ++ if(maps?, do: [{"map", l("Map")}], else: []),
       layout_value(preview, live_action), "list", l("Layout")}
    ]
  end

  @doc "Whether the instance can draw maps (`Bonfire.Geolocate.MapLive.maps_enabled?/0`), false without geolocate."
  def maps_enabled?,
    do: maybe_apply(Bonfire.Geolocate.MapLive, :maps_enabled?, [], fallback_return: false) == true

  def layout_form(preview, live_action \\ nil),
    do: Phoenix.Component.to_form(%{"layout" => layout_value(preview, live_action)})

  defp layout_value(_preview, action) when action in [:map, :my_map], do: "map"
  defp layout_value(preview, _), do: if(tiles?(preview), do: "tile", else: "list")

  @doc "The filters the editor starts from: the list's own order (by start date, earliest first for upcoming, latest first for past) and that it is of events, then what the viewer applied."
  def editor_filters(time, filters, map? \\ false) do
    Map.merge(
      %{
        object_types: ["Event"],
        sort_by: :starts_at,
        sort_order: if(time == :past, do: :desc, else: :asc)
      },
      Map.new(filters)
    )
    |> Map.merge(if(map?, do: map_order(), else: %{}))
  end

  # the map's markers are kept in start order (earliest first), whatever sort was chosen in the list view
  defp map_order, do: %{sort_by: :starts_at, sort_order: :asc}

  @doc "Whether the list is in the order of the start dates, which is when its day headings make sense."
  def sorted_by_start?(time, filters), do: editor_filters(time, filters)[:sort_by] == :starts_at

  @doc "The events grouped by the day they start on (where they happen), in their order: `[{\"Friday, September 20, 2030\", events}, …]`. With `by_start?` false (another order) all of them are one group with no day."
  def by_day(events, by_start? \\ true)

  def by_day([], _by_start?), do: []
  def by_day(events, false), do: [{nil, events}]

  def by_day(events, true) do
    events
    |> Enum.chunk_by(&day_of/1)
    |> Enum.map(fn [first | _] = day_events -> {day_of(first), day_events} end)
  end

  defp day_of(event),
    do: Bonfire.Common.DatesTimes.format_day(EventLive.starts(event)) || l("Date unknown")

  @doc "Today, Tomorrow or Yesterday for an event's start day, else nil."
  def day_word(event), do: Bonfire.Common.DatesTimes.relative_day(EventLive.starts(event))

  @doc "The end of a path that keeps to the list being viewed: `/past` on the past one."
  def time_suffix(:past), do: "/past"
  def time_suffix(_upcoming), do: ""

  # the direct subtopics the viewer may see, as a group's page lists them (one level, as there)
  defp subtopic_ids(category, socket) do
    maybe_apply(
      Bonfire.Classify.Categories,
      :list_tree,
      [[:default, parent_category: id(category)], [current_user: current_user(socket)]],
      fallback_return: %{edges: []}
    )
    |> e(:edges, [])
    |> Enums.ids()
  end

  @doc "The username of the local topic of an FEP-8a8e category value: `MUSIC` → `music_events`."
  def category_username(category), do: String.downcase(category) <> "_events"

  # the chip a topic's username stands for, if it is one of them
  def category_of_username(nil), do: nil

  def category_of_username(ref) do
    key = ref |> String.replace_suffix("_events", "") |> String.upcase()

    if String.ends_with?(ref, "_events") and key in Bonfire.Gatherings.EventCategories.all(),
      do: key
  end

  # a choice in the layout dropdown: saved as the user's setting (a guest's lasts the visit)
  # the map: its page, filtered as the list is, and nothing saved
  def handle_event("set_layout", %{"layout" => "map"}, socket) do
    {:noreply,
     push_navigate(socket,
       to:
         filter_path(
           socket.assigns.category_ref,
           socket.assigns.label_ref,
           :upcoming,
           socket.assigns.my
         ) <> "/map"
     )}
  end

  def handle_event("set_layout", %{"layout" => layout}, socket) do
    preview = to_preview(layout)

    if user = current_user(socket),
      do:
        Bonfire.Common.Settings.put([Bonfire.Gatherings.Events, :custom_preview], preview,
          current_user: user
        )

    socket = assign(socket, event_preview: preview, without_secondary_widgets: tiles?(preview))

    # from the map page, back to the list
    if map_view?(socket.assigns.live_action),
      do:
        {:noreply,
         push_navigate(socket,
           to:
             filter_path(
               socket.assigns.category_ref,
               socket.assigns.label_ref,
               :upcoming,
               socket.assigns.my
             )
         )},
      else: {:noreply, socket}
  end

  # a search term with its spaces trimmed, nil when there's none
  defp blank_to_nil(term) when is_binary(term), do: Enums.filter_empty(String.trim(term), nil)
  defp blank_to_nil(_), do: nil

  # the search goes in the URL, so it can be shared and reloaded; an empty one clears it
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         socket.assigns.base_path <>
           case blank_to_nil(term) do
             nil -> ""
             term -> "?" <> URI.encode_query(%{"search" => term})
           end
     )}
  end

  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, filters_open: !socket.assigns.filters_open)}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, load(socket, socket.assigns.tags, e(socket.assigns, :page_info, :end_cursor, nil))}
  end

  # the sort row of the customize-feed widget (the widget's `order_options/1`)
  def handle_event("set_feed_order", %{"feed_order" => order}, socket) do
    case Bonfire.UI.Social.WidgetCustomizeFeedLive.order_filters(
           order,
           Map.put_new(
             editor_filters(socket.assigns.time, socket.assigns.filters),
             :time_span,
             socket.assigns.time
           )
         ) do
      nil ->
        {:noreply, socket}

      order_filters ->
        {:noreply, apply_filters(socket, Map.merge(socket.assigns.filters, order_filters))}
    end
  end

  # the switches of the customize-feed widget (Boosts and Group activities, `@hidden_filters`)
  def handle_event("set_filter_overrides", %{"key" => key, "on" => on}, socket)
      when on in ["true", "false"] do
    case Bonfire.Social.Feeds.LiveHandler.override_filters(
           key,
           on == "true",
           editor_filters(socket.assigns.time, socket.assigns.filters)
         ) do
      attrs when attrs == %{} -> {:noreply, socket}
      attrs -> {:noreply, apply_filters(socket, Map.merge(socket.assigns.filters, attrs))}
    end
  end

  # the customize-feed widget's editor sends its Apply here (the page is its parent), and its reset button a message: the list is loaded again with them
  def handle_info({Bonfire.UI.Social.FeedFiltersModalContentLive, :apply, filters}, socket) do
    filters = Map.new(filters)
    {:noreply, socket |> remember_nearby(filters) |> apply_filters(filters)}
  end

  def handle_info({Bonfire.UI.Social.WidgetCustomizeFeedLive, :reset}, socket) do
    {:noreply, apply_filters(socket, default_filters(socket))}
  end

  # the map tells its page the box in view after the user moves it (`MapLive`'s `bounds_to_parent`): the events are loaded again for it
  def handle_info({Bonfire.Geolocate.MapLive, :bounds, %{} = bounds}, socket) do
    if map_view?(socket.assigns.live_action),
      do: {:noreply, socket |> assign(map_bounds: bounds) |> load(socket.assigns.tags)},
      else: {:noreply, socket}
  end

  # what Discover starts with: the Nearby filter of the "Events near me by default" setting (nothing on My events, or with no saved location)
  defp default_filters(socket, my? \\ nil) do
    with false <- if(is_nil(my?), do: my_view?(socket.assigns.live_action), else: my?),
         user when not is_nil(user) <- current_user(socket),
         %{} = nearby <- NearbyDefault.filter(socket) do
      %{nearby: nearby}
    else
      _ -> %{}
    end
  end

  # a radius picked on Discover (Anywhere too) is the next visit's start, as the user's own setting: one write per change, and none on My events, which ignores the setting. Only the radius is kept, not the point (a typed place is for this search only)
  defp remember_nearby(socket, filters) do
    user = current_user(socket)
    new_km = e(filters, :nearby, :km, nil)

    if (user && not socket.assigns.my) and
         new_km != e(socket.assigns.filters, :nearby, :km, nil),
       do: NearbyDefault.remember(user, e(filters, :nearby, nil))

    socket
  end

  # the one place the filters change: the list is loaded again, and the widget shows them
  defp apply_filters(socket, filters) do
    socket
    |> assign(filters: filters)
    |> assign(sidebar_widgets: sidebar_widgets(socket.assigns.time, socket.assigns.my, filters))
    |> load(socket.assigns.tags)
  end

  # `/…/past` (the `:past` and `:my_past` live actions) lists the events that have ended; the upcoming list of all events, when it has none, goes there instead (My events stays, and says it has none)
  defp show(socket, tags, base_path) do
    time = if socket.assigns.live_action in [:past, :my_past], do: :past, else: :upcoming
    my? = my_view?(socket.assigns.live_action)

    # moving between Discover and My events with the filters untouched swaps the starting filters (My events ignores the nearby default)
    filters =
      if my? != socket.assigns.my and
           socket.assigns.filters == default_filters(socket, socket.assigns.my),
         do: default_filters(socket, my?),
         else: socket.assigns.filters

    socket =
      assign(socket,
        filters: filters,
        time: time,
        my: my?,
        base_path: base_path,
        sidebar_widgets: sidebar_widgets(time, my?, filters)
      )
      |> load(tags)
      |> load_chips()

    # (the map shows what it has, and an empty map, rather than going to past events; a search with no match says so, rather than going to past events)
    if time == :upcoming and not my? and socket.assigns.events == [] and
         not map_view?(socket.assigns.live_action) and
         is_nil(socket.assigns.search),
       do:
         socket
         |> assign_flash(:info, l("There are no upcoming events, so past events are shown."))
         |> push_patch(to: base_path <> "/past"),
       else: socket
  end

  # the categories of the upcoming events, as chips: counted and cached for the instance (`Events.category_facets/2`), then kept to those the viewer may see, in the background so the events show first
  # TODO: chips for the past list too, from all past events, in a cache of their own (it changes slowly, so it can be kept longer)
  # defp load_chips(%{assigns: %{time: :past}} = socket),
  #   do: assign(socket, category_chips: Phoenix.LiveView.AsyncResult.ok([]))
  # the past list's chips are those of the past events, in a cache of their own (`Events.category_facets/2`)

  defp load_chips(socket) do
    current_user = current_user(socket)
    time = socket.assigns.time
    my? = socket.assigns[:my] == true

    assign_async(socket, :category_chips, fn ->
      # My events counts the categories of the viewer's own list, Discover those of every event
      facets =
        if my? and current_user,
          do: Events.category_facets_my(current_user, time),
          else: Events.category_facets(time)

      chips =
        case facets do
          [] ->
            []

          ids ->
            visible =
              ids
              |> Bonfire.Boundaries.load_pointers(current_user: current_user, verbs: [:see])
              |> Enums.ids()

            # in the order counted (most used first), with what a chip shows
            ids = Enum.filter(ids, &(&1 in visible))

            # Bonfire.Common.Needles.list!(ids, skip_boundary_check: true)
            # |> repo().maybe_preload([:profile, :character])
            # as categories, not bare pointers, so each has its type (a label's chip goes in its own set)
            maybe_apply(
              Bonfire.Classify.Categories,
              :list_tree,
              [
                [id: ids, preload: :profile, preload: :character, preload: :tree],
                [skip_boundary_check: true, limit: length(ids)]
              ],
              fallback_return: %{edges: []}
            )
            |> e(:edges, [])
            # with their own settings (the colour and icon of a chip), one batched query
            |> repo().maybe_preload(:settings)
            |> Enum.sort_by(fn category -> Enum.find_index(ids, &(&1 == category.id)) end)
        end

      {:ok, %{category_chips: chips}}
    end)
  end

  defp load(socket, tags, after_cursor \\ nil) do
    opts = [
      current_user: current_user(socket),
      tags: tags,
      after: after_cursor,
      # a search narrows the list to the index's hits (nil without an index: the whole list)
      ids:
        socket.assigns.search &&
          Events.search(socket.assigns.search, current_user: current_user(socket))
    ]

    # the list and the map both go through the feed loader, so the filters of the widget apply to both
    # (was `if time == :past, do: Events.list_past(opts), else: Events.list_upcoming(opts)`)
    filters =
      if tags in [nil, []],
        do: socket.assigns.filters,
        else: Map.put(socket.assigns.filters, :tags, tags)

    # the map keeps to start order, whatever sort the viewer chose in the list view, and loads the events of the area in view (not a page of the list)
    map? = map_view?(socket.assigns.live_action)

    {filters, opts} =
      if map?,
        do: map_query(filters, opts, socket.assigns.map_bounds),
        else: {filters, opts}

    %{edges: events, page_info: page_info} =
      Events.list_by_feed(
        socket.assigns.time,
        filters,
        opts
        |> Keyword.delete(:tags)
        |> Keyword.put(:feed_name, if(socket.assigns.my, do: :my, else: :custom))
      )

    # what the cards show, loaded once for the page
    # events = repo().maybe_preload(events, EventLive.preloads())
    # with the names of their categories and labels, for the cards' badges (here only, not in feeds' preloads)
    events =
      repo().maybe_preload(
        events,
        EventLive.preloads() ++
          [
            # their online link, shown beside the place (one batched query for the page; feeds don't load it)
            :extra_info,
            # the tags with their names, their usernames (which say whether one is a FEP-8a8e category), and their colours and icons (their own settings: a parent's colour is not loaded here, so a topic with none of its own shows its hashed one)
            tags: [:profile, :character, :settings],
            created: [creator: [:profile, :character]],
            peered: []
          ]
      )

    socket =
      assign(socket,
        tags: tags,
        events: if(after_cursor, do: socket.assigns.events ++ events, else: events),
        page_info: page_info
      )

    # the map opens on the area around the viewer's saved location, when the filters have one; once the user has moved the map, its view is theirs
    if map? and is_nil(socket.assigns.map_bounds),
      do: assign(socket, map_fit: nearby_view(e(filters, :nearby, nil))),
      else: socket
  end

  @doc "The most events the map takes (`[Bonfire.Gatherings.Events, :map_limit]`)."
  def map_limit do
    require Bonfire.Common.Config
    Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :map_limit], 200)
  end

  @doc "How wide the map's view can be, in degrees of longitude, before it is not taken as a box (`[Bonfire.Gatherings.Events, :map_wide_longitude]`)."
  def map_wide_longitude do
    require Bonfire.Common.Config
    Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :map_wide_longitude], 180)
  end

  # The filters and options the map loads with, in start order and capped (`map_limit/0`), one query:
  # - once the user has moved the map: the events in its box (which replaces the Nearby radius, as the box is the area now); for a view wider than `map_wide_longitude/0` no box, but the soonest events that have a place
  # - before that: those around the viewer's saved location, if the filters have a Nearby with one (events with no place are left out), else the soonest that have a place
  defp map_query(filters, opts, bounds) do
    filters = Map.merge(Map.new(filters), map_order())
    nearby = e(filters, :nearby, nil)

    filters =
      cond do
        is_map(bounds) and wide?(bounds) ->
          filters |> Map.delete(:nearby) |> Map.put(:within_bounds, %{has_place: true})

        is_map(bounds) ->
          filters |> Map.delete(:nearby) |> Map.put(:within_bounds, bounds)

        nearby_view(nearby) ->
          Map.put(filters, :nearby, Map.put(Map.new(nearby), :include_no_place, false))

        true ->
          filters |> Map.delete(:nearby) |> Map.put(:within_bounds, %{has_place: true})
      end

    {filters, opts |> Keyword.put(:limit, map_limit()) |> Keyword.put(:after, nil)}
  end

  defp wide?(%{west: west, east: east}), do: east - west >= map_wide_longitude()

  # the view that holds a Nearby filter's circle, as `MapLive` takes it, nil without a usable one
  defp nearby_view(%{} = nearby) do
    maybe_apply(
      Bonfire.Geolocate.Geolocations,
      :bounds_around,
      [e(nearby, :lat, nil), e(nearby, :long, nil), e(nearby, :km, nil)],
      fallback_return: nil
    )
  end

  defp nearby_view(_), do: nil
end
