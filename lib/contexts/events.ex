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

  @doc """
  Creates an event by running the `:create` epic configured in `Bonfire.Gatherings.RuntimeConfig`.

  Options: `current_user`, `event_attrs` (`post_content`, `time_span`, optionally `primary_geolocation`), `boundary`.
  """
  def create(options \\ []) do
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
  Lists the events the viewer may see that have not ended yet (happening now included: an end still ahead, or with no end a start still ahead), earliest start first, a page at a time.

  The time span is inner-joined (every event has one), so the order can use the index on `has_beginning`.
  """
  def list_upcoming(opts \\ []) do
    opts = to_options(opts)
    now = DateTime.utc_now()

    query_base()
    |> join(:inner, [main_object: e], ts in assoc(e, :time_span), as: :time_span)
    |> where(
      [time_span: ts],
      ts.has_end >= ^now or (is_nil(ts.has_end) and ts.has_beginning >= ^now)
    )
    |> order_by([time_span: ts, main_object: e], asc: ts.has_beginning, asc: e.id)
    |> Objects.list_paginated(
      Keyword.put(opts, :cursor_fields, [{{:time_span, :has_beginning}, :asc}, {:id, :asc}])
    )
  end

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
end
