defmodule Bonfire.Gatherings.Events do
  @moduledoc "Creating, reading and listing native events (`Bonfire.Gatherings.Event`)."
  use Bonfire.Common.Utils
  use Bonfire.Common.Repo
  import Bonfire.Boundaries.Queries

  alias Bonfire.Gatherings.Event
  alias Bonfire.Social.Objects

  @behaviour Bonfire.Common.QueryModule
  @behaviour Bonfire.Common.ContextModule
  def schema_module, do: Event
  def query_module, do: __MODULE__

  # incoming only for now: events are not yet sent out by this module (no `ap_publish_activity`), except a C2S event, whose own document the epic's Federate act sends
  @behaviour Bonfire.Federate.ActivityPub.FederationModules
  def federation_module, do: ["Event", {"Create", "Event"}, {"Update", "Event"}]

  @doc """
  Creates an event by running the `:create` epic configured in `Bonfire.Gatherings.RuntimeConfig`.

  Options: `current_user`, `event_attrs` (`post_content`, `time_span`, optionally `primary_geolocation`), `boundary`.
  """
  def create(options \\ []) do
    # run_epic(:create, options)
    # an event made here (not from an AP object, as C2S or an incoming one is) stays local until its ActivityPub mapping exists: the Federate act would ask this module for an `ap_publish_activity`, which it does not have yet
    options =
      if options[:ap_object], do: options, else: Keyword.put_new(options, :skip_federation, true)

    run_epic(:create, options)
  end

  defp run_epic(type, options, module \\ __MODULE__, on \\ :event) do
    Bonfire.Epics.run_epic(module, type, Keyword.put(options, :on, on))
  end

  @doc "The event's own changeset (its mixins); the epic adds post content, thread, boundaries, activity and creator."
  def base_changeset(event \\ %Event{}, attrs), do: Event.changeset(event, attrs)

  @doc "Reads one event, checking that the viewer may read it."
  def read(id, opts_or_socket_or_current_user \\ []) when is_binary(id) do
    # one object is opened, so `[:read]` unless the caller asks for more; checked once, in `query/2`, as `Bonfire.Poll.Questions.read/2` does
    opts =
      to_options(opts_or_socket_or_current_user)
      |> Keyword.put_new(:verbs, [:read])

    query([id: id], opts)
    |> Objects.read(Keyword.put(opts, :skip_boundary_check, true))
  end

  @doc "Lists events the viewer may see, a page at a time."
  def list_paginated(filters, opts \\ [])

  def list_paginated(filters, opts) when is_list(filters) or is_struct(filters) do
    filters
    |> query_paginated(opts)
    |> Objects.list_paginated(opts)
  end

  @doc """
  Lists events through the feed loader (`Bonfire.Social.FeedLoader`), so the feed filters apply (`time_span`, `happening_from`, `happening_until`, `sort_by: :starts_at`, `nearby`, `tags`, `time_limit`, ...), a page at a time, as `%{edges: events, page_info: page_info}`: the events are the objects of the activities the feed returns.

  `time` (`:upcoming` or `:past`) sets the defaults, which `filters` override: the side of now, and the order of the start dates (earliest first for upcoming, latest first for past). Options: those of the feed loader (`current_user`, `after`, ...), `feed_name` (`:custom` by default; `:my` for the events of the people the viewer follows and their own), and `ids` to keep to those events only (eg. a search's hits, `search/2`; none when the list is empty).
  """
  def list_by_feed(time, filters \\ %{}, opts \\ []) when time in [:upcoming, :past] do
    opts = to_options(opts)
    {ids, opts} = Keyword.pop(opts, :ids)

    # the feed reads an empty list of objects as no filter at all, so a search with no hits is answered here
    if ids == [],
      do: %{edges: [], page_info: %Paginator.PageInfo{}},
      else: list_by_feed_ids(time, filters, ids, opts)
  end

  defp list_by_feed_ids(time, filters, ids, opts) do
    filters =
      Map.merge(
        %{
          object_types: ["Event"],
          time_span: if(time == :upcoming, do: :current_and_upcoming, else: :past),
          sort_by: :starts_at,
          sort_order: if(time == :upcoming, do: :asc, else: :desc)
        },
        Map.new(filters)
      )
      |> maybe_put_objects(ids)

    {feed_name, opts} = Keyword.pop(opts, :feed_name, :custom)

    %{edges: edges} = page = Bonfire.Social.FeedLoader.feed(feed_name, filters, opts)

    %{page | edges: activities_to_events(edges)}
  end

  # the feed's objects are pointers to the events, and an event is a virtual with no columns of its own (just its id), so each is made from its pointer's id, in the feed's order; the mixins load by that id (the feed has already left out deleted ones and checked the viewer's boundaries)
  defp activities_to_events(edges) do
    for edge <- edges, id = e(edge, :activity, :object_id, nil), do: %Event{id: id}
  end

  defp maybe_put_objects(filters, ids) when is_list(ids), do: Map.put(filters, :objects, ids)
  defp maybe_put_objects(filters, _), do: filters

  @doc """
  Lists the events the viewer may see that have not ended yet (happening now included: an end still ahead, or with no end the end of the day it starts still ahead), earliest start first, a page at a time.

  The time span is inner-joined (every event has one), so the order can use the index on `has_beginning`.
  """
  def list_upcoming(opts \\ []), do: list_by_time(:upcoming, opts)

  @doc "Lists the events the viewer may see that have ended (the opposite of `list_upcoming/1`: an end passed, or with no end the end of the day it starts passed), most recent start first, a page at a time."
  def list_past(opts \\ []), do: list_by_time(:past, opts)

  # the two differ only in which side of now, and in which direction the start date is walked (the same index either way)
  defp list_by_time(time, opts) do
    opts = to_options(opts)
    dir = if time == :upcoming, do: :asc, else: :desc

    query_base()
    |> join(:inner, [main_object: e], ts in assoc(e, :time_span), as: :object_time_span)
    |> where_time(time, DateTime.utc_now())
    |> maybe_tagged_with(opts[:tags])
    |> maybe_with_ids(opts[:ids])
    |> order_by([object_time_span: ts, main_object: e], [{^dir, ts.has_beginning}, {^dir, e.id}])
    # loaded with the event, which the cursor on the start date reads
    |> preload([object_time_span: ts], time_span: ts)
    # as `paginate:`, which the feed loader's own order options (by id, for a list with no sort) don't replace
    |> Objects.list_paginated(
      Keyword.put(
        opts,
        :paginate,
        Keyword.merge(repo().pagination_opts(opts),
          cursor_fields: [{{:object_time_span, :has_beginning}, dir}, {:id, dir}],
          fetch_cursor_value_fun: &cursor_value/2
        )
      )
    )
  end

  defp cursor_value(event, {:object_time_span, :has_beginning}),
    do: e(event, :time_span, :has_beginning, nil)

  defp cursor_value(event, field), do: Paginator.default_fetch_cursor_value(event, field)

  # only these events (eg. a search's hits, `search/2`); none when the list is empty
  defp maybe_with_ids(query, ids) when is_list(ids),
    do: where(query, [main_object: e], e.id in ^ids)

  defp maybe_with_ids(query, _), do: query

  # the same conditions as the feed's time span filters (`Objects.time_span_where/2`): an event with no end lasts until the end of the day it starts
  defp where_time(query, :upcoming, now),
    do: where(query, ^Objects.time_span_where(:current_and_upcoming, now))

  defp where_time(query, :past, now), do: where(query, ^Objects.time_span_where(:past, now))

  @doc """
  The ids of the categories (topics, groups, labels; not hashtags) that tag the events of a list (`:upcoming` for now), most used first, at most `limit`: the facets of that list, as a search shows only the filters found in its results.

  Counted over every event of the list with no boundary check, and cached instance-wide (`cache: :reset` or `:refresh` to recompute), so a page filters them for its viewer (they may not see every category).
  """
  def category_facets(time \\ :upcoming, opts \\ []) do
    Bonfire.Common.Cache.maybe_apply_cached(
      &category_facets_without_cache/2,
      [time, opts[:limit] || 20],
      Keyword.merge(
        [
          cache_key: "Bonfire.Gatherings.Events.category_facets:#{time}",
          # expire:
          #   Bonfire.Common.Config.get(
          #     [__MODULE__, :category_facets_expire],
          #     to_timeout(minute: 5),
          #     name: l("Event category filters"),
          #     description: l("How long the categories offered as filters on the events page are kept before being counted again.")
          #   )
          expire: category_facets_expire(time)
        ],
        Keyword.take(opts, [:cache])
      )
    )
  end

  # the past changes slowly, so its categories are counted again less often
  defp category_facets_expire(:past),
    do:
      Bonfire.Common.Config.get(
        [__MODULE__, :category_facets_past_expire],
        to_timeout(hour: 1),
        name: l("Past event category filters"),
        description:
          l(
            "How long the categories offered as filters on the past events page are kept before being counted again."
          )
      )

  defp category_facets_expire(_upcoming),
    do:
      Bonfire.Common.Config.get(
        [__MODULE__, :category_facets_expire],
        to_timeout(minute: 5),
        name: l("Event category filters"),
        description:
          l(
            "How long the categories offered as filters on the events page are kept before being counted again."
          )
      )

  @doc """
  As `category_facets/2`, but counted over the events of the user's `:my` feed (the people they follow and their own), and cached for that user, with the same expiry.

  One counting query per user per expiry, run when they open My events: the feed's query gives the ids of the events, which are grouped by category in the database.
  """
  def category_facets_my(user, time \\ :upcoming, opts \\ []) do
    Bonfire.Common.Cache.maybe_apply_cached(
      &category_facets_my_without_cache/3,
      [user, time, opts[:limit] || 20],
      Keyword.merge(
        [
          cache_key: "Bonfire.Gatherings.Events.category_facets:my:#{id(user)}:#{time}",
          expire: category_facets_expire(time)
        ],
        Keyword.take(opts, [:cache])
      )
    )
  end

  @doc false
  def category_facets_my_without_cache(user, time, limit) do
    # the feed's own query (its filters, the viewer's follows and boundaries), with no page limit or order, left as the ids of its events
    event_ids =
      Bonfire.Social.FeedLoader.feed(
        :my,
        %{
          object_types: ["Event"],
          time_span: if(time == :upcoming, do: :current_and_upcoming, else: :past)
        },
        current_user: user,
        return: :query,
        query_with_deferred_join: false,
        # the paginator returns its query when given the option itself (not the page limit, which is dropped below)
        paginate: [limit: 1, return: :query]
      )
      |> exclude(:limit)
      |> exclude(:order_by)
      |> exclude(:select)
      |> exclude(:preload)
      |> select([activity: a], %{id: a.object_id})
      |> subquery()

    from(main_object in Event, as: :main_object)
    |> join(:inner, [main_object: e], f in ^event_ids, on: f.id == e.id, as: :my_events)
    |> count_category_facets(time, limit)
  end

  @doc false
  def category_facets_without_cache(time, limit),
    do: count_category_facets(from(main_object in Event, as: :main_object), time, limit)

  defp count_category_facets(events_query, time, limit) do
    category_table = Bonfire.Common.Types.table_id(Bonfire.Classify.Category)

    events_query
    |> join(:inner, [main_object: e], ts in assoc(e, :time_span), as: :object_time_span)
    |> where_time(time, DateTime.utc_now())
    |> join(:inner, [main_object: e], t in Bonfire.Tag.Tagged, on: t.id == e.id, as: :tagged)
    |> join(:inner, [tagged: t], p in Needle.Pointer,
      on: p.id == t.tag_id and p.table_id == ^category_table and is_nil(p.deleted_at),
      as: :tag
    )
    # |> group_by([tagged: t], t.tag_id)
    # |> order_by([tagged: t], desc: count(t.id), asc: t.tag_id)
    # |> limit(^limit)
    # |> select([tagged: t], t.tag_id)
    # |> repo().all()
    # `limit` of each type (labels apart from topics and groups, as they are shown apart), ranked in the same query
    # |> join(:inner, [tagged: t], c in Bonfire.Classify.Category, on: c.id == t.tag_id, as: :category)
    # |> group_by([tagged: t, category: c], [t.tag_id, c.type])
    # |> select([tagged: t, category: c], %{
    #   id: t.tag_id,
    #   uses: count(t.id),
    #   rank:
    #     over(row_number(),
    #       partition_by: fragment("? = 3", c.type),
    #       order_by: [desc: count(t.id), asc: t.tag_id]
    #     )
    # })
    # each tagged category and its ancestors (its tree `path`), so a parent counts the events of its subtopics, each event once
    |> join(:left, [tagged: t], tr in Bonfire.Classify.Tree, on: tr.id == t.tag_id, as: :tree)
    |> join(
      :inner_lateral,
      [tagged: t, tree: tr],
      a in fragment(
        "SELECT unnest(array_append(coalesce(?, ARRAY[]::uuid[]), ?)) AS id",
        tr.path,
        t.tag_id
      ),
      on: true,
      as: :counted
    )
    |> join(:inner, [counted: a], c in Bonfire.Classify.Category, on: c.id == a.id, as: :category)
    # by the category's own id, typed by its schema (`type(…, Needle.UID)` is not a query type)
    |> group_by([category: c], [c.id, c.type])
    |> select([main_object: e, category: c], %{
      id: c.id,
      uses: count(e.id, :distinct),
      rank:
        over(row_number(),
          partition_by: fragment("? = 3", c.type),
          order_by: [desc: count(e.id, :distinct), asc: c.id]
        )
    })
    |> subquery()
    |> where([f], f.rank <= ^limit)
    |> order_by([f], desc: f.uses, asc: f.id)
    |> select([f], f.id)
    |> repo().all()
  end

  # only the events tagged with one of `tags` (ids or tags, eg. a topic): an `exists` on the tagged rows, so an event with several of them is listed once
  # groups of tags (eg. a category with its subtopics, and a label): tagged with one of each group
  defp maybe_tagged_with(query, [first | _] = groups) when is_list(first),
    do: Enum.reduce(groups, query, &maybe_tagged_with(&2, &1))

  defp maybe_tagged_with(query, tags) when is_list(tags) and tags != [] do
    # as UUIDs, the table's column type (a table source has no schema to cast them)
    tag_uuids =
      for id <- Enums.ids(tags), {:ok, bin} = Needle.UID.dump(id), do: Ecto.UUID.cast!(bin)

    where(
      query,
      [],
      exists(
        from(t in "bonfire_tagged",
          where:
            t.id == parent_as(:main_object).id and
              t.tag_id in type(^tag_uuids, {:array, Ecto.UUID}),
          select: 1
        )
      )
    )
  end

  defp maybe_tagged_with(query, _), do: query

  @doc "The query behind `list_paginated/2`."
  def query_paginated(filters, opts \\ [])

  def query_paginated([], opts), do: query_paginated(query_base(), opts)

  def query_paginated(filters, opts) when is_list(filters) or is_struct(filters),
    do: Objects.list_query(filters, opts)

  def query(filters \\ [], opts \\ nil)

  def query(filters, opts) when is_list(filters) or is_tuple(filters) do
    query_base()
    |> query_filter(filters, nil, nil)
    |> boundarise(main_object.id, opts)
  end

  defp query_base do
    from(main_object in Event, as: :main_object)
    |> proload([:post_content])
  end

  @doc """
  Updates an event's name, summary and body, its time span, its place, and its hashtags and categories.

  `attrs` as for `create/1`'s `event_attrs`, plus `hashtags` (a map, as `Bonfire.Tag.ap_receive_hashtags/1` gives) and `tags`.
  """
  def update(creator, %Event{} = event, attrs) do
    # `tags` too: `Bonfire.Tag.maybe_update_tags/3` compares the new tags with these to know which to remove
    event = repo().preload(event, [:post_content, :time_span, :tags])

    repo().transact_with(fn ->
      with {:ok, _} <- update_post_content(event, attrs[:post_content]),
           {:ok, _} <- update_time_span(event, attrs[:time_span]),
           {:ok, _} <- update_place(event, attrs[:primary_geolocation]),
           {:ok, _} <- update_extra_info(event, attrs[:extra_info]),
           {:ok, event} <-
             Bonfire.Tag.maybe_update_tags(creator, event, Map.take(attrs, [:hashtags, :tags])) do
        {:ok, event}
      end
    end)
    # indexed again once saved, with what it holds now (the index its boundary decides)
    |> tap(fn
      {:ok, event} ->
        # the content and place loaded above are from before the update
        event =
          repo().preload(event, [:post_content, primary_geolocation: :geolocation], force: true)

        maybe_apply(Bonfire.Search, :maybe_index, [event, nil, [current_user: creator]],
          fallback_return: nil
        )

      _ ->
        nil
    end)
  end

  defp update_post_content(_event, nil), do: {:ok, nil}

  defp update_post_content(%{post_content: %{} = content}, attrs),
    do: content |> Bonfire.Data.Social.PostContent.changeset(attrs) |> repo().update()

  defp update_post_content(event, attrs),
    # built at runtime: `bonfire_data_social` is not one of this extension's dependencies, so its struct cannot be expanded when this compiles
    do:
      struct(Bonfire.Data.Social.PostContent, id: event.id)
      |> Bonfire.Data.Social.PostContent.changeset(attrs)
      |> repo().insert()

  defp update_time_span(_event, nil), do: {:ok, nil}

  defp update_time_span(%{time_span: %{} = span}, attrs),
    do: span |> Bonfire.Data.Time.TimeSpan.changeset(attrs) |> repo().update()

  defp update_time_span(event, attrs),
    do:
      %Bonfire.Data.Time.TimeSpan{id: event.id}
      |> Bonfire.Data.Time.TimeSpan.changeset(attrs)
      |> repo().insert()

  # the links given replace the ones kept (a link not given is removed), and any other key of `info` stays; no attrs leave it as it is
  defp update_extra_info(_event, nil), do: {:ok, nil}

  defp update_extra_info(event, %{info: info}) do
    event = repo().preload(event, :extra_info)
    existing = e(event, :extra_info, :info, nil) || %{}
    new_info = existing |> Map.drop(Event.url_keys()) |> Map.merge(Event.web_urls(info))

    case {event.extra_info, new_info} do
      {nil, empty} when empty == %{} ->
        {:ok, nil}

      {nil, _} ->
        %Bonfire.Data.Identity.ExtraInfo{id: event.id}
        |> Bonfire.Data.Identity.ExtraInfo.changeset(%{info: new_info})
        |> repo().insert()

      {extra_info, _} ->
        extra_info
        |> Bonfire.Data.Identity.ExtraInfo.changeset(%{info: new_info})
        |> repo().update()
    end
  end

  # a place no longer named is removed; the geolocation itself stays
  defp update_place(event, %{geolocation_id: geolocation_id}),
    do: Bonfire.Geolocate.PrimaryGeolocations.set(event, geolocation_id)

  defp update_place(event, _), do: Bonfire.Geolocate.PrimaryGeolocations.remove(event)

  ## search index

  @doc "Whether there is a search index to ask (else `search/2` returns nil and the page offers no search)."
  def search_available? do
    module_enabled?(Bonfire.Search.Indexer) and
      maybe_apply(Bonfire.Search, :adapter, [], fallback_return: nil) not in [nil, false]
  end

  @doc """
  The ids of the events the search index finds for `term`, at most `search_limit` (config, default 100) from each index read, to pass as `ids:` to `list_upcoming/1`, which keeps its own filters, order, paging and the viewer's boundaries. Reads the public index, and the closed one too for a signed-in viewer. Returns nil when there is no search index (the page then offers no search), as `Bonfire.Classify.Categories.search_groups/2` does.
  """
  def search(term, opts \\ []) when is_binary(term) do
    opts = to_options(opts)
    limit = Bonfire.Common.Config.get([__MODULE__, :search_limit], 100)
    indexes = if current_user_id(opts), do: ["public", "closed"], else: ["public"]

    if module_enabled?(Bonfire.Search.Indexer) do
      Enum.reduce_while(indexes, [], fn index, ids ->
        case maybe_apply(
               Bonfire.Search,
               :search,
               [
                 term,
                 %{index: index, raw: true, limit: limit},
                 [],
                 # %{"index_type" => Types.module_to_str(Event)}
                 [index_type: Event]
               ],
               fallback_return: nil
             ) do
          %{} = result -> {:cont, ids ++ (result |> e(:hits, []) |> List.wrap() |> Enums.ids())}
          _ -> {:halt, nil}
        end
      end)
      |> then(&(&1 && Enum.uniq(&1)))
    end
  end

  @doc "The document `Bonfire.Search` indexes for an event, under its own type: its name, summary and body, its creator, and its place. Loads only what isn't loaded yet; given a bare pointer, loads the event first, as a pointer has no place mixin."
  def indexing_object_format(%Needle.Pointer{id: id}) when is_binary(id) do
    case repo().get(Event, id) do
      %Event{} = event -> indexing_object_format(event)
      _ -> nil
    end
  end

  def indexing_object_format(%{id: _} = event) do
    event =
      repo().maybe_preload(
        event,
        [
          :post_content,
          created: [creator: [:profile, :character]],
          primary_geolocation: :geolocation
        ],
        false
      )

    geo = e(event, :primary_geolocation, :geolocation, nil)

    %{
      "id" => id(event),
      "index_type" => Types.module_to_str(Event),
      "post_content" =>
        maybe_apply(Bonfire.Social.PostContents, :indexing_object_format, [
          e(event, :post_content, nil)
        ]),
      "created" =>
        maybe_apply(Bonfire.Me.Integration, :indexing_format_created, [event],
          fallback_return: nil
        ),
      "place" =>
        if(geo,
          do: %{
            "name" => e(geo, :name, nil),
            "mappable_address" => e(geo, :mappable_address, nil)
          }
        )
    }
  end

  def indexing_object_format(_), do: nil

  ## incoming ActivityPub

  def ap_receive_activity(creator, activity, object, extra_opts \\ [])

  # the `ActivityPub.Object` is carried in `extra_opts`, so the Federate act can tie it to the event (and over C2S, send it)
  def ap_receive_activity(creator, activity, %{data: %{} = data} = ap_object, extra_opts),
    do:
      ap_receive_activity(
        creator,
        activity,
        data,
        Keyword.put_new(extra_opts, :ap_object, ap_object)
      )

  # a bare `Event` with no `Create` wrapper: the activity is the object
  def ap_receive_activity(
        creator,
        %{data: %{"type" => "Event"} = data} = activity,
        nil,
        extra_opts
      ),
      do:
        ap_receive_activity(
          creator,
          activity,
          data,
          Keyword.put_new(extra_opts, :ap_object, activity)
        )

  def ap_receive_activity(creator, activity, %{"id" => ap_id} = data, extra_opts) do
    opts = ap_receive_opts(creator, activity, data, extra_opts)

    case {e(activity, :data, "type", nil), existing_event(ap_id)} do
      {"Update", %Event{} = event} ->
        # qualified, as a bare `update/3` is `Ecto.Query.update/3`, imported by `use Bonfire.Common.Repo`
        __MODULE__.update(creator, event, opts[:event_attrs])

      _ ->
        with {:ok, event} <- create(opts) do
          # into the feeds of the categories it was tagged with, as far as the creator may `:tag` them (as `Bonfire.Social.APActivities` did for events)
          Bonfire.Common.Utils.maybe_apply(
            Bonfire.Tag,
            :maybe_boost_tagged,
            [creator, event, [ap_object: opts[:ap_object]]],
            fallback_return: nil
          )

          # into the feeds of the topics of its FEP-8a8e categories, whoever posted it: the value is the poster's own claim, as a hashtag is, so no `:tag` permission is asked. Only a local event's boost is sent out to the topic's followers elsewhere
          if opts[:category_mirrors] not in [nil, []],
            do:
              Bonfire.Common.Utils.maybe_apply(
                Bonfire.Social.Tags,
                :auto_boost,
                [
                  opts[:category_mirrors],
                  event,
                  [skip_federation: not Bonfire.Social.is_local?(creator)]
                ],
                fallback_return: nil
              )

          {:ok, event}
        end
    end
  end

  defp existing_event(ap_id) do
    with {:ok, %{pointer_id: id}} when is_binary(id) <-
           ActivityPub.Object.get_cached(ap_id: ap_id) do
      repo().get(Event, id)
    else
      _ -> nil
    end
  end

  defp ap_receive_opts(creator, activity, data, extra_opts) do
    activity_data = e(activity, :data, nil) || %{}
    adapter = Bonfire.Federate.ActivityPub.AdapterUtils

    is_public? = adapter.is_public?(activity, extra_opts[:ap_object] || activity)
    direct_recipients = adapter.all_known_recipient_characters(activity_data, data)

    {boundary, to_circles} =
      adapter.recipients_boundary_circles(
        direct_recipients,
        activity,
        is_public?,
        data["interactionPolicy"]
      )

    # the mirrors of its FEP-8a8e categories, tagged and then boosted into
    # category_mirrors = fep_8a8e_categories(data, creator)
    # with the topics of the values its `Category` tags are named after (eg. Lauti's "Music"), which then make no topic of their own
    {named_keys, other_tags} = split_value_named_tags(data["tag"], creator)

    category_mirrors =
      fep_8a8e_categories(data, creator, named_keys)

    [
      current_user: creator,
      boundary: boundary,
      to_circles: to_circles,
      category_mirrors: category_mirrors,
      event_attrs:
        ap_event_attrs(
          creator,
          activity_data,
          Map.put(data, "tag", other_tags),
          direct_recipients,
          category_mirrors
        )
        # the id the AP object may already have reserved (a C2S object's id URL carries it), as `Bonfire.Posts` does: `Outgoing` then recognises the object as the event, and over C2S sends the client's own Create instead of asking this module to build one
        |> Enums.maybe_put(:id, e(extra_opts[:ap_object], :pointer_id, nil))
    ]
    |> Keyword.merge(Keyword.take(extra_opts, [:publish_in, :ap_object]))
  end

  # the AS2 / FEP-8a8e fields the event models; the rest stay readable in its cached AP document
  defp ap_event_attrs(creator, activity_data, data, direct_recipients, category_mirrors) do
    attrs =
      Bonfire.Social.PostContents.ap_receive_attrs_prepare(
        creator,
        activity_data,
        data,
        direct_recipients
      )

    attrs
    |> Map.merge(%{
      time_span: %{
        has_beginning: Bonfire.Common.DatesTimes.to_date_time(data["startTime"]),
        has_end: Bonfire.Common.DatesTimes.to_date_time(data["endTime"]),
        # an unknown zone is dropped rather than refusing the event
        timezone: known_timezone(data["timezone"])
      },
      # tags: List.wrap(attrs[:tags]) ++ ap_category_tags(data["tag"], creator),
      tags:
        List.wrap(attrs[:tags]) ++
          ap_category_tags(data["tag"], creator) ++ category_mirrors,
      uploaded_media:
        Bonfire.Files.ap_receive_attachments(creator, attrs[:primary_image], attrs[:attachments])
    })
    # |> Enums.maybe_put(:primary_geolocation, ap_place(data["location"]))
    # |> Enums.maybe_put(:primary_geolocation, ap_place(data["location"], creator))
    # the links, always given (empty when the event has none) so an Update that drops one clears it
    |> Map.put(:extra_info, %{
      info: %{
        "external_participation_url" => data["externalParticipationUrl"],
        "online_address" => data["onlineAddress"]
      }
    })
    |> Enums.maybe_put(:primary_geolocation, ap_place(data["location"]))
    |> Enums.maybe_put(:place, ap_place_without_id(List.wrap(data["location"]) |> List.first()))
  end

  @doc "The IANA zone if known, else nil."
  def known_timezone(zone) when is_binary(zone),
    do: if(Tzdata.zone_exists?(zone), do: zone)

  def known_timezone(_), do: nil

  # the Geolocation the nested ingest made of the event's `Place` (Geolocate declares "Place"); an id-less Place has none
  defp ap_place([first | _]), do: ap_place(first)
  defp ap_place(%{"id" => id}), do: ap_place(id)

  # only a stored `Place` (which Geolocate makes a Geolocation): a `location` that is anything else (eg. a Note) leaves the event without a place, rather than refusing it
  defp ap_place(id) when is_binary(id) do
    with {:ok, %{pointer_id: pointer_id, data: %{"type" => "Place"}}} when is_binary(pointer_id) <-
           ActivityPub.Object.get_cached(ap_id: id) do
      %{geolocation_id: pointer_id}
    else
      _ -> nil
    end
  end

  defp ap_place(_), do: nil

  # # the Place of the nested ingest (one with an `id`), else one with no `id`, as a C2S client sends it (eg. Lauti), made a Geolocation here (Geolocate's own reading of a Place: name, summary, latitude and longitude)
  # defp ap_place(location, creator) do
  #   ap_place(location) || ap_place_without_id(List.wrap(location) |> List.first(), creator)
  # end

  # defp ap_place_without_id(%{"type" => "Place"} = place, creator)
  #      when not is_map_key(place, "id") do
  #   if place["name"] || (place["latitude"] && place["longitude"]) do
  #     case Bonfire.Common.Utils.maybe_apply(
  #            Bonfire.Geolocate.Geolocations,
  #            :ap_receive_activity,
  #            [creator, nil, %{data: place}],
  #            fallback_return: nil
  #          ) do
  #       {:ok, %{id: geolocation_id}} -> %{geolocation_id: geolocation_id}
  #       _ -> nil
  #     end
  #   end
  # end

  # a Place with no `id`, as a C2S client sends it (eg. Lauti), read as the attrs of a Geolocation (Geolocate's own reading of a Place: name, summary, latitude and longitude), which the epic's `Bonfire.Geolocate.Acts.PrimaryGeolocation` makes with the event
  defp ap_place_without_id(%{"type" => "Place"} = place) when not is_map_key(place, "id") do
    if place["name"] || (place["latitude"] && place["longitude"]) do
      Bonfire.Common.Utils.maybe_apply(Bonfire.Geolocate.Geolocations, :ap_attrs, [place],
        fallback_return: nil
      )
    end
  end

  defp ap_place_without_id(_), do: nil

  # the event's FEP-8a8e `category` values (known ones only) become tags of the local mirrors of those categories, whoever posted it
  # the values that a local poster's `Category` tags (event types or no scheme; a `…#Topic` one is a label's business) are named after, and the tags left for `ap_category_tags/2`
  defp split_value_named_tags(tags, creator) do
    tags = List.wrap(tags)

    if Bonfire.Social.is_local?(creator) do
      Enum.reduce(tags, {[], []}, fn
        %{"type" => "Category", "name" => name} = item, {keys, rest} ->
          case not topic_scheme?(item) && Bonfire.Gatherings.EventCategories.key_for_name(name) do
            key when is_binary(key) -> {[key | keys], rest}
            _ -> {keys, [item | rest]}
          end

        item, {keys, rest} ->
          {keys, [item | rest]}
      end)
      |> then(fn {keys, rest} -> {Enum.reverse(keys), Enum.reverse(rest)} end)
    else
      {[], tags}
    end
  end

  defp topic_scheme?(%{"inScheme" => scheme}) when is_binary(scheme),
    do: String.ends_with?(scheme, "#Topic")

  defp topic_scheme?(_), do: false

  defp fep_8a8e_categories(data, creator, named_keys) do
    alias Bonfire.Gatherings.EventCategories

    case Enum.uniq(
           Enum.filter(EventCategories.from_object(data), &EventCategories.known?/1) ++ named_keys
         ) do
      [] ->
        []

      # keys -> fep_8a8e_categories(keys, creator, categories_parent(creator))
      # the parent is looked up (or made) only if a category's topic is being made
      keys ->
        value_topics(keys, creator, fn -> categories_parent(creator) end)
    end
  end

  # the topic the category topics are made under, if one is configured (by its username), made the first time it is needed
  defp categories_parent(creator) do
    case Bonfire.Common.Config.get([__MODULE__, :categories_parent], nil,
           name: l("Parent of event category topics"),
           description:
             l(
               "The username of a topic that the topics made for event categories (eg. Music) are put under. None by default."
             )
         ) do
      username when is_binary(username) and username != "" ->
        case Bonfire.Common.Utils.maybe_apply(
               Bonfire.Classify.Categories,
               :get_or_create_topic,
               [%{username: username, name: String.capitalize(username)}, creator],
               fallback_return: nil
             ) do
          {:ok, parent} -> parent
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp value_topics(keys, creator, parent) do
    # alias Bonfire.Gatherings.EventCategories
    #
    # for key <- keys,
    #     {:ok, category} <- [
    #       # Bonfire.Common.Utils.maybe_apply(
    #       #   Bonfire.Classify.Categories,
    #       #   :get_or_create_mirror,
    #       #   [
    #       #     EventCategories.iri(key),
    #       #     %{name: EventCategories.label(key), username: EventCategories.username(key)},
    #       #     creator
    #       #   ],
    #       #   fallback_return: nil
    #       # )
    #       # a local topic per value, as this instance's own events use them too
    #       Bonfire.Common.Utils.maybe_apply(
    #         Bonfire.Classify.Categories,
    #         :get_or_create_topic,
    #         [
    #           %{name: EventCategories.label(key), username: EventCategories.username(key)}
    #           |> Enums.maybe_put(:parent_category, parent),
    #           creator
    #         ],
    #         fallback_return: nil
    #       )
    #     ] do
    #   category
    # end
    for key <- keys, {:ok, category} <- [value_topic(key, creator, parent, [])], do: category
  end

  # a local topic per value, as this instance's own events use them too: under the value the instance groups it under (`EventCategories.parent_key/1`), else under the parent of all of them. The parents are only looked up (or brought back, or made) when this one is being made or brought back
  defp value_topic(key, creator, root_parent, seen) do
    alias Bonfire.Gatherings.EventCategories

    if EventCategories.as_label?(key),
      do: value_label(key, creator),
      else: value_topic_under(key, creator, root_parent, seen)
  end

  # a value the instance makes a label (what an event is about): under the "Events" label, ungrouped
  defp value_label(key, creator) do
    alias Bonfire.Gatherings.EventCategories

    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Classify.Categories,
      :get_or_create_topic,
      [
        %{
          name: EventCategories.label(key),
          username: EventCategories.username(key),
          type: :label,
          parent_category: fn -> EventCategories.events_label() end
        },
        creator
      ],
      fallback_return: nil
    )
  end

  defp value_topic_under(key, creator, root_parent, seen) do
    alias Bonfire.Gatherings.EventCategories

    parent =
      case EventCategories.parent_key(key) do
        parent_key when is_binary(parent_key) ->
          # a grouping configured in a loop would never end
          if parent_key in [key | seen],
            do: root_parent,
            else: fn ->
              case value_topic(parent_key, creator, root_parent, [key | seen]) do
                {:ok, parent} -> parent
                _ -> nil
              end
            end

        _ ->
          root_parent
      end

    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Classify.Categories,
      :get_or_create_topic,
      [
        %{name: EventCategories.label(key), username: EventCategories.username(key)}
        |> Enums.maybe_put(:parent_category, parent),
        creator
      ],
      fallback_return: nil
    )
  end

  # FEP-9b2b `Category` tags become tags of local topics, only when a local user posted it for now (as `Bonfire.Social.APActivities` does)
  defp ap_category_tags(tags, creator) do
    if Bonfire.Social.is_local?(creator),
      do:
        Bonfire.Common.Utils.maybe_apply(
          Bonfire.Classify.Categories,
          :ap_receive_category_tags,
          # [List.wrap(tags), creator],
          # named as the event category topics are, and what an event is about (a `#Topic`, Lauti's "topics") a label under the "Events" label
          [
            List.wrap(tags),
            creator,
            [
              username_suffix: "_events",
              label_schemes: ["#Topic"],
              label_parent: fn -> Bonfire.Gatherings.EventCategories.events_label() end
            ]
          ],
          fallback_return: []
        ),
      else: []
  end
end
