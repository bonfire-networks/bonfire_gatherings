# was `Bonfire.Social.Events.Categories` in `bonfire_social`, with the labels of `Bonfire.UI.Social.EventCategories` merged in
defmodule Bonfire.Gatherings.EventCategories do
  @moduledoc """
  Deprecated, until how a native event holds an FEP-8a8e category is decided (possibly as topics in a scheme): until then the `/events` category chips filter by the hashtag of the same name.

  The FEP-8a8e event `category` vocabulary (controlled keys + normalisation),
  shared by federation, the event APIs, indexing and the `/events` UI. Display
  concerns (labels, icons, colours) live in the UI layer. See
  https://w3id.org/fep/8a8e.
  """
  # for `l/1`, in the labels and the "Events" label's name
  use Bonfire.Common.Localise
  use Bonfire.Common.E

  # the configured `[KEY: [name: …, icon: …], …]`, in order
  defp categories do
    require Bonfire.Common.Config

    case Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :categories], []) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp category_config(key) when is_binary(key) do
    Enum.find_value(categories(), fn {k, config} ->
      if to_string(k) == key, do: List.wrap(config)
    end)
  end

  @doc "All known category keys, in display order (the configured `categories`)."
  def all, do: for({key, _config} <- categories(), do: to_string(key))

  @doc "Whether a (normalised) key is part of the known vocabulary."
  def known?(key) when is_binary(key), do: key in all()
  def known?(_), do: false

  @doc "The icon configured for a category key (a name of the compiled icon set, eg. `ph:music-notes-fill`), or nil."
  def icon(key) when is_binary(key),
    do: category_config(key) |> then(&(&1 && Keyword.get(&1, :icon)))

  def icon(_), do: nil

  @doc "Normalise a category value to the controlled form (UPPER_SNAKE), or nil."
  def normalize(category) when is_binary(category) do
    case category |> String.trim() |> String.upcase() |> String.replace([" ", "-"], "_") do
      "" -> nil
      key -> key
    end
  end

  def normalize(_), do: nil

  @doc """
  The IRI of a category value in the FEP-8a8e vocabulary: the key a local mirror of it is found by.

      iex> Bonfire.Gatherings.EventCategories.iri("MUSIC")
      "https://w3id.org/fep/8a8e/category#MUSIC"
  """
  def iri(key) when is_binary(key), do: "https://w3id.org/fep/8a8e/category#" <> key

  @doc """
  The username of the local mirror of a category value.

      iex> Bonfire.Gatherings.EventCategories.username("MUSIC")
      "music_events"
  """
  def username(key) when is_binary(key), do: String.downcase(key) <> "_events"

  @doc """
  The category value a topic is the local mirror of (by its username, if its character is loaded), or nil.

      iex> Bonfire.Gatherings.EventCategories.key_of_topic(%{character: %{username: "music_events"}})
      "MUSIC"

      iex> Bonfire.Gatherings.EventCategories.key_of_topic(%{character: %{username: "jazz"}})
      nil
  """
  def key_of_topic(topic) do
    with username when is_binary(username) <- e(topic, :character, :username, nil),
         true <- String.ends_with?(username, "_events"),
         key = username |> String.replace_suffix("_events", "") |> String.upcase(),
         true <- known?(key) do
      key
    else
      _ -> nil
    end
  end

  @behaviour Bonfire.Common.StartupTask

  @doc "Startup task (`Bonfire.Common.StartupTasks`, off the boot path): reserves the topics' usernames (`reserve_topics/0`), skipped once every one is held, which one query checks. Not in tests, where it would race the database sandbox at boot: a test that needs the reservation calls `reserve_topics/0`."
  @impl Bonfire.Common.StartupTask
  def run do
    cond do
      Bonfire.Common.Config.env() == :test -> :ok
      all_reserved?() -> :ok
      true -> reserve_topics()
    end
  end

  defp all_reserved? do
    import Ecto.Query, only: [from: 2]
    require Bonfire.Common.Config

    parent_username =
      Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :categories_parent], nil)

    usernames =
      for(key <- all(), do: username(key)) ++
        if(is_binary(parent_username) and parent_username != "", do: [parent_username], else: [])

    Bonfire.Common.Repo.one(
      from(c in Bonfire.Data.Identity.Character,
        where: c.username in ^usernames,
        select: count(c.id)
      )
    ) == length(usernames)
  end

  @doc """
  Reserves the usernames of the topics of all the values (eg. `music_events`), under the configured parent topic (`[Bonfire.Gatherings.Events, :categories_parent]`, eg. `events`), so that nobody else takes them: they are made and archived, and an event that names a value brings its topic back (`Bonfire.Classify.Categories.reserve_topics/2`). Run by a fixtures migration; can run again.
  """
  def reserve_topics do
    require Bonfire.Common.Config

    parent_username =
      Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :categories_parent], nil)

    parent =
      if is_binary(parent_username) and parent_username != "",
        do: [%{username: parent_username, name: String.capitalize(parent_username)}],
        else: []

    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Classify.Categories,
      :reserve_topics,
      # [parent ++ for(key <- @keys, do: %{name: label(key), username: username(key)})],
      # as labels, the values the instance makes labels
      [
        parent ++
          for(
            key <- all(),
            do:
              %{name: label(key), username: username(key)}
              |> Map.merge(if(as_label?(key), do: %{type: :label}, else: %{}))
          )
      ],
      fallback_return: []
    )
    |> seed_icons()
  end

  # the icon of each topic just made, as its own setting (`[:ui, :icon]`, scoped to it), so the chips and cards show the topic's own, which an admin can change or reset. Only for the topics made now (a username already held is skipped, as is its icon).
  defp seed_icons(topics) do
    by_username = Map.new(all(), &{username(&1), &1})

    for topic <- topics do
      topic = Bonfire.Common.Repo.maybe_preload(topic, :character)

      with key when is_binary(key) <- by_username[e(topic, :character, :username, nil)],
           icon when is_binary(icon) <- icon(key) do
        Bonfire.Common.Utils.maybe_apply(
          Bonfire.Classify.Appearance,
          :set_icon,
          [topic, icon, [skip_boundary_check: true]],
          fallback_return: nil
        )
      end

      topic
    end
  end

  @doc "The id of the \"Events\" label, the parent of the labels of events (as \"Content Moderation Labels\" is of the moderation ones), under the top \"Labels\"."
  def events_label_id, do: "1ABE1SF0REVENTSANDGATHER1N"

  @doc "The \"Events\" label, made the first time it is needed."
  def events_label do
    case Bonfire.Common.Utils.maybe_apply(
           Bonfire.Label.Labels,
           :get_or_create,
           [events_label_id(), l("Events")],
           fallback_return: nil
         ) do
      {:ok, %{} = label} -> label
      _ -> nil
    end
  end

  @doc """
  Whether a value is a label (what an event is about) rather than a topic (what kind of event it is), as the instance sets it (`label: true` on the category in the `categories` list of the runtime config). A topic by default.
  """
  def as_label?(key) when is_binary(key) do
    # without the labels extension (eg. a flavour that doesn't include it) every value is a topic, as labels go under its Events label
    (category_config(key) || [])[:label] == true and
      Bonfire.Common.Extend.extension_enabled?(:bonfire_label)
  end

  def as_label?(_), do: false

  @doc """
  The value a value's topic is put under, if the instance groups them (`parent: "ARTS"` on the category in the `categories` list of the runtime config), or nil: then it is under the parent topic of all of them. Flat by default.
  """
  def parent_key(key) when is_binary(key) do
    case (category_config(key) || [])[:parent] do
      parent when is_binary(parent) and parent != "" -> parent
      parent when is_atom(parent) and not is_nil(parent) -> to_string(parent)
      _ -> nil
    end
  end

  def parent_key(_), do: nil

  @doc """
  The value a category's name stands for, if it is one: the value itself in any case or spelling (`"music"`, `"food-drink"`), or its name, ignoring case (`"food & drink"`). Else nil.

  This is for ingest, where there is no viewer: a name matches in English (the source text) or in the instance's default language, never in the process locale.

      iex> Bonfire.Gatherings.EventCategories.key_for_name("music")
      "MUSIC"

      iex> Bonfire.Gatherings.EventCategories.key_for_name("food & drink")
      "FOOD_DRINK"

      iex> Bonfire.Gatherings.EventCategories.key_for_name("concert")
      nil
  """
  def key_for_name(name) when is_binary(name) do
    key = normalize(name)

    if known?(key) do
      key
    else
      wanted = name |> String.trim() |> String.downcase()
      # the source (English) name or the instance's default language's one
      Gettext.with_locale(
        Bonfire.Common.Localise.Gettext,
        Bonfire.Common.Localise.default_locale(),
        fn ->
          Enum.find(all(), fn key ->
            wanted in [
              String.downcase(source_name(key)),
              String.downcase(label(key))
            ]
          end)
        end
      )
    end
  end

  def key_for_name(_), do: nil

  @doc "Normalised, de-duplicated categories from an AS2 `Event` map (flat or nested)."
  def from_object(json) when is_map(json) do
    (object_field(json, "category") || object_field(json, "https://w3id.org/fep/8a8e/category"))
    |> List.wrap()
    |> Enum.map(&normalize/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def from_object(_), do: []

  defp object_field(json, field) do
    get_in(json, ["object", field]) || Map.get(json, field)
  end

  def label(key) when is_binary(key) do
    case category_config(key) do
      config when is_list(config) ->
        # the configured name is the source text (extracted from the `l()` in the runtime config, in this extension's domain), translated here for the viewer's locale, as `Bonfire.Boundaries.Verbs.verb_name/1` does
        case Keyword.get(config, :name) do
          name when is_binary(name) and name != "" -> localise_dynamic(name, __MODULE__)
          _ -> humanise(key)
        end

      nil ->
        humanise(key)
    end
  end

  # the name as configured, untranslated
  defp source_name(key) do
    case category_config(key) do
      config when is_list(config) ->
        case Keyword.get(config, :name) do
          name when is_binary(name) and name != "" -> name
          _ -> humanise(key)
        end

      nil ->
        humanise(key)
    end
  end

  defp humanise(key),
    do: key |> String.downcase() |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)
end
