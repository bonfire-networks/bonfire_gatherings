defmodule Bonfire.Gatherings.FeedTimeSpanFilterTest do
  @moduledoc "Feeds filtered and sorted by when things happen (the `time_span` mixin), here with events, the type that has one."
  # `@moduletag :backend` comes with this case
  use Bonfire.Gatherings.DataCase, async: true

  import Bonfire.Me.Fake
  import Bonfire.Common.E
  import Bonfire.Common.Enums, only: [id: 1]
  alias Bonfire.Gatherings.Events
  alias Bonfire.Social.FeedLoader

  defp at(hours), do: DateTime.add(DateTime.utc_now(), hours * 3600, :second)

  defp event!(user, name, starts, ends) do
    {:ok, event} =
      Events.create(
        current_user: user,
        boundary: "public",
        event_attrs: %{
          post_content: %{name: name},
          time_span: %{has_beginning: starts, has_end: ends}
        }
      )

    event
  end

  # a page big enough for every fixture (pages hold 2 in tests, and `feed_contains?` checks the page it's given)
  defp feed(user, filters) do
    FeedLoader.feed(:custom, Map.merge(%{time_limit: 0}, filters), current_user: user, limit: 50)
  end

  defp has?(feed, object, user), do: FeedLoader.feed_contains?(feed, object, current_user: user)

  setup do
    user = fake_user!()

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: user,
        post_attrs: %{post_content: %{html_body: "<p>Not an event</p>"}},
        boundary: "public"
      )

    {:ok,
     user: user,
     post: post,
     last_week: event!(user, "last week", at(-170), at(-168)),
     now: event!(user, "happening now", at(-1), at(1)),
     next_week: event!(user, "next week", at(168), at(170))}
  end

  test "which side of now: upcoming, past, current, and current with upcoming", ctx do
    %{user: user} = ctx

    upcoming = feed(user, %{time_span: :upcoming})
    assert has?(upcoming, ctx.next_week, user)
    refute has?(upcoming, ctx.last_week, user)
    refute has?(upcoming, ctx.now, user)
    # things with no time span are not in a time-span feed
    refute has?(upcoming, ctx.post, user)

    past = feed(user, %{time_span: :past})
    assert has?(past, ctx.last_week, user)
    refute has?(past, ctx.next_week, user)
    refute has?(past, ctx.now, user)

    current = feed(user, %{time_span: :current})
    assert has?(current, ctx.now, user)
    refute has?(current, ctx.next_week, user)

    current_and_upcoming = feed(user, %{time_span: :current_and_upcoming})
    assert has?(current_and_upcoming, ctx.now, user)
    assert has?(current_and_upcoming, ctx.next_week, user)
    refute has?(current_and_upcoming, ctx.last_week, user)
  end

  test "happening during a period (eg. this weekend, worked out by the UI in the viewer's time zone), including what started before it",
       ctx do
    %{user: user} = ctx
    # a festival from before the period into it
    festival = event!(user, "festival", at(140), at(160))
    # no end: it lasts the day it starts
    one_off = event!(user, "one-off", at(155), nil)
    later = event!(user, "later", at(300), at(302))

    during = feed(user, %{happening_from: at(150), happening_until: at(190)})
    assert has?(during, festival, user)
    assert has?(during, ctx.next_week, user)
    assert has?(during, one_off, user)
    refute has?(during, later, user)
    refute has?(during, ctx.now, user)
    refute has?(during, ctx.last_week, user)
  end

  test "either end of a period alone: from a time on, or until a time", ctx do
    %{user: user} = ctx

    from = feed(user, %{happening_from: at(150)})
    assert has?(from, ctx.next_week, user)
    refute has?(from, ctx.now, user)
    refute has?(from, ctx.last_week, user)

    until = feed(user, %{happening_until: at(0)})
    assert has?(until, ctx.now, user)
    assert has?(until, ctx.last_week, user)
    refute has?(until, ctx.next_week, user)
  end

  test "something with no end lasts until the end of the day it starts", %{user: user} do
    # started a second ago: still its day (unless the test runs in the second after midnight)
    just_started =
      event!(user, "just started", DateTime.add(DateTime.utc_now(), -1, :second), nil)

    # started yesterday: its day is over
    yesterday = event!(user, "yesterday", at(-25), nil)

    current = feed(user, %{time_span: :current})
    assert has?(current, just_started, user)
    refute has?(current, yesterday, user)

    past = feed(user, %{time_span: :past})
    assert has?(past, yesterday, user)
    refute has?(past, just_started, user)
  end

  test "the Events feed has an event published long ago that's still to come", %{user: user} do
    published_40_days_ago =
      Bonfire.Common.DatesTimes.past(40, :day) |> Bonfire.Common.DatesTimes.generate_ulid()

    {:ok, event} =
      Events.create(
        current_user: user,
        boundary: "public",
        event_attrs: %{
          id: published_40_days_ago,
          post_content: %{name: "announced early"},
          time_span: %{has_beginning: at(168), has_end: at(170)}
        }
      )

    # the activity is really dated 40 days ago (its id is the time it was published), else this proves nothing
    assert %{id: activity_id} =
             Bonfire.Common.Repo.one(
               from(a in Bonfire.Data.Social.Activity, where: a.object_id == ^event.id)
             )

    assert activity_id == published_40_days_ago

    # published before the feeds' default window (`time_limit`, 30 days), which is about when things were published, not when they happen
    assert FeedLoader.feed_contains?(:events, event, current_user: user)
  end

  describe "the feeds' default window of 30 days (`time_limit`), which is about when things were published" do
    setup %{user: user} do
      published_40_days_ago =
        Bonfire.Common.DatesTimes.past(40, :day) |> Bonfire.Common.DatesTimes.generate_ulid()

      {:ok, event} =
        Events.create(
          current_user: user,
          boundary: "public",
          event_attrs: %{
            id: published_40_days_ago,
            post_content: %{name: "announced early"},
            time_span: %{has_beginning: at(168), has_end: at(170)}
          }
        )

      # the activity is really dated 40 days ago (its id is the time it was published), else this proves nothing
      assert %{id: activity_id} =
               Bonfire.Common.Repo.one(
                 from(a in Bonfire.Data.Social.Activity, where: a.object_id == ^event.id)
               )

      assert activity_id == published_40_days_ago

      {:ok, early: event}
    end

    # the feed as the loader runs it (not `feed_contains?`, which turns the window off), and a page big enough for every fixture
    defp listed?(user, event, filters) do
      %{edges: edges} = FeedLoader.feed(:events, filters, current_user: user, limit: 50)
      Enum.any?(edges, &(ed(&1, :activity, :object_id, nil) == event.id))
    end

    test "an event published long ago that is still to come is in the Events feed when it has a Happening filter",
         %{user: user, early: early, next_week: next_week} do
      # control: a recent one is listed, so the feed and the filter work
      assert listed?(user, next_week, %{time_span: :current_and_upcoming})

      assert listed?(user, early, %{time_span: :current_and_upcoming})
      assert listed?(user, early, %{happening_from: at(100)})
      assert listed?(user, early, %{happening_until: at(200)})
    end

    test "without a Happening filter the window still applies, and a window the viewer picks applies with one",
         %{user: user, early: early, next_week: next_week} do
      assert listed?(user, next_week, %{})
      refute listed?(user, early, %{})

      assert listed?(user, next_week, %{time_span: :current_and_upcoming, time_limit: 7})
      refute listed?(user, early, %{time_span: :current_and_upcoming, time_limit: 7})
    end
  end

  test "sorted by when things start, a page at a time", ctx do
    %{user: user} = ctx

    # published a day ago (so its id is smaller than the others'), but starting last; `sooner` is made after it, starting before it: the second page is in the order of the start dates, not of the ids
    {:ok, later} =
      Events.create(
        current_user: user,
        boundary: "public",
        event_attrs: %{
          id:
            Bonfire.Common.DatesTimes.past(1, :day) |> Bonfire.Common.DatesTimes.generate_ulid(),
          post_content: %{name: "in two weeks"},
          time_span: %{has_beginning: at(336), has_end: nil}
        }
      )

    sooner = event!(user, "in ten days", at(240), nil)

    ids = fn %{edges: edges} ->
      Enum.map(edges, fn edge -> ed(edge, :activity, :object_id, nil) || id(edge) end)
    end

    # pages hold 2 in tests, so the second page follows the cursor on the start time
    assert %{page_info: %{end_cursor: cursor}} =
             page_1 =
             FeedLoader.feed(
               :custom,
               %{
                 time_limit: 0,
                 time_span: :current_and_upcoming,
                 sort_by: :starts_at,
                 sort_order: :asc
               },
               current_user: user
             )

    assert ids.(page_1) == [ctx.now.id, ctx.next_week.id]

    page_2 =
      FeedLoader.feed(
        :custom,
        %{time_limit: 0, time_span: :current_and_upcoming, sort_by: :starts_at, sort_order: :asc},
        current_user: user,
        after: cursor
      )

    assert ids.(page_2) == [sooner.id, later.id]
  end
end
