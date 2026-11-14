if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  # was `Bonfire.Social.Events.MastoEventsController` in `bonfire_social`
  defmodule Bonfire.Gatherings.API.MastoEventsController do
    @moduledoc "Mastodon-compatible events REST endpoints. Deprecated, until the native refactor: they serve events stored as APActivities."

    use Bonfire.UI.Common.Web, :controller

    alias Bonfire.Gatherings.API.APActivityEventsMastoAdapter, as: EventsAdapter

    def events_timeline(conn, params), do: EventsAdapter.list_events(params, conn)

    def user_events(conn, %{"id" => user_id} = params),
      do: EventsAdapter.list_user_events(user_id, params, conn)

    def show(conn, %{"id" => id}), do: EventsAdapter.show_event(id, conn)
  end
end
