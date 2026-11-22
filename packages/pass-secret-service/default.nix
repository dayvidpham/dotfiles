{ pass-secret-service }:

# Upstream pass_secret_service loads collections and items into memory once at
# startup. Because remote-session-compositor runs a private D-Bus session bus
# alongside the physical niri bus, each bus activates its own daemon against
# the same ~/.password-store. Syncing from disk on SearchItems / CreateItem
# keeps both instances seeing newly created, updated, or deleted secrets.
pass-secret-service.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./sync-disk.patch ];
})
