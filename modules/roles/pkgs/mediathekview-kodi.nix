# plugin.video.mediathekview, with the "Results Limited" notification removed.
#
# WHY THIS FILE EXISTS. The add-on caps every listing at `maxresults` (an
# add-on setting, default 1000, slider max 3000) and then tells you so —
# strings #30980 / #30981, "Results Limited / Only the first {} results are
# shown." — from two call sites in `storeQuery.py`, one for a channel's
# recent films and one for its full list. The ARD/ZDF Mediatheken are far
# larger than any of those numbers, so the notification fires on ordinary
# browsing rather than on an unusual query, and there is no setting to turn
# it off: upstream offers the cap, not the message.
#
# The no-op is applied to the notifier rather than to the two `storeQuery.py`
# call sites, because the notifier is one place and the call sites are two
# and would grow. Nothing else calls `show_limit_results`.
#
# THE CAP ITSELF IS LEFT ALONE, deliberately. Raising it to 3000 was the
# other option and it is the worse one: the listing still gets capped on a
# big channel, so the message comes back, and every list in between is
# slower for it. Silence the message, keep the cheap query.
#
# WHAT THIS HIDES. Exactly one true statement: that you are looking at the
# first 1000 rows of something longer. Search rather than scroll when that
# matters — the add-on's own search applies the same cap and, since this
# patch, says nothing about it either.
{ mediathekview }:

mediathekview.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    substituteInPlace resources/lib/notifierKodi.py \
      --replace-fail "        self.kodiUi.show_notification(30980, self.language(30981).format(maxresults))" \
                     "        pass  # notification patched out: see modules/roles/pkgs/mediathekview-kodi.nix"
  '';
})
