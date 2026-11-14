defmodule Bonfire.Gatherings.EventsTest do
  @moduledoc "Creating, reading and listing events through the `Bonfire.Gatherings.Events` context."
  use Bonfire.Gatherings.DataCase, async: true

  import Bonfire.Me.Fake
  alias Bonfire.Common.Repo
  alias Bonfire.Gatherings.Event
  alias Bonfire.Gatherings.Events

  @begin ~U[2030-06-01 18:00:00.000000Z]
  @end_ ~U[2030-06-01 23:00:00.000000Z]

  defp event_attrs(extra \\ %{}) do
    Map.merge(
      %{
        post_content: %{name: "Garden party", summary: "Bring snacks"},
        time_span: %{has_beginning: @begin, has_end: @end_}
      },
      extra
    )
  end

  defp create!(user, attrs \\ event_attrs(), boundary \\ "public") do
    assert {:ok, event} =
             Events.create(current_user: user, event_attrs: attrs, boundary: boundary)

    event
  end

  test "an event is created with its name, dates and creator" do
    user = fake_user!()
    event = create!(user)

    assert %{
             post_content: %{name: "Garden party", summary: "Bring snacks"},
             time_span: %{has_beginning: b, has_end: e},
             created: %{creator_id: creator_id}
           } = Event |> Repo.get!(event.id) |> Repo.preload([:post_content, :time_span, :created])

    assert DateTime.compare(b, @begin) == :eq
    assert DateTime.compare(e, @end_) == :eq
    assert creator_id == user.id
  end

  test "an event is created with a place, and read back with its geolocation" do
    user = fake_user!()
    geo = Bonfire.Geolocate.Simulate.fake_geolocation!(user)

    event = create!(user, event_attrs(%{primary_geolocation: %{geolocation_id: geo.id}}))

    assert %{primary_geolocation: %{geolocation: %{id: geo_id}}} =
             Event |> Repo.get!(event.id) |> Repo.preload(primary_geolocation: :geolocation)

    assert geo_id == geo.id
  end

  test "reading an event follows its boundary" do
    user = fake_user!()
    other = fake_user!()

    public = create!(user)
    private = create!(user, event_attrs(), "mentions")

    assert {:ok, %Event{}} = Events.read(public.id, current_user: other)
    assert {:ok, %Event{}} = Events.read(public.id, [])

    assert {:ok, %Event{}} = Events.read(private.id, current_user: user)
    assert {:error, _} = Events.read(private.id, current_user: other)
  end

  test "events are listed" do
    user = fake_user!()
    event = create!(user)

    assert %{edges: edges} = Events.list_paginated([], current_user: user)
    assert event.id in Enum.map(edges, &(Bonfire.Common.Enums.id(&1) || &1.id))
  end

  test "upcoming lists events not yet ended, happening now included, earliest start first" do
    user = fake_user!()
    now = DateTime.utc_now()
    at = fn hours -> DateTime.add(now, hours * 3600, :second) end

    span = fn name, b, e ->
      create!(
        user,
        event_attrs(%{post_content: %{name: name}, time_span: %{has_beginning: b, has_end: e}})
      )
    end

    ended = span.("ended", at.(-72), at.(-48))
    started_no_end = span.("started, no end", at.(-24), nil)
    ongoing = span.("ongoing", at.(-1), at.(1))
    later_no_end = span.("in two days, no end", at.(48), nil)
    tomorrow = span.("tomorrow", at.(24), at.(26))

    ids = fn %{edges: edges} -> Enum.map(edges, &(Bonfire.Common.Enums.id(&1) || &1.id)) end

    # pages hold 2 in tests, so the second page also checks the cursor on the joined start date
    assert %{page_info: %{end_cursor: cursor}} = page_1 = Events.list_upcoming(current_user: user)
    assert ids.(page_1) == [ongoing.id, tomorrow.id]

    page_2 = Events.list_upcoming(current_user: user, after: cursor)
    assert later_no_end.id in ids.(page_2)

    seen = ids.(page_1) ++ ids.(page_2)
    refute ended.id in seen
    refute started_no_end.id in seen
  end

  test "past lists events that have ended, most recent first" do
    user = fake_user!()
    now = DateTime.utc_now()
    at = fn hours -> DateTime.add(now, hours * 3600, :second) end

    span = fn name, b, e ->
      create!(
        user,
        event_attrs(%{post_content: %{name: name}, time_span: %{has_beginning: b, has_end: e}})
      )
    end

    last_week = span.("last week", at.(-170), at.(-168))
    yesterday = span.("yesterday", at.(-26), at.(-24))
    started_no_end = span.("started yesterday, no end", at.(-24), nil)
    ongoing = span.("ongoing", at.(-1), at.(1))
    tomorrow = span.("tomorrow", at.(24), at.(26))

    ids = fn %{edges: edges} -> Enum.map(edges, &(Bonfire.Common.Enums.id(&1) || &1.id)) end

    # pages hold 2 in tests, so the second page also checks the cursor
    assert %{page_info: %{end_cursor: cursor}} = page_1 = Events.list_past(current_user: user)
    assert ids.(page_1) == [started_no_end.id, yesterday.id]
    assert ids.(Events.list_past(current_user: user, after: cursor)) == [last_week.id]

    refute ongoing.id in ids.(page_1)
    refute tomorrow.id in ids.(page_1)
  end

  test "creating an event publishes an activity by its creator, and starts a thread" do
    user = fake_user!()
    event = create!(user)

    assert %{subject_id: subject_id} =
             Repo.one(from(a in Bonfire.Data.Social.Activity, where: a.object_id == ^event.id))

    assert subject_id == user.id

    assert %{thread_id: thread_id} = Repo.get!(Bonfire.Data.Social.Replied, event.id)
    assert thread_id == event.id
  end

  test "an event needs a start" do
    user = fake_user!()

    # the reason: the start is required by the event's changeset (the shared mixin leaves it optional)
    changeset = Event.changeset(%{time_span: %{has_beginning: nil}})
    refute changeset.valid?

    assert %{time_span: %{has_beginning: ["can't be blank"]}} =
             Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)

    assert Event.changeset(%{time_span: %{has_beginning: @begin}}).valid?

    assert {:error, _} =
             Events.create(
               current_user: user,
               event_attrs: event_attrs(%{time_span: %{has_beginning: nil}}),
               boundary: "public"
             )
  end

  test "the category facets keep their limit for topics and for labels apart" do
    user = fake_user!()
    topic = Bonfire.Classify.Simulate.fake_category!(user, nil, %{type: :topic, name: "Gigs"})

    {:ok, label} =
      Bonfire.Classify.Categories.get_or_create_topic(
        %{
          name: "Outdoors",
          username: "outdoors_#{System.unique_integer([:positive])}",
          type: :label
        },
        user
      )

    create!(user, event_attrs(%{tags: [topic, label]}))

    ids = Events.category_facets_without_cache(:upcoming, 1)
    assert topic.id in ids
    assert label.id in ids
  end

  test "the usernames of the FEP-8a8e category topics and their parent are reserved, as archived topics, until an event uses them" do
    # idempotent: the fixtures migration has already run it
    # Bonfire.Gatherings.EventCategories.reserve_topics()
    # a startup task, run off the boot path on every boot (so a run that was interrupted is tried again), cheap to skip once done
    assert Bonfire.Gatherings.EventCategories in Bonfire.Common.StartupTasks.tasks()
    Bonfire.Gatherings.EventCategories.run()

    assert {:error, _} =
             Bonfire.Classify.Categories.get("music_events", skip_boundary_check: true)

    assert {:ok, %{id: _music_id}} = Bonfire.Classify.Categories.get_archived("music_events")
    assert {:ok, %{id: _parent_id}} = Bonfire.Classify.Categories.get_archived("events")

    # under the parent, as the tree survives archiving
    # (it does not: the tree's `parent_id` is a strong pointer to the parent's `category` row, which archiving deletes, so the children's tree rows go with it; they are reserved without a parent, and put under it when an event brings one back)
    # assert %{tree: %{parent_id: ^parent_id}} =
    #          Repo.preload(%Bonfire.Classify.Category{id: music_id}, :tree)

    # nobody else can take the name
    group = Bonfire.Classify.Simulate.fake_group!(fake_user!(), %{username: "music_events"})
    refute Repo.preload(group, :character).character.username == "music_events"
  end

  test "the Events feed and the Events filter (\"Event\") list native events, and not posts" do
    user = fake_user!()
    event = create!(user)

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: user,
        post_attrs: %{post_content: %{html_body: "<p>Not an event</p>"}},
        boundary: "public"
      )

    # the `events` preset, as `/feed/events` loads it
    assert Bonfire.Social.FeedLoader.feed_contains?(:events, event, current_user: user)
    refute Bonfire.Social.FeedLoader.feed_contains?(:events, post, current_user: user)

    # the "Events" tab of the feed filters
    filtered =
      Bonfire.Social.FeedLoader.feed(:custom, %{object_types: ["Event"]}, current_user: user)

    assert Bonfire.Social.FeedLoader.feed_contains?(filtered, event, current_user: user)
    refute Bonfire.Social.FeedLoader.feed_contains?(filtered, post, current_user: user)
  end
end
