defmodule Bonfire.Gatherings.EventCategoriesTest do
  @moduledoc "The FEP-8a8e categories as the one ordered list in the runtime config: key, name and icon, and the icon seeded into each topic made for them."
  use Bonfire.Gatherings.DataCase, async: false
  use Bonfire.Common.Repo

  require Repatch
  alias Bonfire.Gatherings.EventCategories

  @in_order ~w(
    MUSIC ARTS FOOD_DRINK PARTY FESTIVALS COMMUNITY MEETING MOVEMENTS_POLITICS
    SPORTS LEARNING SCIENCE_TECH FILM_MEDIA PERFORMING_VISUAL_ARTS THEATRE GAMES
    NETWORKING BUSINESS CAUSES CLIMATE_ENVIRONMENT MEDITATION_WELLBEING
    OUTDOORS_ADVENTURE FAMILY_EDUCATION LANGUAGE_CULTURE LGBTQ INCLUSIVE_SPACES
    CRAFTS CREATIVE_JAM DIY_MAKER_SPACES WORKSHOPS_SKILL_SHARING FASHION_BEAUTY
    PHOTOGRAPHY BOOK_CLUBS COMEDY PETS SPIRITUALITY_RELIGION_BELIEFS AUTO_BOAT_AIR
  )

  test "all/0 is the configured keys, in the configured order" do
    assert EventCategories.all() == @in_order
  end

  test "each key has a name and an icon in the config" do
    for key <- EventCategories.all() do
      assert is_binary(EventCategories.label(key)) and EventCategories.label(key) != ""
      assert "ph:" <> _ = EventCategories.icon(key)
    end

    assert EventCategories.label("MUSIC") == "Music"
    assert EventCategories.label("FOOD_DRINK") == "Food & Drink"
    assert EventCategories.icon("MUSIC") == "ph:music-notes-fill"
    # a key that is not configured: its name humanised, no icon
    assert EventCategories.label("SOME_NEW_THING") == "Some New Thing"
    assert EventCategories.icon("SOME_NEW_THING") == nil
  end

  describe "names are translated for the viewer's locale at render time" do
    # no `bonfire_gatherings` catalogue has a translation yet, so the lookup is stubbed: it must ask the extension's own gettext domain with the English source text, under the viewer's locale
    setup do
      Repatch.patch(
        Bonfire.Common.Localise.Gettext,
        :lgettext,
        [mode: :shared],
        fn
          "fr", "bonfire_gatherings", _context, "Music", _bindings ->
            {:ok, "Musique"}

          "fr", "bonfire_gatherings", _context, "Food & Drink", _bindings ->
            {:ok, "Cuisine"}

          locale, domain, context, msgid, bindings ->
            Repatch.real(
              Bonfire.Common.Localise.Gettext.lgettext(locale, domain, context, msgid, bindings)
            )
        end
      )

      on_exit(fn -> Gettext.put_locale(Bonfire.Common.Localise.Gettext, "en") end)
      :ok
    end

    test "label/1 gives the viewer's locale's name, and the English one in English" do
      Gettext.put_locale(Bonfire.Common.Localise.Gettext, "fr")
      assert EventCategories.label("MUSIC") == "Musique"
      # no translation: the source text
      assert EventCategories.label("ARTS") == "Arts"
      # not configured: humanised, not looked up
      assert EventCategories.label("SOME_NEW_THING") == "Some New Thing"

      Gettext.put_locale(Bonfire.Common.Localise.Gettext, "en")
      assert EventCategories.label("MUSIC") == "Music"
    end

    test "key_for_name/1 finds a category by its English name or its name in the instance's default language, not the process locale" do
      default_key = [:bonfire_common, Bonfire.Common.Localise.Cldr, :default_locale]

      # instance default fr, process locale en
      Process.put(default_key, "fr")
      Gettext.put_locale(Bonfire.Common.Localise.Gettext, "en")
      assert EventCategories.key_for_name("Musique") == "MUSIC"
      assert EventCategories.key_for_name("musique") == "MUSIC"
      assert EventCategories.key_for_name("Music") == "MUSIC"
      assert EventCategories.key_for_name("food & drink") == "FOOD_DRINK"
      assert EventCategories.key_for_name("cuisine") == "FOOD_DRINK"
      assert EventCategories.key_for_name("concert") == nil
      # the process locale is left as it was
      assert Gettext.get_locale(Bonfire.Common.Localise.Gettext) == "en"

      # instance default en, process locale fr: the process locale is ignored
      Process.put(default_key, "en")
      Gettext.put_locale(Bonfire.Common.Localise.Gettext, "fr")
      assert EventCategories.key_for_name("Music") == "MUSIC"
      assert EventCategories.key_for_name("Musique") == nil
      assert EventCategories.key_for_name("cuisine") == nil
    end
  end

  test "every configured icon is in the compiled icon set" do
    css = File.read!(Path.join(Iconify.static_path(), "icons.css"))

    missing =
      for key <- EventCategories.all(),
          icon = EventCategories.icon(key),
          not String.contains?(css, ~s([iconify="#{icon}"])),
          do: {key, icon}

    assert missing == []
  end

  test "every configured icon is one the topic icon picker offers" do
    offered = Bonfire.UI.Common.IconPickerLive.curated_icons()

    assert for(key <- EventCategories.all(), EventCategories.icon(key) not in offered, do: key) ==
             []
  end

  describe "grouping and labels are read from the same list" do
    test "parent_key/1 is the `parent` of the category in the list" do
      Process.put(
        [:bonfire_gatherings, Bonfire.Gatherings.Events, :categories],
        PARTY: [name: "Party", icon: "ph:confetti-fill"],
        MUSIC: [name: "Music", icon: "ph:music-notes-fill", parent: "PARTY"],
        ARTS: [name: "Arts", icon: "ph:palette-fill"]
      )

      assert EventCategories.parent_key("MUSIC") == "PARTY"
      assert EventCategories.parent_key("ARTS") == nil
      assert EventCategories.parent_key("PARTY") == nil
    end

    test "as_label?/1 is the `label` flag of the category in the list" do
      Process.put(
        [:bonfire_gatherings, Bonfire.Gatherings.Events, :categories],
        MEETING: [name: "Meeting", icon: "ph:users-fill"],
        PETS: [name: "Pets", icon: "ph:paw-print-fill", label: true]
      )

      refute EventCategories.as_label?("MEETING")
      # as labels need the labels extension
      assert EventCategories.as_label?("PETS") ==
               Bonfire.Common.Extend.extension_enabled?(:bonfire_label)
    end

    test "the defaults in the list: Music is under Arts, Meeting is a label" do
      assert EventCategories.parent_key("MUSIC") == "ARTS"
      assert EventCategories.parent_key("SPORTS") == "OUTDOORS_ADVENTURE"
      assert EventCategories.parent_key("ARTS") == nil

      assert EventCategories.as_label?("MEETING") ==
               Bonfire.Common.Extend.extension_enabled?(:bonfire_label)

      refute EventCategories.as_label?("MUSIC")
    end
  end

  test "an instance's own list, in its runtime config, replaces the default" do
    Process.put(
      [:bonfire_gatherings, Bonfire.Gatherings.Events, :categories],
      OPERA: [name: "Opera", icon: "ph:microphone-stage-fill"]
    )

    assert EventCategories.all() == ["OPERA"]
    assert EventCategories.label("OPERA") == "Opera"
    assert EventCategories.known?("OPERA")
    refute EventCategories.known?("MUSIC")
  end

  # the fixtures migration has already made the topics of the default categories, and a username already held is skipped, so this uses categories of its own
  test "the topic made for a category gets its icon as its own setting, a label too" do
    Process.put(
      [:bonfire_gatherings, Bonfire.Gatherings.Events, :categories],
      OPERA: [name: "Opera", icon: "ph:microphone-stage-fill"],
      BALLET: [name: "Ballet", icon: "ph:person-simple-run-fill", label: true]
    )

    EventCategories.reserve_topics()

    assert {:ok, %{id: id}} = Bonfire.Classify.Categories.get_archived("opera_events")
    opera = repo().preload(%Bonfire.Classify.Category{id: id}, :settings)
    assert Bonfire.Classify.Appearance.icon(opera) == "ph:microphone-stage-fill"

    assert {:ok, %{id: ballet_id}} = Bonfire.Classify.Categories.get_archived("ballet_events")
    ballet = repo().preload(%Bonfire.Classify.Category{id: ballet_id}, :settings)
    assert Bonfire.Classify.Appearance.icon(ballet) == "ph:person-simple-run-fill"
  end
end
