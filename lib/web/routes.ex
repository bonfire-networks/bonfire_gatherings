defmodule Bonfire.Gatherings.Web.Routes do
  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/gatherings/", Bonfire.Gatherings.Web do
        pipe_through(:browser)

        live("/", HomeLive)
        live("/about", AboutLive)
      end

      # upcoming events, and those tagged with a topic (named by its username, or its id if it has no character); moved from `bonfire_ui_social`
      scope "/", Bonfire.Gatherings.Web do
        pipe_through(:browser)

        live("/events", EventsLive, as: :events)
        live("/events/past", EventsLive, :past, as: :events)
        live("/events/category/:category_ref", EventsLive, as: :events)
        live("/events/category/:category_ref/past", EventsLive, :past, as: :events)
        # the upcoming events on a map, filtered as the list is
        live("/events/map", EventsLive, :map, as: :events)
        live("/events/category/:category_ref/map", EventsLive, :map, as: :events)
        live("/events/label/:label_ref/map", EventsLive, :map, as: :events)
        live("/events/category/:category_ref/label/:label_ref/map", EventsLive, :map, as: :events)
        # by a label (what events are about), alone or with a category
        live("/events/label/:label_ref", EventsLive, as: :events)
        live("/events/label/:label_ref/past", EventsLive, :past, as: :events)
        live("/events/category/:category_ref/label/:label_ref", EventsLive, as: :events)

        live("/events/category/:category_ref/label/:label_ref/past", EventsLive, :past,
          as: :events
        )
      end

      # the events of the people I follow and my own (signed in only), upcoming and past, with the same category and label pages as the list of all events
      scope "/", Bonfire.Gatherings.Web do
        pipe_through(:browser)
        pipe_through(:user_required)

        live("/events/my", EventsLive, :my, as: :events)
        live("/events/my/past", EventsLive, :my_past, as: :events)
        live("/events/my/map", EventsLive, :my_map, as: :events)
        live("/events/my/category/:category_ref/map", EventsLive, :my_map, as: :events)
        live("/events/my/label/:label_ref/map", EventsLive, :my_map, as: :events)

        live("/events/my/category/:category_ref/label/:label_ref/map", EventsLive, :my_map,
          as: :events
        )

        live("/events/my/category/:category_ref", EventsLive, :my, as: :events)
        live("/events/my/category/:category_ref/past", EventsLive, :my_past, as: :events)
        live("/events/my/label/:label_ref", EventsLive, :my, as: :events)
        live("/events/my/label/:label_ref/past", EventsLive, :my_past, as: :events)
        live("/events/my/category/:category_ref/label/:label_ref", EventsLive, :my, as: :events)

        live("/events/my/category/:category_ref/label/:label_ref/past", EventsLive, :my_past,
          as: :events
        )
      end

      # pages only guests can view
      scope "/gatherings/", Bonfire.Gatherings.Web do
        pipe_through(:browser)
        pipe_through(:guest_only)
      end

      # pages you need an account to view
      scope "/gatherings/", Bonfire.Gatherings.Web do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need to view as a user
      scope "/gatherings/", Bonfire.Gatherings.Web do
        pipe_through(:browser)
        pipe_through(:user_required)
        live("/new", NewLive)
      end

      # pages only admins can view
      scope "/gatherings/admin", Bonfire.Gatherings.Web do
        pipe_through(:browser)
        pipe_through(:admin_required)
      end
    end
  end
end
