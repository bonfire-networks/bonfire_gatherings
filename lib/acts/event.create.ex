defmodule Bonfire.Gatherings.Event.Create do
  @moduledoc """
  Builds the initial `Bonfire.Gatherings.Event` changeset for the event-creation epic and registers it for insertion via `Bonfire.Ecto.Acts.Work`.

  Epic Options:
    * `:current_user` — user that will create the event, required.
    * `:event_attrs` (configurable) — attrs to create the event from, required.

  Act Options:
    * `:on` — key to assign the changeset to, default: `:event`.
    * `:attrs` — epic options key to find the attributes at, default: `:event_attrs`.
  """

  alias Bonfire.Ecto.Acts.Work
  alias Bonfire.Epics.Epic
  alias Bonfire.Gatherings.Events

  use Arrows
  import Bonfire.Epics

  @doc false
  def run(epic, act) do
    current_user = Bonfire.Common.Utils.current_user_or_id(epic.assigns[:options])

    cond do
      epic.errors != [] ->
        maybe_debug(epic, act, length(epic.errors), "Skipping due to epic errors")
        epic

      not (is_struct(current_user) or is_binary(current_user)) ->
        maybe_debug(epic, act, current_user, "Skipping due to missing current_user")
        epic

      true ->
        as = Keyword.get(act.options, :as) || Keyword.get(act.options, :on, :event)
        attrs_key = Keyword.get(act.options, :attrs, :event_attrs)
        attrs = Keyword.get(epic.assigns[:options], attrs_key, %{})

        maybe_debug(epic, act, attrs_key, "Assigning changeset to :#{as} using attrs")

        Events.base_changeset(attrs)
        |> maybe_put_id(attrs[:id])
        |> Map.put(:action, :insert)
        |> Epic.assign(epic, as, ...)
        |> Work.add(:event)
    end
  end

  # an id already reserved for the event (eg. by the AP object it was posted as), else one is generated
  defp maybe_put_id(changeset, id) when is_binary(id),
    do: Ecto.Changeset.put_change(changeset, :id, id)

  defp maybe_put_id(changeset, _), do: changeset
end
