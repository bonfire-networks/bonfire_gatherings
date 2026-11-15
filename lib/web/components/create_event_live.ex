defmodule Bonfire.Gatherings.Web.CreateEventLive do
  @moduledoc "The composer's event form, as `CreatePollLive` is for polls."
  use Bonfire.UI.Common.Web, :stateless_component
  alias Surface.Components.Form

  prop reply_to_id, :any, default: nil
  prop context_id, :string, default: nil
  prop create_object_type, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []
  prop smart_input_opts, :map, default: %{}
  prop showing_within, :atom, default: nil
  prop insert_text, :string, default: nil
  prop preloaded_recipients, :any, default: nil
  prop uploads, :any, default: nil
  prop uploaded_files, :list, default: nil
  prop selected_cover, :any, default: nil
  prop title_prompt, :string, default: nil
  prop thread_mode, :any, default: nil
  prop open_boundaries, :boolean, default: false
  prop boundaries_modal_id, :string, default: :sidebar_composer
  prop textarea_container_class, :css_class
  prop textarea_container_class_alpine, :string
  prop textarea_class, :css_class
  prop event_target, :any, default: nil
  prop composer_policy, :map, default: nil

  @behaviour Bonfire.UI.Common.SmartInputModule
  def smart_input_module, do: [:event, Bonfire.Gatherings.Event]

  def smart_input_icon(_), do: "ph:calendar-blank-duotone"
  def smart_input_label(_), do: l("Event")

  @doc "Offered only where the instance allows creating events."
  def smart_input_tray?, do: Bonfire.Gatherings.Web.NewEventButtonLive.local_creation?()
end
