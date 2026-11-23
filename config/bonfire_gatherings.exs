import Config

# The FEP-8a8e values split as Lauti splits its lists (and FEP-2fa1 its schemes): what kind of event it is (a `#Form`, Lauti's "categories") is a topic, in the chip bar; what it is about (a `#Topic`, Lauti's "topics") is a label, beside it. Flavours can move values between the two.
config :bonfire_gatherings, Bonfire.Gatherings.Events,
  # the most hits a search of the events page takes from each search index
  search_limit: 100,
  # how long after an event ends it leaves the search index (`Bonfire.Gatherings.Workers.UnindexEnded`, daily)
  unindex_ended_after: to_timeout(day: 30),
  # how far from the viewer's saved location the events page starts, in the viewer's units (km, or miles when their measurement units are imperial); "anywhere" for no default filter. Each user can choose their own (`Bonfire.Gatherings.Settings.NearbyDefaultSettingLive`)
  default_nearby_radius: 50,
  # the most events the events map takes (the soonest in the area in view)
  map_limit: 200,
  # how wide the map's view can be, in degrees of longitude, before it takes the soonest events that have a place instead of those in the box
  map_wide_longitude: 180
