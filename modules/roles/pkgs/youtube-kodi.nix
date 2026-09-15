# plugin.video.youtube, with the ANDROID_VR player client removed.
#
# WHY THIS FILE EXISTS. Since roughly August 2026 YouTube requires a GVS
# (googlevideo) proof-of-origin token for the ANDROID_VR client, and the
# add-on cannot produce one. The stream URLs it hands to
# inputstream.adaptive are still valid — the video starts, plays, and then
# every byte-range request past the first ~60-70 s comes back 403:
#
#   [plugin.video.youtube] http_server:537(do_GET)
#     Stream proxy response not OK
#     Stream: ('q4jdWe5YJEg', '140') - ('audio', 'mp4')
#     Status: 403 Forbidden
#     Client: 28 (ANDROID_VR)
#     Range:  'bytes=1134583-1296405' (~70.10s)
#   AddOnLog: inputstream.adaptive: [AS-7] Segment download failed, attempt 6...
#
# after which ISA gives up and playback stops. Measured on ernst 2026-09-15.
#
# THE SHAPE OF THE FAILURE IS THE MISLEADING PART: playback *starts*, so it
# reads as a network or buffering problem, and the first thing anyone
# reaches for — a different quality, a different video, restarting Kodi —
# changes nothing, because the cutoff is a fixed position in the stream
# rather than a rate.
#
# Upstream: anxdpanic/plugin.video.youtube#1481 and #1483. NO RELEASE FIXES
# THIS. 7.4.4 (2026-06-24, the newest release) is the version most reports
# are filed against, so bumping the nixpkgs pin is not the answer and should
# not be tried as one. Both known workarounds are source edits; this is the
# better-attested of the two.
#
# WHAT IT COSTS. With `android_vr` gone the add-on falls through to the
# `*_testsuite_params` client groups, which are `auth_disabled` — the
# playback request carries no account. Two upstream reporters say YouTube
# watch history then stops updating. If that turns out to matter more than
# the add-on working, the alternative is upstream PR #1482, which refreshes
# the VR device fingerprint (Oculus Quest 3 -> Pico A8110) in
# `request_client.py` instead; one reporter says history survives that.
#
# REVISIT WHEN the add-on is bumped: if upstream has taken a real fix, this
# override should go rather than be carried forward. It will announce itself
# either way — `--replace-fail` fails the build if the line it expects is
# gone, which is the point. A patch that silently stopped applying would
# hand back the exact failure it was written for, and that failure looks
# like a broken living room rather than a broken build.
{ youtube }:

youtube.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    substituteInPlace resources/lib/youtube_plugin/youtube/client/player_client.py \
      --replace-fail "                'android_vr'," \
                     "                # 'android_vr',  # patched out: GVS 403, see modules/roles/pkgs/youtube-kodi.nix"
  '';
})
