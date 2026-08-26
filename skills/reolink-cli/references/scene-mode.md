# Scene Mode: Hub Arming Profiles

## Scope

`scene *` — the Reolink app's Home / Away / Disarm control on a **hub or NVR**.
A scene is a named set of per-channel task bits; switching scenes re-arms every
paired camera at once.

Not to be confused with `detect motion|ai set`, which is per-camera detection
config. Scene mode does not change *what the camera detects* — it changes *what
the hub does about it*.

## Rules

- **Must** run `scene show` before `scene set` — the ids are device-specific
  (`[1, 2, 3]` on one hub is not `[1, 2, 3]` on another), and `scene show` also
  reports `supportedIpcTasks`, which is the only honest list of task names that
  device will act on.
- **Must** treat `currentSceneId: 0` as "the weekly schedule is driving", not as
  a scene. `scene show` surfaces it as `followSchedule: true`.
- **Must** warn the user before `scene edit --tasks` — it **replaces** the
  scene's task set rather than adding to it. A scene edited down to no tasks
  records nothing and notifies nobody, and nothing on the device says so.
- **Forbidden** using `scene *` against a single camera. These commands exist on
  hubs and NVRs; a plain IPC answers 405.
- `audio` in the task list is the **siren**, not the microphone.

## Read

```bash
reolink-cli --camera hub scene show     # active scene + capability + ids
reolink-cli --camera hub scene list     # every scene, per-channel tasks
reolink-cli --camera hub scene status   # the running scene, in full
```

`scene show` output worth reading:

| Field | Meaning |
| --- | --- |
| `currentSceneId` | Active scene, or `0` for "follow the schedule" |
| `followSchedule` | The same thing, spelled out |
| `supportedIpcTasks` | Task names this device honours — read-only capability |
| `keyEnable` | Whether the hub's Home button cycles scenes. `-1` = unsupported |
| `enterPrivateMode` | Privacy mode while disarmed. `-1` = unsupported |

## Switch

```bash
reolink-cli --camera hub scene set 3           # arm for leaving
reolink-cli --camera hub scene set --schedule  # hand back to the timetable
```

An id the hub does not have is rejected, and the error lists the ids it does
have — so a failed `scene set` tells you what to run instead.

## Task bits

| Bit | Name | What it gates |
| --- | --- | --- |
| 0 | `record` | Recording on alarm |
| 1 | `ftp` | FTP upload |
| 2 | `email` | Email |
| 3 | `push` | Push notification |
| 4 | `audio` | **The siren** |
| 5 | `linkage` | Alarm linkage |
| 6 | `speaker` | Local speaker |
| 7 | `track` | Auto-track |

IoT tasks: `linkage`, `device`.

```bash
# Replace channel 0's tasks; every other channel keeps what it had
reolink-cli --camera hub scene edit 2 --tasks record,push --channel 0

# Every channel in the scene
reolink-cli --camera hub scene edit 2 --tasks record

# Clear every task on the scene
reolink-cli --camera hub scene edit 2 --tasks ""

# Metadata
reolink-cli --camera hub scene edit 2 --name evening --delay 30
```

## Weekly schedule

The timetable only drives anything while `currentSceneId` is `0`.

```bash
reolink-cli --camera hub scene schedule get
reolink-cli --camera hub scene schedule set --scene 3 --days 1,2,3,4,5 --from 9 --to 17
```

- `--days` uses the **device's own 0-6 numbering**. Which weekday index 0 is
  varies by firmware — read `scene schedule get` and compare against a day you
  know rather than assuming Sunday or Monday.
- `--to` is **exclusive**: `--from 9 --to 17` covers 09:00–16:59.
- Omitting `--days` writes **every day**.
- The device stores 2 half-hour slots per hour; the CLI writes both, so an hour
  is never left half-armed.

## Alarm mapping

```bash
reolink-cli --camera hub scene alarm get --channel 0
reolink-cli --camera hub scene alarm set --task REC --types people,vehicle
reolink-cli --camera hub scene alarm set --task REC --types ""   # trigger on nothing
```

Which alarm types feed each task on that channel. Task names come back
upper-case here (`REC`, `FTP`) and lower-case in `supportedIpcTasks` — that is
the device's inconsistency, not a bug in the output; `--task` accepts either
case.

`--types` **replaces** the task's set and is required — leaving it off would
otherwise mean "trigger on nothing", which is not a default worth having.

## Options

```bash
reolink-cli --camera hub scene options --key-disable        # stop the Home button cycling
reolink-cli --camera hub scene options --private-mode       # privacy while disarmed
```

A device reporting `-1` for one of these does not support it, and the command
says so instead of writing a value the firmware ignores.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `405` on every `scene` command | Not a hub — plain IPCs have no scene mode |
| `scene set` succeeded, nothing changed | The scene's task bits are all off; check `scene list` |
| Schedule edits do nothing | `currentSceneId` is not `0`, so a pinned scene overrides the timetable |
| `unknown scene task '...'` | Typo, or a task this device does not honour — `scene show` lists what it does |
