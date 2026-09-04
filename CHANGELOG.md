# Changelog

All notable changes to the public `reolink-cli` distribution are documented here.
This is the customer-facing release history; it tracks the LAN-only (external)
builds published as GitHub Releases.

## [0.18.0] — 2026-09-04

### Added

- **A time-range download can now bring the audio with it: `--audio clip.aac`.**
  v0.17.0 dropped it, and dropped it silently. The camera had been sending it
  all along — measured on a 49-second window, **749 video packets and 779 AAC
  ones** — and the parser counted the audio packets' length and threw the bytes
  away.

  That was not a design choice, it was an incomplete feature: downloading a
  recording by name hands back an MP4 with its AAC track, and somebody asking
  for a *clip* usually wants what was said in it.

  ```sh
  reolink-cli vod download --from 2026-09-02T09:45:00 --to 2026-09-02T09:55:00 \
    --channel 5 --file clip.hevc --audio clip.aac
  ffmpeg -i clip.hevc -i clip.aac -c copy clip.mp4     # no re-encode
  ```

  The audio is **ADTS AAC** — each packet is exactly one whole ADTS frame — so
  the `.aac` is readable on its own and remuxes losslessly. Measured: the
  remuxed file is hevc + aac, 49.856 s, against 49.828 s for the same recording
  downloaded by name. A 28 ms difference, below one frame.

  **The default is deliberately unchanged.** Video-only stays byte-for-byte
  what it was, and `--audio` is a second request. Carrying both tracks in one
  response would have meant reworking the record framing that multi-file
  downloads use — a shipped mechanism serving a different feature. The price is
  that the camera cuts the window twice.

### Fixed

- The parser's AAC and ADPCM packets always carried an empty buffer: the type
  promised data it never delivered.

## [0.17.1] — 2026-09-04

### Fixed

- **A device refusing a download no longer reads as the stream simply ending.**
  The receive loop treated an empty frame as end-of-stream, and a refusal *is*
  an empty frame carrying a non-200 code — so the refusal was swallowed and the
  time-range download reported "no recording in that window" instead. On a model
  that does not implement the cut command at all, that diagnosis is wrong and
  sends you looking in the wrong place ("but I can see the recordings").

  Response codes are now read the way the reference implementation reads them:
  200 carries data, 300 ends a download by name, 331 ends a cut, and anything
  else is the device saying no — reported as the device error it is.

  This came out of a control experiment worth recording: an NVR answered 400 to
  the cut command, but so did a camera that demonstrably **does** support it,
  when asked for a window holding no recording. A 400 therefore cannot tell
  "unsupported" from "nothing there" — v0.17.0's release note implied it could.
  Since the CLI searches before it cuts, a 400 arriving *after* recordings were
  found is now reported for what it most likely is: this model has no cut
  download, and `vod download <name>` still works.

## [0.17.0] — 2026-09-04

`vod download` can now ask the camera for a time range and let it do the
cutting, instead of fetching whole recordings and trimming them yourself.

### Added

- **`vod download --from/--to` — a time range, cut by the device ([#105]).**

  ```sh
  reolink-cli vod download --from 2026-09-02T09:45:00 --to 2026-09-02T09:55:00 \
    --channel 5 --directory ./clips
  ```

  On an NVR a recording is typically a whole hour, so ten minutes of it used to
  mean downloading a gigabyte and throwing away nine tenths of it — and a window
  crossing the hour meant two files to join by hand.

  There is no protocol document for this device command, so every statement
  below is measured rather than quoted:

  - **One request returns one recording.** The device answers with the *first*
    recording the window touches, clipped to the window; a window starting in a
    gap skips forward to the next recording. Verified against frame counts on
    four windows of the same camera — 15s inside one recording gave 241 frames,
    the whole 49s recording gave 749, a window spanning three recordings still
    gave 749 (it stopped at the first one's end), and a window starting in a gap
    gave 781 from the second recording.

    So the CLI searches the window first and asks once per recording in it,
    joining the pieces. That is what makes a window crossing a recording
    boundary — on a continuously-recording NVR, any window crossing the hour —
    come back whole. The three-recording window above joins to 2165 frames,
    8.87 MB, in 3.4 s.

  - **The output is an elementary stream, not MP4.** A download by name hands
    back the MP4 the device stored; a cut is produced live and arrives as media
    packets, so it lands as `.hevc` or `.h264`. Wrap it with
    `ffmpeg -i clip.hevc -c copy clip.mp4` if you need a container.

  - **Not every model implements it.** Nothing in the capability list advertises
    it either; a model that lacks it answers 400, and downloading whole
    recordings by name is unaffected.

### Fixed

- **`--directory` no longer renames a download to a guess.** Only the response
  knows what the bytes turned out to be — the extension is read off the real
  container or codec — but the `--directory` path used a name built before the
  request went out. Downloading by name happened to be right (the device really
  does return MP4); a cut got a raw HEVC stream in a file called `.mp4`.
  `--file` still names an exact path; everything else now follows the response.

[#105]: https://github.com/reolink/reolink-cli/issues/105

## [0.16.1] — 2026-09-04

Three fixes, all of them cases where the CLI knew what had gone wrong and told
you something else — or nothing at all.

### Fixed

- **A failed single-file `vod download` now reports the device's actual error
  ([#105]).** Internally a download emits `file started` → `file skipped:
  <reason>` → `error: <reason>`, and the reader stopped at the skip marker. So
  *every* single-file failure was replaced by the hint reserved for a download
  that streams nothing and gives no reason — advice about waking battery
  cameras behind a hub, which reached someone whose recordings were on an NVR.
  Reproduced here on a Home Hub with a recording name that does not exist: one
  name produced the battery text, the same request with two names (the batch
  path, which was always correct) produced `device rejected command 14 (400)`.
  The hint stays, for the case it was written for.

- **"Recording not found" now says which channel it searched.** A download
  re-searches the recording to get its exact window, and a hub or NVR files
  recordings per channel — so a name copied out of `vod search --channel 7` and
  downloaded without `--channel` is genuinely absent, and the old message read
  like the recording was gone. It now names the channel, and reads the likely
  one back out of the recording name (the leading two digits are the 1-based
  channel):

  ```
  recording '0820260831070001' not found on channel 0 in the search of 2026-08-31 —
  the name starts with '08', which usually means channel 7. Pass the same `--channel`
  you searched with.
  ```

  It only says so; it will not silently download from a different channel.

- **Aliases carrying both a `host` and a `uid` can use the media endpoints
  again.** Login routed such a target by uid (it runs a connect race, with the
  IP as a LAN hint) while the media URL named the IP, so the gateway's binding
  check rejected the token it had just issued — `token does not match host`,
  which disabled `snapshot`, `preview` and `vod download` for those aliases
  entirely. Not a regression; it had been true for several releases. The media
  request now routes exactly like the login.

- **Preview no longer dies about 11 seconds in on battery devices.** A battery
  camera sends a heartbeat during a session and closes the session when the
  client never answers. That answer existed only inside the recording-download
  loop; every other long-running command reads through a shared loop that
  dropped the frame. Measured on a battery doorbell: preview ran 11.0s, 10.9s
  and 11.0s before, and 30s+ after, with every packet accounted for.

[#105]: https://github.com/reolink/reolink-cli/issues/105

## [0.16.0] — 2026-09-02

Snapshots got faster, and one class of snapshot stopped failing outright. Both
turned out to be our bugs, not the camera's — found by timing each phase of a
capture instead of assuming the wait was physics.

### Fixed

- **`--stream sub` was silently returning a full-resolution frame on some
  cameras.** `<fullFrame>` is a model-specific snapshot mode (the reference SDK
  documents it as "snap full frame pic, *for sd7*", to be used *together with*
  the sub stream). The CLI sent `fullFrame=1` unconditionally, to every device.
  On a camera that implements the flag, that overrides `<streamType>` — you ask
  for the small preview-sized JPEG and the device dutifully encodes and sends
  the full-resolution one.

  Measured on a dual-lens child behind a Home Hub 2, same camera and otherwise
  identical request:

  ```
                    resolution     size     awake     asleep (first capture)
  --stream sub
    fullFrame=1     3840x2160     875 KB     9.34 s     23 s
    fullFrame=0      896x512       58 KB     1.92 s     6.46 s

  --stream main
    fullFrame=1     3840x2160     861 KB     17.1 s
    fullFrame=0     3840x2160     860 KB      5.2 s
  ```

  So the default stream is **~5x faster and ~15x smaller**, and its cold-start
  case drops from 23 s to 6.5 s.

  `--stream main` is worth reading twice: it returns the same resolution and
  very nearly the same bytes either way, so nothing about the image changed —
  but the flag was routing the capture down a much slower and far less stable
  path. Three runs took 11.8 / 17.1 / 28.8 s with it, against 4.7 / 5.2 / 7.4 s
  without. Full-resolution captures on these cameras are roughly **3x faster**
  as a result.

  Cameras that never implemented the flag measured the same either way, which is
  exactly why this hid for so long: only the models that *support* the mode
  looked broken, and they looked like they were ignoring `--stream` rather than
  following an instruction we should not have been sending.

- **Snapshots from a sleeping or high-resolution camera could fail instead of
  just being slow.** The transport's read budget was a flat 10 s, and it bounds
  a *single* read — while a snapshot's `cmd 109` is one long silence: a battery
  camera behind a hub has to bring its whole video pipeline (sensor, ISP,
  encoder) up before it sends the first byte.

  Measured on a Home Hub 2: a sub-stream capture from a sleeping child spent
  **5.1 s** in that silence, and the 4K dual-lens child needed **23 s** when
  three channels were woken concurrently. Anything past 10 s came back as
  `tcp read timeout after 10s` — a failed capture, not a slow one.

  The budget is now 30 s, which covers the wake. It stays a single global value
  rather than a per-command one: VOD download and preview first-frame have the
  same "one long wait" shape, and a per-call timeout is something every future
  media path would have to remember to pass. The trade is that a device which
  accepts the connection and then goes mute takes 30 s to report — rare, and
  well inside the CLI's own 60 s response budget. Timeout messages now quote the
  real value instead of a hard-coded "10s".

### Added

- **`events history` — search the event log the device itself recorded**
  (hub / NVR; v2.0 cmds 516/517/518). This is a different store from
  `events query`: `query` and `stream` read the gateway's in-memory ring of live
  pushes (the most recent few hundred, lost when the gateway restarts), while
  `history` asks the device for the events it wrote down, so it reaches back as
  far as the device keeps them.

  ```
  reolink-cli --channel 1 events history --since 7d --types people,motion
  ```

  Takes `--from`/`--to` or a relative `--since`, an optional `--types` filter,
  and `--limit`. A hub files events per paired camera, and the CLI resolves that
  sub-device automatically from `--channel`. Standalone cameras have no event
  log and answer `400`; an empty list from a hub means the window genuinely held
  no matching events.

## [0.15.0] — 2026-09-01

Four community issues, and along the way the answer to a question 0.14.2 left
open: the siren was never actually making a sound.

### Fixed

- **The siren was accepted and silent — on every camera, in every release
  before this one** (#95, reported by **@ridome**). 0.14.2 stopped the CLI
  claiming the siren had sounded, which was right but incomplete: it had not
  established whether it sounded at all. It did not.

  Cmd 263 carries a `playMode`, and the CLI sent mode 1 ("sound for
  `playDuration` seconds"). This firmware accepts that with a `200` and ignores
  it. Mode 0 ("sound `playTimes` times") is the one that works. Measured by
  capturing the camera's own microphone through the preview stream and firing
  both modes into a single recording — the audio is flat at ambient through
  mode 1 and peaks roughly forty times higher on mode 0:

  ```
  [167,186,171,173,178,201,157,167,203,186,197,210,213,190,182,176,811,7295,7434,7508]
               ^ mode 1 fired here                       ^ mode 0 fired here
  ```

  One repetition runs about 3.2 s, so `--duration` now rounds up to whole
  repetitions and the answer reports `playTimes` and `approxDurationSeconds` —
  the conversion is visible rather than hidden. `--times N` is there when you
  want exact control. `verified: false` still stands, because v2.0 has no way
  to *ask* a device whether its siren is sounding; what changed is that it now
  does.

- **A `400` from a sleeping camera read as "your model does not support this"**
  (#95 and #97, reported by **@ridome**). A battery camera behind a hub falls
  asleep after roughly two minutes of quiet, and a sleeping child rejects
  commands with a bare `400` — the same code the device uses for a command it
  does not implement. That is how an agent came to tell a user their Argus PT
  Ultra had no built-in siren. It has one.

  Varying only the gap since the previous command, on one hub:

  ```
  gap                                     attempts to succeed
  back-to-back (seconds)                  1
  none, but a brand-new gateway session   1
  ~2 min / 120 s / 300 s / overnight      3
  ```

  A flat three attempts, about 1.6 s, and the refused request is itself what
  wakes the camera — so retrying is the mechanism, not a workaround. `audio
  siren play` and `light spotlight set` now retry on a bounded backoff and
  report `attempts`; when the backoff is exhausted the error explains standby
  instead of passing the device's "unsupported" wording through. The hub
  publishes the state as `loginState: standby`, which `info` now surfaces
  alongside the child's identity (it lags, so it explains a failure rather than
  predicting one).

- **A siren that sounds but cannot be heard** (#95). One child on a test hub sat
  at speaker volume 7 of 100 and was inaudible on its own microphone; the same
  command at 100 peaked twenty-one times above ambient. The command succeeds
  either way, so the answer now carries `speakerVolume` — if nobody heard it,
  that is the first thing to read.

- **`vod search` failed for a day at the start of every month.** A window
  crossing a month end produced no query windows at all internally, so the
  search came back as "no recordings"; a guard upstream turned that into an
  outright rejection, which is why `--since 24h` did not work on the first of
  any month and `--since 7d` did not work for its first week. The window is now
  walked by calendar date — month ends, year ends and leap-year February
  included.

- **One unreadable recording no longer costs you the whole batch.** A
  multi-file `vod download` used to abort at the first file the device would
  not serve, discarding everything after it. Failures are now reported per file
  (`requested` / `downloaded` / `skipped`) and the rest of the batch continues;
  a batch where nothing arrived is still a hard error, and no zero-byte file is
  left behind for a skipped recording.

- **Recording timestamps parsed from decorated file names.** Every digit in the
  string counted, so `Mp4Record_0120260820100150.mp4` came out as the year 260.
  Parsing now anchors on one unbroken run of digits.

- **Two Wi-Fi and gateway timeouts that cost more than they saved.** Built
  internally as 0.14.3 and never released on its own, so it ships here.
  `wifi set`'s pre-switch address probe went from 900 ms to 5 s: in a 925-case
  compatibility run the one "switch: not measured" was a camera probed one
  second after re-associating, where the same broadcast found it 4.45 s later
  in the same command — the switch had worked, only the measurement was lost.
  And the gateway's LAN leg now gives a cached or hinted address 3 s instead of
  10 s to answer: a live address replies in milliseconds, while a stale one
  written back into the cache after a network switch made every following
  connection wait the full ten before a fallback probe found the new address in
  0.4 s.

### Added

- **`--view N` addresses the second lens of a dual-lens camera** (#100,
  reported by **@ridome**). It is a third axis, orthogonal to `--channel`
  (which camera) and `--stream` (which encoding profile of that view), and
  defaults to the only view an ordinary camera has, so nothing existing
  changes. `info` lists what a channel has:

  ```
  hub-ch2  OMVI 2i Ultra  dualLens=true  views=[(0, "wide"), (1, "telephoto")]
  ```

  Measured per view on real hardware: `encode` (3840x2160 vs 2880x1616),
  privacy mask, motion detection and PTZ all differ. Media does not —
  `snapshot` is answered `400` for any view above 0, and preview and
  `stream url` have no selector in the protocol at all. Those two now **refuse**
  a non-zero `--view` rather than quietly handing back the first view, and the
  snapshot error says which half of the axis works.

- **Bounded monitoring tasks** (#96, reported by **@ridome**). An
  `events monitor` rule takes `expires_at` — an RFC 3339 timestamp or a Unix
  second — after which it stops firing. Absolute rather than relative on
  purpose: a `"30m"` would restart its countdown on every reload, so a bounded
  task would quietly become an unbounded one. Expiry deactivates the rule
  without rewriting your rules file, `status` reports `expired` and
  `secondsRemaining` per rule, and `history` takes `--rule` and `--since` with
  the filters applied *before* `--last`, so a busy neighbour can no longer
  crowd a bounded task's captures out of the tail.

- **`audio siren enable set --channel-on` / `--channel-off`.** The buzzer
  linkage has two switches — a device-wide master and a per-channel bitmap —
  and the CLI could only write the master. One hub reported the master on with
  every channel bit clear, a state the command line had no way to correct.

- **`audio siren play --times N`** for an exact number of repetitions, with
  `--duration` kept as the convenience that rounds up to it.

## [0.14.2] — 2026-08-28

Three Home Hub defects, all verified on a Home Hub 2 with three child cameras.

### Fixed

- **A hub channel reported the hub's own model, not the child camera's**
  (#99, reported by **@ridome**). `info` sends a device-level command, so every
  channel of a hub answered `Reolink Home Hub 2` and the child cameras were
  invisible — leaving an agent unable to tell what any given channel could
  actually do. There is a per-channel equivalent in the protocol that was
  simply not implemented. `info` now reports the child under its own `channel`
  object:

  ```
  hub-ch0  hub=Reolink Home Hub 2 | child: Argus PT Ultra   / v3.0.0.4739 / Front Door
  hub-ch1  hub=Reolink Home Hub 2 | child: Reolink Argus PT / v3.0.0.5585 / Back Door
  hub-ch2  hub=Reolink Home Hub 2 | child: OMVI 2i Ultra    / v3.0.0.6976 / Back Yard
  ```

  Deliberately a separate object rather than merged into the top level: a
  caller deciding what a camera supports must not mistake hub metadata for the
  child's. Serial number, hardware version and build day come through too.

- **`audio siren play` reported the siren was sounding when the device had only
  acknowledged the command** (#95, reported by **@ridome**). `state: "on"` was
  a hard-coded string — it was never evidence. Measured on a Home Hub 2: the
  command returned 200 on two channels while no `siren.on` report arrived on
  any of them, so an agent faithfully relayed a success the CLI had invented.

  There is no way to ask a v2.0 device whether its siren is sounding, so rather
  than fake verification the response now states only what is known:
  `accepted`, the requested duration, send and expected-stop timestamps, and
  `verified: false`, with a pointer to `events stream` where a device that does
  sound emits `siren.on` / `siren.off`.

- **The first spotlight command to a hub child camera could fail with `400`**
  (#97, reported by **@ridome**). The pattern was `400, ok, ok` — try it once
  and you conclude the feature is unsupported, though all three child cameras
  turn their light on and off normally.

  The trigger could not be pinned: it did not correlate with how long the
  camera had been idle (after 120s the first call succeeded), nor with a
  freshly started gateway. So this does not pretend to know why — it retries on
  a device-side `400` with a bounded backoff and reports `retried` so the
  caller can see it happened. A `405`, meaning the model has no spotlight, is
  not retried.

## [0.14.1] — 2026-08-28

Three defects reported by users of 0.14.0, plus a documentation gap that took
someone hitting an error to find.

### Fixed

- **Downloaded recordings were always named `.h264`, whatever the codec**
  (#94, reported by **@djancak**). The extension was wrong twice over: those
  files are not an elementary stream at all, they are an **MP4 container**.
  Every one begins `…ftyp iso4`, which is why `ffprobe` reads them happily and
  reports `hevc`.

  The old code assumed the bytes after the header frame were raw H.264/H.265
  and sniffed for Annex-B start codes. An MP4 header happens to contain a
  `00 00 00 01`, so the sniffer read a meaningless NAL type and fell back to
  its `h264` default — which is why *every* download got that name regardless
  of what was inside. It now identifies the container first and names the file
  `<recording>.mp4`; the Annex-B sniffing stays as a fallback for firmware that
  really does send an elementary stream.

- **`--password-stdin` hung on a terminal, and did not exist where it was
  advised** (#92, reported by **@djancak**). It went straight to a blocking
  read with nothing on screen, which is indistinguishable from a hang. It now
  says what it is waiting for first:

  ```
  reading the password from stdin — type it, press Enter, then Ctrl-D
  ```

  That wording is measured, not assumed: on a line-buffered terminal a single
  Ctrl-D after the password does **not** end the read, because Ctrl-D only
  signals EOF when the line buffer is already empty.

  The flag is also global now, like `--password` has always been. Previously it
  existed only on `device add` / `device update`, while every other command's
  error message advised "use `--password-stdin`" — advice that could not be
  followed.

### Added

- **`vod download --directory <DIR>`** (#93, requested by **@djancak**).
  Chooses where recordings land, creating the directory if it does not exist,
  for a single recording or a list. Previously the only way was to `cd` first,
  which a caller that does not control its working directory — an MCP client,
  an agent — cannot do. `--file` remains single-recording-only and the two are
  mutually exclusive.

### Documentation

- **Camera names with spaces** (#91, reported by **@ian1182**). There are no
  name rules — spaces, mixed case and non-ASCII all work — but a name with a
  space needs shell quotes like any other argument, and every example showed
  the hyphenated form. `device add --help`, the command reference and the
  bundled skill now show a quoted example and note that names match exactly, so
  `Front Door` and `front door` are different cameras.

Verified against a real Reolink Home Hub 2 (v3.3.0.579), including the terminal
behaviour of `--password-stdin` under a pty.

## [0.14.0] — 2026-08-26

Scene mode: the Home / Away / Disarm control your hub shows in the app, now on
the command line.

### Added

- **`scene` — arming profiles on a hub or NVR.** A scene is a named set of
  per-channel tasks (`record`, `ftp`, `email`, `push`, `audio` — the siren —,
  `linkage`, `speaker`, `track`), so switching scenes re-arms every paired
  camera at once. It does not change what each camera *detects*; it changes what
  the hub *does* about it.

  ```
  reolink-cli --camera hub scene show          # which scene is active
  reolink-cli --camera hub scene list          # every scene and its tasks
  reolink-cli --camera hub scene set 3         # arm for leaving
  reolink-cli --camera hub scene set --schedule # hand back to the timetable
  ```

  `scene edit` changes a scene's tasks, name, icon and activation delay —
  `--channel N` confines the change to one camera, and without it every channel
  in the scene is rewritten. `scene schedule get/set` reads and writes the
  weekly timetable (7 days × 2 half-hour slots × 24 hours) that drives scene
  switching whenever no scene is pinned. `scene alarm get/set` maps alarm types
  (person, vehicle, pet, other) onto individual tasks. `scene options` covers
  the master switch, the hub's Home button, and privacy mode while disarmed.

  Scene id `0` is not a scene — it hands control to the timetable, and
  `scene show` reports that plainly as `followSchedule: true`.

  Commands refuse rather than guess: a scene id the hub does not have is
  rejected with the ids it does have, a mistyped task name is rejected with the
  names this device honours, and an option the device reports as unsupported is
  refused instead of written and ignored.

- **MCP tools** `camera_scene_show`, `camera_scene_list`,
  `camera_scene_schedule_get` and `camera_scene_set`, so an agent can read and
  switch arming state in plain language.

### Notes

- Scene mode exists on hubs and NVRs. A standalone camera answers `405` to
  every `scene` command.
- `scene edit --tasks` **replaces** a scene's task set rather than adding to it.
  A scene edited down to no tasks records nothing and notifies nobody, and the
  device gives no warning — `references/scene-mode.md` in the bundled skill
  spells this out.
- Every write is read-modify-write, because the device replaces the whole object
  on each of these commands. Fields you do not name keep the value the device
  reported.

Verified against a real Reolink Home Hub 2 (v3.3.0.579): every command and flag
was exercised on the device and the original configuration restored afterwards.

## [0.13.1] — 2026-08-24

Three bugs reported against 0.13.0, plus two more `vod download` defects found
while verifying the fixes against a real Home Hub 2, and a large speed-up for
batch downloads.

### Fixed

- **`vod download` silently dropped everything past about the 210th recording**
  (#87, reported by **@djancak**). The recording names travel in the request
  URL, and the gateway cut that URL off at 4096 bytes without saying so — then
  served the shortened request as if nothing had happened, reporting `ok: true`
  for a download that fetched 210 of 394 files.

  The gateway now answers `414 URI Too Long` instead of truncating, and the CLI
  splits a long list into as many requests as it takes, each sized against the
  real encoded length. Recordings in one batch still share a single device
  connection, so the speed-up from 0.12.4 (#72) is intact. Verified on a Home
  Hub 2: 220 recordings requested, 220 written.

- **A camera registered with a `uid` could not be reached at all** (#85,
  reported by **@djancak**). Since these builds carry no P2P, a `uid` target
  went straight to a wake broadcast — ignoring the LAN address the same entry
  already gave — and a mains-powered camera that never answers a wake failed
  after about nine seconds with `wake timed out after 3 attempts`. A camera
  that did answer would then have been logged in with the wrong protocol.

  A `uid` target now tries the LAN first: an entry that also carries a `host`
  connects straight to it, and the wake path is left to the battery devices it
  was meant for. Verified against a real camera: 9.0s failure → 2.1s success.

- **`vod download` could not fetch any recording past the 500th of its day.**
  Locating a recording by name re-searched its day with a hard cap of 500, so
  on a busy day `vod search` would list a recording that `vod download` then
  reported as `not found`. Measured on a Home Hub 2 with 604 recordings in one
  day. The cap is gone — that search looks for one known name, so capping it
  protected nothing.

- **Long multi-recording downloads failed near the end with `invalid or expired
  token`.** A media token expires 300 seconds after its last use, and a batch of
  a few hundred recordings streams for far longer than that. Each batch now gets
  a fresh token.

### Changed

- **`vod search --limit` accepts up to 100000, and `--limit 0` means no limit**
  (#86, reported by **@djancak**). The old ceiling of 500 was never a camera
  limit — the request carries no count at all and the camera pages until it runs
  out — and a single busy day can exceed it, leaving no way to tell "this camera
  has 500 recordings" from "we stopped counting at 500". A day with 604 and a
  month with 965 both come back whole now.

### Performance

- **Batch `vod download` is several times faster.** Locating each recording
  searched its entire day and then filtered by name; a recording's name already
  ends in its own start time, so the search now asks for that one second and
  falls back to the day only if that finds nothing. On a Home Hub 2 a day
  holding 604 recordings took 4.97s to search and one second of it 0.31s, and
  this runs once per file. Same 220 recordings, same camera: 360s → 204s, and
  roughly six times faster on days with more recordings in them.

## [0.13.0] — 2026-08-21

Two new command groups — video encoder settings and the manual siren — plus a
recording fix for Home Hubs and NVRs. Both new groups were verified against real
cameras (E1 Outdoor, RLC-823S1).

### Added

- **`encode` — read and change the video encoder.** `encode get` shows every
  stream (main / sub / third): resolution, frame rate, bit rate, codec
  (H.264 / H.265), profile, GOP, and H.265+. `encode set --stream <s>` changes
  one stream — for example
  `encode set --stream main --fps 15 --bitrate 4096 --codec h265`. `encode
  capability` lists the exact resolution / frame-rate / bit-rate combinations
  the camera will accept.

  Run `encode capability` before `encode set`: a value the camera does not list
  is rejected, and nothing changes. The write replaces all three streams at
  once on the wire, so the CLI always re-reads the current settings and patches
  only the flags you pass — the streams you do not name are preserved. Changing
  a resolution restarts the encoder, so any live preview / RTSP / NVR consumer
  reconnects.

- **`audio siren` — sound the built-in siren.** `audio siren play --duration N`
  sounds it for N seconds (it stops itself); `audio siren stop` silences it now.
  This is the app's manual-siren button. `audio siren task` / `audio siren
  enable` expose the alarm-linkage schedule and master switch where the model
  implements them (many current models return "unsupported" for those two while
  manual play/stop works everywhere). A sounding camera also surfaces as a
  `siren.on` / `siren.off` event on the event stream.

- **MCP tools** for both: `camera_encode_get` / `camera_encode_set` /
  `camera_encode_capability` and `camera_siren_play` / `camera_siren_stop`.

- **Gateway observability.** The gateway now writes a log file and records
  timing on the paths that matter for diagnosing a slow or failing connection,
  and `benchmark` reports success rate and measured bit rate.

### Fixed

- **Recording search and download on Home Hubs and NVRs now target the right
  camera.** On a multi-camera hub, `vod search` / `vod download` resolve each
  channel to its paired sub-device before querying, instead of addressing the
  wrong channel.

- **`encode` never invents a setting the camera did not report.** A camera that
  omits a field (some send no rate-control mode or audio flag at all) no longer
  gets a default written back on the next unrelated edit — which, for the audio
  flag, would have silently muted the stream.

## [0.12.4] — 2026-08-14

Wi-Fi work, a protocol default that stops guessing, and a data-loss defect in
redirected setups reported by a user.

### Contract change (read this if you script the CLI)

- **The wire protocol now defaults to `v20` instead of probing.** With no
  `--protocol` and no `protocol` in the camera entry, the CLI connects as v20
  directly. Previously it opened an extra TCP round trip to detect v20 vs v30
  from the device's response magic — and on Wi-Fi that probe was the single
  most common cause of spurious failures (see below). Cameras that speak v30
  must now say so: `protocol = "v30"` in the entry, or `--protocol v30`. The
  probe is still available on demand as `--protocol auto`, which also overrides
  an entry's declaration — the way out when an entry names the wrong protocol.

- **`wifi set` prints two new lines and `data.new_host` changed meaning.**
  `phases:` gives per-phase timings and `switch:` states one of three verdicts
  about the transition. `data.new_host` is now strictly *the host written into
  the camera entry*, and is `null` whenever `registry_updated` is `false`; it
  used to carry "the address rediscovery happened to see", which was frequently
  the address the camera was about to leave. For where a camera ended up, read
  the `switch:` line or run `discover`.

### Fixed

- **`credentials.key` now lives beside the file whose passwords it protects**
  (#79, reported by **@ch-bas**). `--cameras-file` / `--config-file` (and their
  environment variables) were honoured by every data read and write, but the key
  file was always created in the platform default config directory. The
  documented backup procedure — copy the registry *and* the key next to it — was
  therefore impossible to follow in a redirected setup, and restoring on another
  machine lost every stored password. Each redirected profile is now
  self-contained, which also means separate `--cameras-file` profiles no longer
  share one key. Existing installations keep working: if no key sits beside the
  file, the old location is still read (read-only — the next write puts the key
  where it belongs).

- **`doctor` inspects the files the CLI is actually using** (#79). It accepted
  `--cameras-file` / `--config-file` but its `config.toml`, `cameras registry`
  and `registry perms` checks always looked at the default paths, so under
  redirection it reported a missing registry while `device list` was reading
  three cameras from the redirected one. The permissions check — which exists
  because the registry holds encrypted credentials — now examines the registry
  in use.

- **Intermittent `route not found: TCP connect timed out` on Wi-Fi.** The
  pre-login protocol probe gave itself 750 ms, which is shorter than the
  operating system's first TCP SYN retransmission (1 s on both Windows and
  Linux). A single lost SYN — routine on Wi-Fi — therefore became a hard
  failure for a camera that was up and 17 ms away, and it failed an operation
  whose real connect budget is 10 s. The login path now allows 3 s; `discover`
  keeps the short budget, because a subnet sweep probes mostly dead addresses.
  Error messages report the budget actually in force.

- **A camera that changed address no longer fails the first command after the
  move.** The remembered LAN address for a UID is now re-resolved with a fresh
  broadcast when it stops answering, instead of being abandoned outright — the
  camera is almost always still on the same LAN, just somewhere else on it.

- **`wifi set` no longer pins an address onto a camera registered by UID
  alone.** An entry created with `device add --uid` (no `--host`) states that
  the address is expected to move; writing the address found after a switch
  turned that into a fixed host, which the next switch invalidated. The address
  is reported, not stored.

- **`wifi set` measures the switch instead of inferring it.** The old timing
  came from reading the SSID back after reconnecting, but the v20 config command
  returns stored configuration, not association state — there is no
  "currently associated SSID" in the protocol, so that number was a round trip,
  not a transition. The CLI now samples reachability from the client side and
  reports when the camera left, when it answered again, and at which address.

- **`wifi set` no longer refuses on a wired camera.** The check for "is this
  camera on Wi-Fi right now" asked `GetLinkType`, whose values are `LAN`,
  `PPPOE` and `CDMA` — how the device obtains an IP, with no wireless value at
  all. The branch could only be reached when the read *failed*, so wired
  cameras were told to pass `--no-test`. It now uses the measured signal
  strength, the one live value in that structure.

### Added

- **`wifi get` reports `signal`** — the associated link's signal strength as the
  device measures it.

## [0.11.0] — 2026-08-06

Six reported issues, two new platforms, and one command that could delete your
installation without asking.

### Added

- **32-bit Raspberry Pi builds — `linux-armv7` and `linux-armv6`** (#73). armv7
  covers a Pi 2/3/4 on a 32-bit OS; armv6 covers the Pi 1 and Zero, whose CPUs
  cannot execute armv7 code at all. They are two separate archives for that
  reason, and `install.sh` and `self-update` each resolve the one matching the
  build they are replacing rather than guessing from the CPU.

  Built against glibc 2.28, so Raspberry Pi OS Buster and later work — the
  default toolchain target would have been 2.34 and excluded everything before
  Bookworm. Verified on Raspberry Pi OS armv6 (`uname -m` = `armv6l`), on Debian
  Buster and Bullseye armv7, and by confirming the armv7 binary does refuse to
  run on an ARMv6 CPU, which is why the two archives exist.

  `uname -m` is not the deciding answer on a Pi, and `install.sh` no longer
  treats it as one. 32-bit Raspberry Pi OS has booted a 64-bit kernel by default
  since Bullseye, so it reports `aarch64` while the userland is 32-bit and
  carries no arm64 loader — the arm64 archive cannot start there at all. The
  installer reads `getconf LONG_BIT` and the loader on disk, which answer for
  the userland that has to run the binary. A genuine 64-bit userland is
  unaffected and still gets the arm64 archive.

- **`vod download` takes several recordings at once** (#72), fetching them over
  one device connection instead of one per file:

  ```bash
  reolink-cli -c my-cam vod download 0120260803025316 0120260803025332 0120260803025401
  ```

  A download deliberately avoids the shared session — a transfer running for
  minutes would stall every other command against that camera — so each
  invocation otherwise pays its own connect and login, measured at about a
  quarter of a second per file. Naming them together pays it once. Each
  recording is written to `<name>.<codec>` in the current directory; `--file`
  names a single destination and is rejected with several names.

  A request for one recording is unchanged, byte for byte, including its
  `Content-Disposition`. Only a multi-file request switches to the framed
  `application/vnd.reolink.vod-batch` response, so nothing that already reads
  `/api/vod/download` is affected.

- **A UID target is resolved on the LAN before falling back to P2P.** A camera
  whose router has no internet access can never register with the relay, so
  connecting by UID failed outright (`p2p error: -7`, the relay answering "no
  such UID") even with the camera sitting on the same subnet. The gateway now
  broadcasts for the UID first, remembers the answer for 60 seconds, and
  connects over TCP when it finds one; P2P remains the path for a UID that
  nothing on the LAN claims. The discovery broadcast also binds its source
  address per interface, so a host with several networks asks on all of them
  rather than whichever the routing table happened to pick.

- **`vod search` reports `scanned`** — how many recordings the camera returned
  before `--type` filtering. `--limit` is applied by the camera on the
  *unfiltered* set, so a narrow filter can match 2 of 20 scanned while more
  exist further back. Without the number that reads as "there are only 2".

### Fixed

- **`vod search --type` did not filter** (#74). The request carried the type all
  along and the camera ignored it, so `--type people` returned every motion
  recording in the window. Filtering now happens on our side, which also fixes
  it for the MCP tools and the HTTP API. A recording carries a set of tags and
  so does the request: `--type people` keeps one tagged `md,people`, and asking
  for several types is a union.

- **`--output text` printed JSON for `device list`, `device show` and
  `cache status`** (#69) — the commands most likely to be wanted as a table. The
  text renderer only ever handled objects of plain values; it now renders a list
  of records as an aligned table and expands nested sections, so any future list
  command gets the same treatment. Columns that are empty in every row are
  dropped rather than padded.

- **`config init` pointed at a directory the tool does not read** (#68). The
  generated files told you to copy them to `reolink/`, while the config
  directory is `reolink-cli/` and `config init` had already written them to the
  right place. The same stale path appeared in `--help` for the event-monitor
  rules and in the instructions the MCP server hands every agent at startup,
  where it also still called `--camera` by its old name. The repo-side half of
  this was reported and fixed by **@ch-bas** in #71.

- **`disabled = true` was ignored by `--all-devices` and `--tag`** (#70). Only
  `device list` honoured it, so a camera you had deliberately taken out of
  service — or one of the examples `config init` seeds — was still contacted by
  every fan-out. A fresh install running `--all-devices ping` opened TCP
  connections to `192.168.1.41`, an address the user never chose and which on a
  real network belongs to somebody else. Fan-out selectors now skip disabled
  cameras; naming one with `--camera` still works, because asking for a camera
  by name is intent and `disabled` is not a lock. The seeded examples ship
  disabled as well.

- **`device resolve --camera <name>` reported a disabled camera as enabled**,
  and its description and tags as empty, while `--cameras <name>` reported all
  three correctly. Two paths, one question, different answers.

### Security

- **`setup --uninstall` had no confirmation of any kind.** Not a prompt, not a
  flag check — any process that reached the command ran it to completion, and
  with `--purge` that removes both binaries, your config, your camera registry,
  the agent skill directories and the Claude Code plugin registration. It needs
  no config, no credentials and no terminal, so nothing else stood in the way.
  This is not hypothetical: a documentation checker that executed the commands
  it found in fenced code blocks wiped a developer's whole installation.

  Uninstalling now refuses when stdin is not a terminal unless `--no-interactive`
  is present. That flag is the declaration that the deletion was meant, and it
  is the flag `AGENTS.md` has told agents to pass all along — until now nothing
  read it, so the documentation described a confirmation step that did not
  exist. The check reads stdin rather than stdout, so `setup --uninstall | tee
  log.txt` is still a person at a keyboard and still works in one shot.

  **If you script an uninstall, add `--no-interactive`.** Slash commands and the
  tarball's `uninstall.sh` / `uninstall.ps1` wrappers pass it through.

- **`scripts/check-doc-commands.py` executed every command it found in the
  docs.** It described itself as running them "through the argument parser" and
  leaned on redirected config paths to make them harmless, but an explicit flag
  beats an environment variable, and a command needing no config never went near
  the redirect. Anyone who cloned this repository and ran it got their own
  installation removed. It now passes `--parse-only`, which validates the
  argument vector and exits before dispatch, and refuses to start against a
  binary too old to support it.

### Notes

`--parse-only` is a hidden flag for that checker. It is an assertion about a
command line, not a mode of operation, and it is deliberately absent from
`--help`.

### Platforms

| | |
|---|---|
| macOS | arm64 (Apple Silicon) |
| Linux glibc | x86_64, arm64 |
| Linux musl | x86_64, arm64 — Alpine, Home Assistant OS, slim Docker images |
| Linux 32-bit ARM | armv7, armv6 — Raspberry Pi on a 32-bit OS |
| Windows | x86_64 |

Verify a download against `checksums/v0.11.0.sha256` on `main`, **not** the
`SHA256SUMS` attached to the release — see
[Verifying a download](https://github.com/reolink/reolink-cli#verifying-a-download).

## [0.10.8] — 2026-08-04

A security release. Three of these were found by auditing our own code rather
than by a report, and one of them was introduced by the previous release's
hardening.

### Security

- **`reolink-cli self-update` verified nothing at all.** It resolved the latest
  release, downloaded the archive, unpacked it and overwrote both binaries — no
  checksum, no signature — and carried its own `REOLINK_UPDATE_REPO` override
  with nothing anchoring it. 0.10.5 gave the installers a committed-checksum
  anchor and left this path untouched, and it is the one that runs on machines
  that already have the tool, repeatedly, often with `--yes`. It now verifies
  against the same committed checksum and fails closed.

- **The gateway's cross-origin guard was bypassable by DNS rebinding.** It
  compared `Origin` against `Host`, and rebinding makes those agree: an
  attacker's domain, re-resolved to 127.0.0.1, produces a request where both are
  `evil.example`. The guard allowed it and `Access-Control-Allow-Origin: *`
  handed the response back. Not merely a read —
  `POST /api/cameras/<name>/login` authenticates with the password stored in
  `aliases.toml`, so any page could mint a token and then read snapshots and the
  live event stream. The gateway now also requires `Host` to be an address it
  actually bound to.

  **Consequence, deliberate:** reaching the dashboard from a browser through a
  custom hostname is refused. Use `localhost`, `127.0.0.1`, or the bound
  address. Requests without an `Origin` — `curl`, go2rtc, Home Assistant
  server-side pulls, `<img src>` — are unaffected.

- **The event stream never re-checked its token.** `/api/events` validated once
  at connect and then streamed forever, so a stream opened with a valid token
  kept delivering camera events long after that token expired. It now re-checks
  every 30 s and closes when the token is gone — using a check that deliberately
  does *not* refresh the inactivity window, or a subscription would renew its
  own token indefinitely.

- **`self-update`'s scratch directory could be taken over.** It was
  `create_dir_all` on a predictable `<tmp>/reolink-update-<pid>`, and
  `create_dir_all` succeeds when the path already exists. Another local user
  could own that directory and swap the archive in the window between the
  checksum passing and the two later reads of the same file — installing
  binaries that were never verified and are then executed. Now created
  exclusively, mode 0700 at creation, with a random component.

- **A dead hook shipped in every release archive piped an environment-variable
  URL into a shell.** `plugins/reolink-cli/scripts/ensure-binaries.sh` carried
  three `curl "$REOLINK_REPO_URL/-/raw/master/scripts/install.sh" | sh` calls
  with no verification of any kind, against a GitLab-shaped path left over from
  when this project was private. No manifest registered it and nothing invoked
  it. Deleted rather than hardened.

- **The tarball's Windows installer could discard your Claude Code settings.**
  On any read or parse error it fell back to an empty object and wrote that over
  the file — for `~/.claude/settings.json` that is permissions, hooks, model
  settings and MCP servers. It now leaves an unreadable file untouched and says
  so.

- **`GITHUB_TOKEN` was on curl's command line** in `install.sh`, where `ps`
  makes it readable by every other user on the machine — while `self_update.rs`
  refused to do exactly that and explained why. The header now goes to curl on
  stdin.

### Fixed

- **Uninstalling killed every gateway on the machine, not just this install's.**
  The Windows branch called `taskkill /F /IM reolink-gateway.exe` directly below
  a comment explaining that it must not, because that is image-name-wide and
  hits other installations. Same defect as #29 on Unix, fixed there and left
  standing here. It now filters by executable path, and says which processes it
  skipped.

- **`setup --uninstall` exited 0 having left `reolink-cli` behind on Windows.**
  The OS locks a running image so the binary cannot delete itself; that printed
  a warning and reported success, which is what a script or package manager
  reads. It now exits non-zero and gives the one command that finishes the job.

- **`self-update` asked for confirmation before checking whether the platform is
  supported**, so a Windows user consented to an update that was never possible.

- **The cross-origin guard refused a gateway bound to port 80**, because a
  browser omits the default port and the new `Host` check required one.

- Two independent sources of test-suite flakiness, together failing about one
  run in four: temp directories named from a clock that is not
  nanosecond-granular, and an `lsof` latency being reported as a logic failure.

### Documentation

- `SECURITY.md` states what download verification proves and what it does not,
  and that **any local process able to reach the gateway port can control your
  cameras** — the boundary is the machine, not the process.
- The one-line install had no documented uninstall path; `setup --uninstall` is
  now the primary instruction.
- `scripts/check-past-findings.py` turns every previously reported defect into
  an assertion, so they cannot quietly regress.

## [0.10.7] — 2026-08-03

### Security

Reported privately as GHSA-65x2-w384-qp7j by Bassem Chagra, as a follow-up to
the report behind 0.10.5's committed-checksum change. Two of the three findings
were valid as filed; the third was half right, and investigating it turned up a
worse hole in a path the report did not cover.

- **`self-update` verified nothing at all.** It resolved the latest release,
  downloaded the archive, unpacked it, and overwrote both binaries — no
  checksum, no signature — and carried its own `REOLINK_UPDATE_REPO` override
  with nothing anchoring it. The installers had been given a committed-checksum
  anchor in 0.10.5; this path had not, and it is the one that runs on every
  machine that already has the tool, repeatedly, often with `--yes`. It now
  verifies against the same committed checksum and fails closed. Not in the
  report — found while checking it.

- **The checksum source followed `REOLINK_REPO`** (finding 2). Both the archive
  and the checksum were fetched from the overridden repository, so pointing it
  at another repository meant the archive was validated against *that*
  repository's own committed checksums: attacker supplies both halves, every
  check passes, and the installer prints "ok". The checksum source is now pinned
  to `reolink/reolink-cli` in `install.sh`, `install.ps1` and `self-update`.
  `REOLINK_REPO` still moves the download, so a mirror serving identical bytes
  works; a fork serving its own build no longer validates itself.

- **A crafted archive could choose which binary got installed** (finding 3).
  The binaries were located with `find "$tmp" -name reolink-cli | head -n1`,
  which searches the whole extraction tree and takes whatever the walk reaches
  first — so an archive carrying a second `reolink-cli` under a directory
  sorting earlier won, and that file was then made executable and run.
  Reproduced with such an archive before fixing. All three paths now derive the
  directory name from the asset name and read `bin/<name>` from it, and refuse
  a symlink or reparse point in that position.

  The other half of that finding — that `..` and absolute members could write
  outside the extraction directory — did **not** reproduce: BSD tar refuses `..`
  and exits non-zero, GNU/busybox tar strips the prefix and keeps the file
  inside the destination. A pre-scan that refuses both member types was added
  anyway, so the guarantee comes from our code rather than from whichever tar
  is installed.

- **The README told manual verifiers to use the anchor it had just discredited**
  (finding 4). Two passages pointed at the release-attached `SHA256SUMS` while a
  third explained why that file cannot be trusted. All now point at
  `checksums/<tag>.sha256`, with a worked example.

- **`SECURITY.md` now states what verification does and does not prove**, as a
  table of covered and uncovered threats. The uncovered ones are a compromised
  maintainer account and a compromised build machine: the checksum is written by
  the same pipeline that builds the archive, so integrity here is not
  authenticity. Closing that needs a signature anchored outside the pipeline,
  which this project does not have yet — GitHub build attestation is not
  currently possible because releases are not built in GitHub Actions.

### Added

- **Statically linked musl builds for Linux x86_64 and arm64** (#54).
  `reolink-cli-<ver>-external-linux-arm64-musl.tar.gz` and its x86_64 sibling
  join the release. Alpine and the distributions built on it — Home Assistant
  OS is the one that raised this — have no glibc, so the existing Linux
  archives could not merely run badly there, they could not load at all:
  `Error relocating ./reolink-cli: __res_init: symbol not found`. The musl
  archives are static and need no runtime at all.

  `install.sh` detects musl (loader path, with `ldd --version` as a second
  probe) and picks the right archive; `self-update` resolves the musl archive
  when the running binary is a musl build, which it can only know at compile
  time — `env::consts` reports `linux`/`aarch64` for both C libraries, and a
  musl install that updated itself into a glibc binary would be unable to
  start.

  x86_64 is included although only arm64 was asked for. Adding musl detection
  to the installer and then publishing one of the two architectures would mean
  x86_64 Alpine detects musl and finds no archive — a worse failure than not
  detecting it at all.

  These are additions. The glibc archives keep their names, because an existing
  install reconstructs the same filename it came from when it self-updates.

- **`discover` now reports each device's `mac` and hardware model** (#36).
  Asked for by the reporter of the merge bug — a MAC is what lets you line
  eleven cameras up against DHCP leases, and the model is useful for the
  devices that do not answer ONVIF, which is most of them out of the box.

  Both were already in the broadcast reply and were being read past: the
  layout is `net_scan_devinfo_t` from the vendor SDK header, `cMac[32]` at
  offset 164 and `cMouduleType[32]` at 196. The model is published as a
  `reolink-lan://hardware/<model>` scope, mirroring ONVIF's
  `onvif://www.onvif.org/hardware/<model>`, so "what model is this" has one
  place to look whichever probe answered. `mac` merges into the ONVIF record
  like `uid` does, and never overwrites an existing value.

  The `access_key` in the same reply stays unread. It is a credential, it does
  not help identify anything, and the reply is an unauthenticated LAN broadcast
  whose contents end up in logs and agent transcripts. A test asserts it does
  not appear in the output.

### Fixed

- **`REOLINK_PASSWORD` triggered the warning telling you not to put passwords
  on the command line.** `--password` reads that environment variable, so by
  the time the value arrived it was indistinguishable from one typed on argv,
  and the check warned for both — telling anyone following the documented safe
  path to stop doing exactly what they were doing, and printing a second,
  duplicate warning for the people who really were on argv. The remaining check
  reads the actual argv, so it can tell the difference. `--password` on the
  command line still warns, once.

- **`device import` ignored the friendly name of any device without ONVIF.**
  The scope lookup only understood `onvif://www.onvif.org/<key>/`, but the
  Reolink broadcast publishes the name as `reolink-lan://name/…` — so on the
  models that ship with ONVIF off, which is most of them, imported cameras were
  described as "Discovered via lanUdp" and aliased off their IP address. 0.10.6
  had stopped `discover` from throwing that name away; the one command that
  would use it was not looking where it is kept. The lookup now accepts either
  scheme, ONVIF first, so registries that already import keep their aliases
  unchanged.

- **`AGENTS.md` and `GEMINI.md` still described a private-vendor tarball.**
  They told agents to "get a fresh release tarball from their vendor" and
  stated there was "no in-place network upgrade" — while line 131 of the same
  file documented `reolink-cli self-update`, which does exactly that. The
  troubleshooting table also documented an error message,
  `no prebuilt binary for <os>-<arch>`, that appears in neither installer; the
  real ones are `unsupported OS` / `unsupported arch`. Both files now describe
  the one-line installer and `self-update`, and the table lists the strings the
  installers actually print, plus the musl symptom.

- **`GEMINI.md` had the stale "works without the gateway" list**, the one
  corrected in `SKILL.md` a release earlier: `features`, `doctor` and
  `cache status|clean` need no gateway either, and they are what an agent
  reaches for first. One copy had been fixed and the other had not, which is
  the whole problem in miniature.

### Changed

- **The skill's install snippet is now a call to `install.sh`** rather than its
  own copy of the download logic. That copy was the fourth place platform
  detection lived, it had already drifted once (#43), and — the reason this is
  a fix and not tidying — it verified nothing it downloaded. `install.sh`
  checks the archive against the checksum committed to this repository and
  refuses to install on a mismatch.

## [0.10.6] — 2026-07-31

Most of this release came from issues and pull requests opened here.

### Fixed

- **`discover` dropped the UID and device name for any device that answered
  both probes** (#36). Deduplication kept the ONVIF record and discarded the
  Reolink broadcast record wholesale, under a code comment praising ONVIF's
  "rich metadata" — but the UID and the friendly name live *only* in the
  broadcast reply, and those are the two fields that let a person tell eleven
  cameras apart. The reporter had four devices listing without UIDs on Linux.

  Records are now merged per IP: the ONVIF entry gains the UID, the
  `reolink-lan://name/…` scope, the device kind, and the port-qualified host
  (`<ip>:9000`, which is what `device add --host` wants; a bare `<ip>` is not).
  An existing UID is never overwritten.

  Whether a device lands in `lan` or `lanUdp` depends on whether ONVIF is
  enabled on it (off by default on many models) and whether the network passes
  WS-Discovery (Windows Defender commonly eats it). The `counts` split still
  differs between machines and now **stops mattering** — every entry carries the
  same fields whichever bucket it landed in.

  Verified by A/B against hardware: with ONVIF temporarily enabled on a camera
  so it answered both probes, 0.10.5 reported `uid: null`, no name and a bare-IP
  host; this build reports all three with the ONVIF metadata intact.

### Documentation

Six pull requests from @ch-bas, all of them the same defect wearing different
clothes: a fact that lives in the code, restated in prose, where the
restatement had drifted.

- **`--week-table` was documented backwards** (#48). It is `Sun=bit0 … Sat=bit6`,
  now stated with its authority: the vendor SDK defines `iWeekTable` as *"index
  0:sunday, index 1~index 6:Monday->Saturday"*, with four corroborating
  definitions in the same header. The doc said `Mon=bit0` until today, so the
  `31` and `63` copied from it select the wrong days — and a schedule on the
  wrong days does not look broken.
- **`detect motion set --sensitivity` is 1–50, not 0–100** (#49). The range is
  enforced by the parser, so the doc's own example (`--sensitivity 60`) could
  never run. Confirmed three ways: the v20 spec, and both a camera and an NVR
  reporting `{"min": 1, "max": 50}` for themselves.
- **The skill's install snippet could never download anything on macOS** (#47):
  it mapped `Darwin` to `macos` while the published asset says `darwin`, and its
  glob omitted `-external-`.
- **Windows users are no longer told to `self-update`** in the quick start
  (#42) — it covers macOS and Linux only, as the same README says further down.
- **The archive example is platform-agnostic and zsh-safe** (#40); zsh treats an
  unmatched glob as an error rather than passing it through.
- Reference docs no longer restate value ranges or deprecation status (#50).
  `--help` is generated from the code and cannot drift; a hand-copy only gets
  staler. What stays is what `--help` cannot say — for instance that motion and
  AI sensitivity use *different* scales, which is the trap, not the numbers.

### Build

- The version lived in sixteen hand-edited places; now it lives in two. The six
  crates inherit `[workspace.package]`, both README badges became live
  shields.io release lookups (a copy that cannot go stale beats a copy that is
  checked), and the skill's example output no longer names a version. Cutting a
  release is now one line plus a CHANGELOG entry.
- `scripts/check-doc-commands.py` feeds every `reolink-cli` line in a fenced
  code block to the real binary's parser, which validates subcommands, flag
  names and value ranges before a command does anything. It runs against
  TEST-NET-1 with config paths redirected to a temp dir, so nothing touches a
  device. Verified to catch rather than merely pass: restoring `--sensitivity
  60` makes it fail. It cannot see whether a documented *meaning* is right —
  that class is what a human reader catches.

### Policy

- **Published releases and tags are permanent from now on** (#38). Deleting a
  superseded release breaks every downstream pinning that version, and it was
  wrong of us to do it. `v*` tags are now protected by a ruleset with no bypass
  actors (verified: an admin deletion attempt returns 422). Releases 0.10.0
  through 0.10.4 were deleted under the old policy and cannot be honestly
  restored; **0.10.5 is the oldest surviving release and the first one covered
  by this guarantee.**

## [0.10.5] — 2026-07-30

### Fixed

- **`setup --uninstall` did not stop your own gateway on macOS**, then deleted
  the binary out from under it, leaving a process running a file that no longer
  exists.

  This came out of a contributor report (#29, #31) about the docs' manual
  `pkill -f reolink-gateway` fallback matching every install on the machine. The
  same mistake was one layer down in the code, and worse there:
  `process_exe_path` used `ps -p <pid> -o comm=` on non-Linux platforms under a
  comment asserting that prints the executable's full path. It does not — it
  echoes argv[0], so a gateway started as `reolink-gateway` from `PATH` reported
  a bare name, which the ownership check rejects as non-absolute. That comment
  had never been executed.

  The question is now asked backwards: `lsof -t -a -d txt <prefix>/bin/reolink-gateway`
  lists the processes whose *executing image* is that file, which avoids argv
  entirely. `-d txt` restricts it to the image, so a process merely reading the
  binary is not a candidate. Linux keeps `/proc/<pid>/exe`.

  Verified with two gateways from different prefixes, one started by bare name:
  ours was stopped, the second install was left alone.

### Verified

- **`device expand` now has hardware behind it on the firmware from #25.** An
  RLN4E running v3.6.5.562 — the same version as the RLN8-410 in that report —
  confirms the original bug (cmd 199 answers code 300) and the fix: the channel
  with a camera answers, empty channels are refused, and scanning 20 channels
  takes 0.9 seconds.

  The channel field genuinely selects the channel, which is worth stating on its
  own: a protocol that ignored it would look identical on a one-camera device,
  with every channel returning channel 0's data.

  Correction to a note in #25 along the way: on an NVR with no cameras attached,
  cmd 44 is refused on *every* channel, which briefly read as the firmware not
  implementing it. It does. The refusal means "no camera on that channel" —
  exactly the signal the probe wants.

  Non-contiguous numbering is covered by an integration test reproducing the
  reporter's device. Reverting the naming to the 0.10.3 behaviour makes it fail,
  which is the only reason to believe it guards anything.

## [0.10.4] — 2026-07-30

Four fixes found by installing 0.10.3 and running it against real hardware. The
first is 0.10.3's own.

### Fixed

- **`device expand` named child cameras after the wrong channel.** The `channel`
  field was correct; the names were not. Defaults and descriptions used the
  position in the discovered list rather than the real channel number. On the
  NVR from #25 — cameras on channels 1, 9, 10 and 11 — that produces `nvr-ch0`
  through `nvr-ch3`, four aliases each claiming a channel it does not connect to.

  Nothing fails loudly, which is what makes it bad: you find out by wondering
  why `nvr-ch1` shows the wrong camera. It was 0.10.3's fix left half-done — the
  probe learned the real channel numbers and the naming never used them.

  Non-contiguous-channel hardware is not something I have, so this is pinned by
  three unit tests rather than one hand-check.

- **`reolink-gateway --help`, `--version` and `--addr` all failed with
  "invalid socket address".** The binary took `args[1]` as the listen address,
  so any flag was handed to `bind()` and the error pointed at something entirely
  unrelated to the real problem. Unrecognised arguments are now rejected by name;
  `--addr` and the bare positional form both work (`reolink-cli gateway start`
  uses the positional one). `reolink-gateway --version` also reports the build
  flavor now, the same way the CLI does.

- **The CLI could hang forever talking to the gateway.** If something occupies
  the gateway port and accepts the connection without answering, the control
  channel had no timeout: no output, no exit, indefinitely — and an AI agent
  driving the CLI wedges with it. Docker and OrbStack both listen on `:9000` by
  default, the port this tool documents, so it is easy to land in. There is now
  a 60-second bound on the control channel with an error naming the likely
  cause. Preview and VOD share the underlying read path and stay unbounded on
  purpose.

- **The channel scan had no overall budget.** Per-request I/O timeouts (10s) add
  up once a device stops answering mid-scan. The scan is capped at 30 seconds
  total and reports how far it got (`scanned` / `requested`), so a truncated
  scan reads as "checked 6 of 20" instead of looking like a complete answer.

### Added

- **`./scripts/check-version-sync.sh --set <version>`** rewrites all nine version
  locations from one list, then re-checks its own work so a location whose
  pattern drifted is reported rather than skipped (#7, #27).

## [0.10.3] — 2026-07-30

Came from an issue opened here.

### Fixed

- **`device expand` failed on an NVR that declines `GetSupport`** (#25). An
  RLN8-410 on firmware v3.6.5.562 answers cmd 199 with code 300, which aborted
  the whole command.

  Following that report turned up a second, quieter bug: **even when 199
  succeeded, the channels written were wrong.** `channelNum` is a *count*, and
  the code registered `0..count`. The reporter's four cameras sit on channels
  1, 9, 10 and 11 — so on a cooperative NVR it would have created four entries
  pointing at slots 0–3, three of them empty.

  `expand` now asks 199 for an upper bound when it answers, ignores it when it
  does not, then probes each channel and registers only the ones that answer,
  with their real channel number. The probe uses cmd 44 (OSD get), which is
  per-channel and refused on an empty slot.

  The probe runs on **one** connection. The channel travels in each request's
  extension XML rather than in the session, so a single connection can ask
  about every channel. Opening a session per channel would hold one TCP
  connection per candidate — the gateway pools sessions with a 300-second TTL
  and reaps them lazily — and an NVR that caps concurrent connections would
  start refusing partway through, silently reporting the rest as empty. That
  would produce a short, confident, wrong channel list: worse than the hard
  failure it replaced. Measured after scanning 20 channels: 1 established
  connection to the device.

  Not verified: no RLN8-410 here. The single-connection property and the
  single-camera refusal are verified on hardware; the non-contiguous channel
  path is sound in logic and untested in fact.

## [0.10.2] — 2026-07-29

Both changes came from issues opened here.

### Added

- **`config get performance`** — live device load: `cpuUsedPercent`, `codeRate`,
  `netDataRate` (#9). Verified on hardware: an E1 Outdoor reports 60% CPU.

  Not every model implements it. Those answer with a device-level rejection
  rather than a fabricated zero — a camera reported as 0% busy when it never
  said so would be worse than an error. `codeRate` reads 0 on an idle camera and
  only becomes meaningful while a stream is running; it is reported rather than
  hidden, so you can tell "idle" from "not reported".

  This is distinct from `benchmark`, which times the **client** round trip.

### Fixed

- **Protocol-detection failures blamed the host when the host was fine** (#10).
  An NVR channel failed with `unable to detect protocol — device unreachable, or
  not a Reolink v20/v30 device` while another channel on the same host worked in
  the same session, sending the reporter to check VLAN routing and firewall
  rules.

  Each channel opens its own session, so the probe runs **per channel** —
  blaming the host is wrong by construction whenever another channel is working.
  The probe also collapsed four outcomes into one: connect timed out, connect
  refused, **connected but no answer**, and unrecognised magic. That third case
  matters: a device that is up but declining an additional connection looks
  identical on the wire to one that is unreachable.

  The message now names the channel and the actual failure, and points at
  `--protocol v20` to skip the probe.

## [0.10.1] — 2026-07-27

### Fixed

- **`self-update` could never download anything.** It asked for
  `reolink-cli-<ver>-macos-arm64.tar.gz` while the published archive is
  `reolink-cli-<ver>-external-darwin-arm64.tar.gz` — all three supported
  platforms were wrong. The archives had gained an `-external` flavour segment
  so an internal build can never be mistaken for the customer build, and the
  macOS token had moved from `macos` to `darwin`; neither reached the updater.
  It stayed invisible because the download only happens when an update exists —
  running it on the current version returns `already up to date` and never gets
  that far.

  Windows remains unsupported by `self-update` and now says so with the download
  link: that archive is a `.zip` while the updater only untars, and a running
  `.exe` cannot be replaced in place. Upgrade there by extracting the new
  archive and running `install.ps1`.

- **The agent skill misspelled `--cameras` as `--cameraes`.** A copied command
  failed with an unrecognized-argument error.

### Build

- The packaging script now refuses to produce an archive whose filename the
  updater cannot reconstruct, so this class of drift cannot ship again.

## [0.10.0] — 2026-07-25

Stored camera passwords are no longer kept in plaintext.

### Breaking

- **Passwords in `aliases.toml` are now ciphertext** (`RLENC1:…`, AES-256-GCM),
  decrypted with a key in `credentials.key` beside it (`0600`). An existing
  plaintext config is converted automatically the first time you run any
  command — **you do not have to do anything**, and hand-written plaintext
  passwords keep working and are converted on the next load. The `password` in
  `config.toml` is the last fallback in the same resolution chain and is covered
  too.
- **`aliases.toml` can no longer be copied or backed up on its own** — take
  `credentials.key` with it. With only one of the two the passwords cannot be
  recovered and must be re-entered with
  `reolink-cli device update <camera> --password-stdin`.

### Why

This tool is built to be driven by AI agents, and reading a config file is the
cheapest thing an agent can do: with plaintext, a single `cat` puts every camera
credential into a transcript that usually leaves the machine. The real isolation
boundary is still the operating system (`0600`); the ciphertext is a second
layer so that obtaining the file alone — a copy, a backup, an agent reading it —
yields nothing. It does not defend against something that reads the key file as
well.

### Notes

- One entry that cannot be decrypted no longer takes the whole file down with
  it: it keeps its ciphertext, the rest of the registry loads normally, and the
  error is raised only when that camera is actually used. Otherwise the repair
  itself (`device update`) would hit the same error and leave no way out.
- A missing or mismatched key is reported as exactly that, with the command to
  fix it — never as an empty password or a silent login failure against the
  camera.
- Encryption failure is a hard error; nothing is written. A password is never
  stored readable while reporting success.

## [0.9.1] — 2026-07-25

Found while validating the published 0.9.0 packages end to end. The security
boundary was re-verified and is unchanged (cross-origin rejection, media
endpoint authentication, no credentials in URLs, loopback-only default bind,
`0600` credential files); everything below is functional or documentation.

### Behaviour change

- **A bare `ptz focus auto` now reads the setting instead of erroring.** 0.9.0
  changed it from "silently enable autofocus" to a hard error, which stopped it
  from mutating your camera but left no way to read the setting back at all —
  you could change autofocus without being able to record what it had been.
  Writing still requires an explicit `--enable` / `--disable`.

### Fixed

- **Uninstall left the installer's `PATH` export in your shell rc.** The block
  `install.sh` appends to `~/.zshrc` says it is removed on uninstall, but
  nothing removed it: the bundled `uninstall.sh` forwards to
  `reolink-cli setup --uninstall`, which had no shell-rc handling. Every
  uninstall left behind an `export PATH` pointing at a deleted directory. It is
  now stripped precisely between its `# >>> reolink-cli PATH >>>` markers,
  across `.zshrc`, `.bashrc`, `.bash_profile` and `config.fish`. A block
  belonging to a different install prefix is left alone, and a block whose
  closing marker is missing (hand-edited) is refused rather than deleted to
  end-of-file.
- **The skill documented a `--keep-config` flag that does not exist**, so an
  agent following it produced `error: unexpected argument`. Omitting `--purge`
  is what preserves config, cache and state. The skill now also states that the
  agent skill directories are global paths, removed regardless of
  `REOLINK_PREFIX`.
- **`AGENTS.md` documented a `REOLINK_PURGE` environment variable for a full
  wipe on Windows.** `uninstall.ps1` only forwards arguments and never reads the
  environment, so anyone following it believed their stored credentials had been
  erased while the files remained on disk. Use `--purge` on both platforms.
- **An exported-but-empty `ZDOTDIR` was treated as set**, diverging from the
  installer's `${ZDOTDIR:-$HOME}`.

## [0.9.0] — 2026-07-25

Fixes from a three-platform black-box regression (macOS / Windows / Linux) and
live-hardware testing. **Contains three behaviour changes** — read the first
section before upgrading if you parse this tool's output in scripts.

### Behaviour changes (may break scripts)

- **`light ir get` now returns `on` / `off` / `auto`**, matching what `--state`
  accepts. It previously echoed the device's own words `open` / `close`, so
  `set --state off` followed by `get` reported `close` and a script asserting on
  what it had just written always failed.
- **`ptz zoom set` / `ptz focus set` no longer echo the value you passed.** They
  returned `{"pos": <your request>}` without ever reading the device back —
  asking for zoom 999 on a lens whose maximum is 27 answered `{"pos": 999}`
  while the lens sat at 27. They now read back and report
  `{pos, requested, verified}`, and when the position cannot be read they omit
  `pos` entirely and report `verified: false`.
- **`ptz focus auto` now requires an explicit `--enable` or `--disable`.** With
  no flag it used to default to "enable", so a command that reads like a query
  silently switched autofocus on.

### Fixed

- **Recording search returned nothing for any multi-day range.** The firmware
  answers a wide time range with an empty list rather than an error, which is
  indistinguishable from "no recordings" — a whole-month search always came back
  empty, and so did `--since` as soon as it spanned more than a day. The range is
  now split into per-day queries and merged. Verified on hardware: 0 → 200
  recordings for a full month.
- **`ping` with a multi-device selector failed outright** instead of fanning out,
  which is exactly the case you want it for ("which of these are online?"). It
  now emits the same `{summary, results[]}` envelope as other batch commands, and
  an unreachable camera counts as failed in the summary and exit code — it
  previously reported all-clear.
- **`setup --uninstall` killed gateway processes belonging to other installs.**
  Termination is now scoped to the prefix being removed.
- **`--purge` left the state directory behind on Windows** because the
  uninstaller derived its own paths, which had drifted from the ones the
  application uses. Both now come from one list, which also covers the legacy
  directories the app migrates from.
- **A device saying "this model has no such feature" with a 400 was
  indistinguishable from a bad parameter** — no PTZ, no SD card and an
  unsupported AI type all reported only `device command N failed`.
- The protocol selector for `stream url` is `--kind`; every documented example
  said `--protocol`, which fails.
- Corrected the documented format of a downloaded recording: current firmware
  returns a complete MP4, not the raw frame stream the docs described.

## [0.8.0] — 2026-07-25

Security release. **Contains breaking changes** — if you script the gateway HTTP
API directly, read the first two items before upgrading.

- **Camera passwords are no longer accepted in gateway URLs.** `/api/snapshot`,
  `/api/vod/download` and `/api/preview/video` now require a session token and
  resolve the device credentials server-side. Putting the password in a URL leaked
  it into shell history, `ps` output and any proxy log on the path. If you built
  those URLs with `&user=…&password=…`, get a token from `set auth.login` and pass
  `?token=…` instead; the token is bound to its device.
- **The gateway now refuses browser cross-origin requests.** Every response
  previously carried `Access-Control-Allow-Origin: *` while
  `POST /api/cameras/<name>/login` required no authentication, so any web page you
  visited could obtain a token and read your camera snapshots and live detection
  events — binding to loopback did not prevent this, because the browser runs on
  the same machine. Requests whose `Origin` does not match the address they were
  sent to are now rejected. Callers that send no `Origin` — `curl`, go2rtc, Home
  Assistant, and `<img src>` / `<video src>` embeds — are unaffected.
- **Session tokens now expire** after 300 seconds of inactivity (the window
  refreshes on each use). Previously a token stayed valid for the life of the
  gateway process.
- **MCP tools no longer accept a plaintext `password` argument.** It would be
  written verbatim into the agent's transcript. Register cameras with
  `reolink-cli device add` and target them by `alias`, or set `REOLINK_PASSWORD`
  when starting the server.
- **The gateway binds `127.0.0.1` by default** instead of all interfaces. Pass
  `--addr 0.0.0.0:9000` to expose it on the LAN deliberately.
- **Fixed a denial-of-service in XML parsing** (RUSTSEC-2026-0194 / -0195). Device
  replies are untrusted input, so a malformed one could pin the CPU.
- Snapshots, recordings, captures, log exports and the event-monitor history are
  now written owner-only; config files are written atomically so a password is
  never briefly readable by other local accounts. On Windows, config files now get
  an owner-only ACL.
- **Release archives ship a `.sha256`** — verify your download before extracting.
- **New MCP tool `camera_snapshot`** — JPEG capture, matching the `snapshot` CLI
  command.
- `preview stop` issued immediately after `preview start` no longer fails.
- `setup --uninstall` no longer leaves a stray skill document behind.

## [0.7.2] — 2026-07-21

Patch release. A full independent retest of 0.7.1 plus several rounds of deep
testing found and fixed a batch of edge-case bugs, all verified on real hardware.

- **`ping <ip>` works with a bare IP again** — it no longer demands an explicit
  `:port`.
- **Rapid, back-to-back `snapshot` calls no longer occasionally fail** — added an
  automatic retry so quick bursts (and `benchmark`) are reliable.
- **Clearer errors.** Motion-detection sensitivity is validated to the range the
  camera actually accepts; a feature the camera doesn't support now says so
  plainly instead of a cryptic failure; an unreachable camera reports a network
  error (not an auth error); `osd set --name` and `image tune` give precise
  bounds. `wifi get` output is flattened to match every other command.
- **`doctor` self-repair fixes config permissions correctly** (previously it
  could leave `config.toml` in a state the CLI itself rejected).
- Docs/help: corrected the `raw` example and the macOS cache path shown by
  `cache` / `status`.

## [0.7.1] — 2026-07-21

Patch release. Fixes found in a pre-release audit, verified on real hardware.

- **`stream url` no longer prints your password by default.** The default output
  now shows only the host, user and stream URLs (plus a `with_auth` flag). Pass
  `--with-auth` to get a ready-to-paste URL with the credentials embedded. This
  keeps passwords out of logs, terminals and AI-assistant context.
- **Light controls now take effect.** Setting the IR / night-vision LED and the
  body status LED previously reported success without changing anything on the
  camera. `light ir` and `light statusled` (and the matching MCP tools) now work,
  and `light statusled` confirms the change — returning a clear error instead of a
  false success if the camera can't apply it.
- **Clearer error when a camera name is rejected.** `osd set --name` now explains
  that the camera only accepts letters, digits, spaces and hyphens (no `_ . #`),
  instead of a cryptic protocol error.
- **Safety warnings.** The CLI warns when a password is passed on the command line
  (visible to other processes) and when the gateway is started on an address
  reachable from your network.

## [0.7.0] — 2026-07-20

- **Device running log** — browse and export the camera's on-device log
  (`reolink-cli log …`).
- **One-line install** — `curl … install.sh | sh` (macOS/Linux) and
  `install.ps1` (Windows); no Node required for the CLI or Claude Code.
- **`self-update`** pulls the latest build from GitHub Releases.
- **MCP** launcher now passes `REOLINK_GATEWAY_ADDR`, so a non-default gateway
  address works out of the box.
- **Prebuilt binaries** — macOS arm64, Linux x86_64, Windows x86_64.

## [0.6.0] — not published

Prepared as the first public distribution but never released here; the
first published release was 0.7.0. Kept for the record of what it covered.

- LAN-only camera operation: discover, login, info, snapshot, live preview, PTZ,
  IR / spotlight / LEDs, image tuning, OSD, motion + AI detection, recording +
  SD-card status, VOD search/download, alarm events, users, reboot, firmware
  upgrade, RTSP/RTMP/FLV stream URLs.
- Cross-agent skill/plugin: install into Claude Code, Codex, Cursor, Gemini,
  OpenCode, and 70+ agents via `npx skills add`.
- Prebuilt binaries for macOS (arm64), Windows (x64), and Linux (x64),
  with `SHA256SUMS` and bundled `THIRD-PARTY-LICENSES.txt`.
