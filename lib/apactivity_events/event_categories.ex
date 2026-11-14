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

  # ordered popular-first (also drives the UI's "Browse by Category" grid order)
  @keys ~w(
    MUSIC ARTS FOOD_DRINK PARTY FESTIVALS COMMUNITY MEETING MOVEMENTS_POLITICS
    SPORTS LEARNING SCIENCE_TECH FILM_MEDIA PERFORMING_VISUAL_ARTS THEATRE GAMES
    NETWORKING BUSINESS CAUSES CLIMATE_ENVIRONMENT MEDITATION_WELLBEING
    OUTDOORS_ADVENTURE FAMILY_EDUCATION LANGUAGE_CULTURE LGBTQ INCLUSIVE_SPACES
    CRAFTS CREATIVE_JAM DIY_MAKER_SPACES WORKSHOPS_SKILL_SHARING FASHION_BEAUTY
    PHOTOGRAPHY BOOK_CLUBS COMEDY PETS SPIRITUALITY_RELIGION_BELIEFS AUTO_BOAT_AIR
  )

  @doc "All known category keys, in display order."
  def all, do: @keys

  @doc "Whether a (normalised) key is part of the known vocabulary."
  def known?(key) when is_binary(key), do: key in @keys
  def known?(_), do: false

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

  @behaviour Bonfire.Common.StartupTask

  @doc "Startup task (`Bonfire.Common.StartupTasks`, off the boot path): reserves the topics' usernames (`reserve_topics/0`), skipped once every one is held, which one query checks."
  @impl Bonfire.Common.StartupTask
  def run do
    if all_reserved?(), do: :ok, else: reserve_topics()
  end

  defp all_reserved? do
    import Ecto.Query, only: [from: 2]
    require Bonfire.Common.Config

    parent_username =
      Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :categories_parent], nil)

    usernames =
      for(key <- @keys, do: username(key)) ++
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
            key <- @keys,
            do:
              %{name: label(key), username: username(key)}
              |> Map.merge(if(as_label?(key), do: %{type: :label}, else: %{}))
          )
      ],
      fallback_return: []
    )
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
  Whether a value is a label (what an event is about) rather than a topic (what kind of event it is), as the instance sets it (`config :bonfire_gatherings, Bonfire.Gatherings.Events, categories_as_labels: [...]`). None by default.
  """
  def as_label?(key) when is_binary(key) do
    require Bonfire.Common.Config

    key in List.wrap(
      Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :categories_as_labels], [])
    )
  end

  @doc """
  The value a value's topic is put under, if the instance groups them (`config :bonfire_gatherings, Bonfire.Gatherings.Events, categories_nesting: %{"ARTS" => ["THEATRE", "COMEDY"]}`), or nil: then it is under the parent topic of all of them. Flat by default.
  """
  def parent_key(key) when is_binary(key) do
    require Bonfire.Common.Config

    Bonfire.Common.Config.get([Bonfire.Gatherings.Events, :categories_nesting], %{})
    |> Enum.find_value(fn {parent, children} ->
      if key in List.wrap(children), do: to_string(parent)
    end)
  end

  @doc """
  The value a category's name stands for, if it is one: the value itself in any case or spelling (`"music"`, `"food-drink"`), or its label, ignoring case (`"food & drink"`). Else nil.

      iex> Bonfire.Gatherings.EventCategories.key_for_name("music")
      "MUSIC"

      iex> Bonfire.Gatherings.EventCategories.key_for_name("food & drink")
      "FOOD_DRINK"

      iex> Bonfire.Gatherings.EventCategories.key_for_name("concert")
      nil
  """
  def key_for_name(name) when is_binary(name) do
    key = normalize(name)

    if key in @keys do
      key
    else
      wanted = name |> String.trim() |> String.downcase()
      Enum.find(@keys, &(String.downcase(label(&1)) == wanted))
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

  # the labels, from `Bonfire.UI.Social.EventCategories` (which only the old `/events` page used)
  # use Bonfire.Common.Localise
  # (moved to the top of the module, as `events_label/0` uses `l/1` too)

  @doc "Localised label for a category key (humanises unknown keys)."
  def label("ARTS"), do: l("Arts")
  def label("AUTO_BOAT_AIR"), do: l("Auto, Boat & Air")
  def label("BOOK_CLUBS"), do: l("Book Clubs")
  def label("BUSINESS"), do: l("Business")
  def label("CAUSES"), do: l("Causes")
  def label("CLIMATE_ENVIRONMENT"), do: l("Climate & Environment")
  def label("COMMUNITY"), do: l("Community")
  def label("COMEDY"), do: l("Comedy")
  def label("CRAFTS"), do: l("Crafts")
  def label("CREATIVE_JAM"), do: l("Creative Jam")
  def label("DIY_MAKER_SPACES"), do: l("DIY & Maker Spaces")
  def label("FAMILY_EDUCATION"), do: l("Family & Education")
  def label("FASHION_BEAUTY"), do: l("Fashion & Beauty")
  def label("FESTIVALS"), do: l("Festivals")
  def label("FILM_MEDIA"), do: l("Film & Media")
  def label("FOOD_DRINK"), do: l("Food & Drink")
  def label("GAMES"), do: l("Games")
  def label("INCLUSIVE_SPACES"), do: l("Inclusive Spaces")
  def label("LANGUAGE_CULTURE"), do: l("Language & Culture")
  def label("LEARNING"), do: l("Learning")
  def label("LGBTQ"), do: l("LGBTQ")
  def label("MEETING"), do: l("Meeting")
  def label("MEDITATION_WELLBEING"), do: l("Meditation & Wellbeing")
  def label("MOVEMENTS_POLITICS"), do: l("Movements & Politics")
  def label("MUSIC"), do: l("Music")
  def label("NETWORKING"), do: l("Networking")
  def label("OUTDOORS_ADVENTURE"), do: l("Outdoors & Adventure")
  def label("PARTY"), do: l("Party")
  def label("PERFORMING_VISUAL_ARTS"), do: l("Performing & Visual Arts")
  def label("PETS"), do: l("Pets")
  def label("PHOTOGRAPHY"), do: l("Photography")
  def label("SCIENCE_TECH"), do: l("Science & Tech")
  def label("SPIRITUALITY_RELIGION_BELIEFS"), do: l("Spirituality & Beliefs")
  def label("SPORTS"), do: l("Sports")
  def label("THEATRE"), do: l("Theatre")
  def label("WORKSHOPS_SKILL_SHARING"), do: l("Workshops & Skill-sharing")

  def label(key) when is_binary(key) do
    key |> String.downcase() |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)
  end
end
