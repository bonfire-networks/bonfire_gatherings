defmodule Bonfire.Gatherings.LiveHandler do
  @moduledoc "`create_event` from the composer, as `Bonfire.Poll.LiveHandler` handles `create_poll`."
  use Bonfire.UI.Common.Web, :live_handler

  alias Bonfire.Gatherings.Events
  alias Bonfire.Gatherings.Web.NewEventButtonLive

  def handle_event("create_event", %{"post" => post_params} = params, socket) do
    handle_event("create_event", Map.merge(Map.drop(params, ["post"]), post_params), socket)
  end

  def handle_event("create_event", params, socket) do
    current_user = current_user_required!(socket)

    {to_circles, verb_grants} =
      maybe_apply(Bonfire.Posts.LiveHandler, :transform_circles_for_backend, [params],
        fallback_return: {[], []}
      )

    with true <-
           NewEventButtonLive.local_creation?() ||
             {:error, l("Creating events is not enabled on this instance")},
         {:ok, event_attrs} <- event_attrs(params),
         # an upload placed in the description gets its stored URL there
         {event_attrs, uploaded_media} =
           Bonfire.UI.Common.live_upload_files_into(
             event_attrs,
             current_user,
             params["upload_metadata"],
             socket
           ),
         # {event_attrs, place} =
         #   event_attrs
         #   |> Map.put(:uploaded_media, uploaded_media)
         #   |> maybe_put_place(trimmed(params["place"]), current_user),
         # the place is made by the epic, with the event
         event_attrs =
           event_attrs
           |> Map.put(:uploaded_media, uploaded_media)
           |> Map.put(:place, trimmed(params["place"])),
         {:ok, event} <-
           Events.create(
             current_user: current_user,
             event_attrs: event_attrs,
             boundary: e(params, "to_boundaries", nil) |> List.wrap() |> List.first(),
             to_circles: to_circles,
             verb_grants: verb_grants,
             context_id: e(params, "context_id", nil)
           ) do
      # |> drop_place_on_error(place) do
      {:noreply,
       socket
       |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()
       |> assign_flash(
         :info,
         "<span>#{l("Posted!")}</span> <a href='#{path(event)}' target='_top' class='ml-2 link link-hover font-medium text-primary'>#{l("Show")} →</a>"
       )}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, assign_error(socket, message)}

      other ->
        error(other, "Could not create the event")
        {:noreply, assign_error(socket, l("Could not create your event"))}
    end
  end

  defp event_attrs(params) do
    name = params |> e("post_content", "name", nil) |> trimmed()
    starts = Bonfire.Common.DatesTimes.to_date_time(trimmed(params["starts_at"]))
    ends = Bonfire.Common.DatesTimes.to_date_time(trimmed(params["ends_at"]))

    cond do
      is_nil(name) ->
        {:error, l("Give the event a name")}

      is_nil(starts) ->
        {:error, l("Pick when the event starts")}

      ends && DateTime.compare(ends, starts) == :lt ->
        {:error, l("The event cannot end before it starts")}

      true ->
        {:ok,
         %{
           post_content: %{name: name, html_body: e(params, "post_content", "html_body", nil)},
           time_span: %{
             has_beginning: starts,
             has_end: ends,
             timezone: Events.known_timezone(trimmed(params["timezone"]))
           }
         }}
    end
  end

  # defp maybe_put_place(attrs, nil, _user), do: {attrs, nil}

  # defp maybe_put_place(attrs, place, user) do
  #   case maybe_apply(Bonfire.Geolocate.Geolocations, :create, [
  #          user,
  #          %{name: place, mappable_address: place}
  #        ]) do
  #     {:ok, geo} -> {Map.put(attrs, :primary_geolocation, %{geolocation_id: geo.id}), geo}
  #     _ -> {attrs, nil}
  #   end
  # end

  # # the epic runs its acts in tasks, so it cannot share a transaction with the place: a place made for an event that failed is removed instead
  # defp drop_place_on_error({:error, _} = error, %{} = place) do
  #   maybe_apply(Bonfire.Geolocate.Geolocations, :soft_delete, [place, []])
  #   error
  # end

  # defp drop_place_on_error(result, _place), do: result

  defp trimmed(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end

  defp trimmed(_), do: nil
end
