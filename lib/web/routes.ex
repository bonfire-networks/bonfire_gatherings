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
