# Controlled IPTV acceptance fixtures

These local fixtures exercise the integrated IPTV transport and native decoder
paths without depending on a public channel:

- `h264-1080p60-aac.ts`: H.264 High, level 4.2, 1920x1088 coded / 1920x1080
  visible, 60 fps, AAC-LC 48 kHz stereo;
- `hevc-main8-1080p60-aac.ts`: HEVC Main, level 4.1, 1920x1088 coded /
  1920x1080 visible, 60 fps, AAC-LC 48 kHz stereo;
- `h264-hls` and `hevc-hls`: generated MPEG-TS HLS variants of the same
  30-second fixtures;
- `controlled-index.m3u`: a host-specific copy of
  `controlled-index.m3u.example`; and
- `iptv-autotest.txt`: a host-specific copy of
  `iptv-autotest.txt.example` that acts as an optional `/app0` trigger and runs the
  controlled H.264 HLS fixture followed by HEVC without controller input.

Generated transport streams, HLS playlists, and host-specific manifests are
ignored by Git. Copy both `.example` files to names without `.example`, replace
`HOST_IP` with the development PC address visible to the console, and generate
or supply the matching media locally.

From the repository root, serve this directory on the development PC:

```bash
python3 -m http.server 8088 --bind 0.0.0.0 \
  --directory examples/iptv/fixtures
```

Do not start, upload, mount, launch, or inspect the PS5 outside the shared
PS5 homebrew development protocol lock. Hold the same lock from preflight
through evidence capture and cleanup.

For an automated codec cycle, copy `iptv-autotest.txt` only into a disposable
copy of the built app folder before invoking the locked cycle. The production
folder must not contain that file. Stdout emits `IPTV_AUTOTEST_BEGIN`,
`IPTV_RECEIPT`, and `IPTV_AUTOTEST_END` markers for each codec.
