defmodule Bonfire.Gatherings.Web.HomeLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  declare_extension(
    "ExtensionTemplate",
    icon: "bi:app",
    description: l("Orginisation of events"),
    default_nav: [
      Bonfire.Gatherings.Web.HomeLive,
      Bonfire.Gatherings.Web.AboutLive
    ]
  )

  declare_nav_link(l("Home"), page: "home", icon: "healthicons:community-meeting", emoji: "🗓️")

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       page: "extension_template",
       page_title: "ExtensionTemplate"
     )}
  end

  def handle_event(
        "custom_event",
        _attrs,
        socket
      ) do
    # handle the event here
    {:noreply, socket}
  end
end
