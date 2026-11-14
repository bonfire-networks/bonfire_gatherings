defmodule Bonfire.Gatherings.Web.EventsLive do
  @moduledoc """
  The `/events` page: upcoming events (not yet ended, earliest start first, `Bonfire.Gatherings.Events.list_upcoming/1`), shown with their cards (`Bonfire.Gatherings.Web.Preview.EventLive`), a page at a time. `/events/category/:category_ref` lists those tagged with a topic.

  It replaces `Bonfire.UI.Social.EventsLive`, which listed APActivity events through the `:events` feed.
  """
  use Bonfire.UI.Common.Web, :surface_live_view

  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Gatherings.Events
  alias Bonfire.Gatherings.Web.Preview.EventLive

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
    {:ok,
     assign(socket,
       page: "events",
       # page_title: l("Upcoming events"),
       # as on the old `/events` page, with its sidebar widget
       page_title: l("Discover Events"),
       sidebar_widgets: [
         users: [secondary: [{Bonfire.Tag.Web.WidgetTagsLive, []}]],
         guests: [secondary: [{Bonfire.Tag.Web.WidgetTagsLive, []}]]
       ],
       page_header_icon: "ph:calendar-blank-fill",
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
       event_preview: event_preview(socket),
       # tiles take the width of the right sidebar
       without_secondary_widgets: tiles?(event_preview(socket)),
       time: :upcoming,
       base_path: "/events",
       events: [],
       page_info: nil
     )}
  end

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
       label_ref: params["label_ref"]
     )
     |> show(
       if(tag_groups != [], do: tag_groups),
       filter_path(params["category_ref"], params["label_ref"], :upcoming)
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
  def map_markers(events) do
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
    end
  end

  @doc "What a chip's link names its category or label by: its username, else its id."
  def chip_ref(category), do: e(category, :character, :username, nil) || id(category)

  @doc "The path of a filtered list: by a category, a label, or both, upcoming or past."
  def filter_path(category_ref, label_ref, time) do
    "/events" <>
      if(category_ref, do: "/category/#{category_ref}", else: "") <>
      if(label_ref, do: "/label/#{label_ref}", else: "") <> time_suffix(time)
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
  def layout_menus(preview, live_action \\ nil) do
    [
      # an icon already used elsewhere, so in the compiled set (`GroupFilterMenusLive` renders it from a string)
      {:layout, "events_layout_menu", "ph:list-bullets",
       [{"list", l("List")}, {"tile", l("Tiles")}, {"map", l("Map")}],
       layout_value(preview, live_action), "list", l("Layout")}
    ]
  end

  def layout_form(preview, live_action \\ nil),
    do: Phoenix.Component.to_form(%{"layout" => layout_value(preview, live_action)})

  defp layout_value(_preview, :map), do: "map"
  defp layout_value(preview, _), do: if(tiles?(preview), do: "tile", else: "list")

  @doc "The events grouped by the day they start on (where they happen), in their order: `[{\"Friday, September 20, 2030\", events}, …]`."
  def by_day(events) do
    events
    |> Enum.chunk_by(&day_of/1)
    |> Enum.map(fn [first | _] = day_events -> {day_of(first), day_events} end)
  end

  defp day_of(event),
    do: Bonfire.Common.DatesTimes.format_day(EventLive.starts(event)) || l("Date unknown")

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

  @doc "The username of the local topic of an FEP-8a8e category value: `MUSIC` → `music_events` (Mayel)."
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
       to: filter_path(socket.assigns.category_ref, socket.assigns.label_ref, :upcoming) <> "/map"
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
    if socket.assigns.live_action == :map,
      do:
        {:noreply,
         push_navigate(socket,
           to: filter_path(socket.assigns.category_ref, socket.assigns.label_ref, :upcoming)
         )},
      else: {:noreply, socket}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, load(socket, socket.assigns.tags, e(socket.assigns, :page_info, :end_cursor, nil))}
  end

  # `/…/past` (the `:past` live action) lists the events that have ended; the upcoming list, when it has none, goes there instead
  defp show(socket, tags, base_path) do
    time = if socket.assigns.live_action == :past, do: :past, else: :upcoming
    socket = assign(socket, time: time, base_path: base_path) |> load(tags) |> load_chips()

    # (the map shows what it has, and an empty map, rather than going to past events)
    if time == :upcoming and socket.assigns.events == [] and socket.assigns.live_action != :map,
      do: push_patch(socket, to: base_path <> "/past"),
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

    assign_async(socket, :category_chips, fn ->
      chips =
        case Events.category_facets(time) do
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
            |> Enum.sort_by(fn category -> Enum.find_index(ids, &(&1 == category.id)) end)
        end

      {:ok, %{category_chips: chips}}
    end)
  end

  defp load(socket, tags, after_cursor \\ nil) do
    opts = [current_user: current_user(socket), tags: tags, after: after_cursor]

    %{edges: events, page_info: page_info} =
      if socket.assigns.time == :past,
        do: Events.list_past(opts),
        else: Events.list_upcoming(opts)

    # what the cards show, loaded once for the page
    # events = repo().maybe_preload(events, EventLive.preloads())
    # with the names of their categories and labels, for the cards' badges (here only, not in feeds' preloads)
    events = repo().maybe_preload(events, EventLive.preloads() ++ [tags: [:profile]])

    assign(socket,
      tags: tags,
      events: if(after_cursor, do: socket.assigns.events ++ events, else: events),
      page_info: page_info
    )
  end
end
