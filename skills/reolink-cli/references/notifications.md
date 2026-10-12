# Push Notifications

## Scope

notify push reads or changes alarm notifications delivered to the Reolink mobile
app. Reading or changing settings requires a running gateway; receiving
notifications also requires push delivery to be configured in the app.

Use the camera alias registered with device add. For gateway event subscriptions,
see [events.md](events.md).

A rich notification includes a camera image or animated GIF with the alarm
message. Text-only mode does not disable push notifications. These commands
update settings; they do not send a test push or register a phone for delivery.

## Rules

- Check the current configuration with notify push get before changing it.
- --interval SECS controls the cooldown between app alarm notifications. The
  device controls which intervals it accepts.
- --rich 0 selects text only and does not disable push; --rich 1 adds a camera
  image; --rich 2 adds an animated GIF.
- Image and GIF formats depend on device and mobile app support. Confirm support
  before enabling a rich format.
- --consent 0 means the privacy agreement is not accepted; --consent 1 means it
  is accepted. Do not set 1 unless the user has accepted the agreement.
- Omitted options preserve current settings, including consent. Do not add
  --consent 1 automatically when changing the notification format.

For a first end-to-end check, enable push for the camera in the Reolink app,
make sure a detection rule is enabled, then run get, set, and get. Trigger the
enabled motion or AI rule in front of the camera to test delivery. A successful
set only means the camera accepted the saved value; these commands never send a
test push, and a saved value does not prove that the phone received anything.

## Commands

```bash
# Read current settings
reolink-cli --camera front-door notify push get

# Change only the cooldown; keep format and consent
reolink-cli --camera front-door notify push set --interval 30

# Add a camera image, if supported
reolink-cli --camera front-door notify push set --rich 1

# Use an animated GIF, if supported
reolink-cli --camera front-door notify push set --rich 2

# Use text-only notifications without disabling push
reolink-cli --camera front-door notify push set --rich 0
```

## Reading the result

The CLI returns an envelope with ok and data fields. For get, data.interval
is the cooldown in seconds; data.richNotificationEnable maps to --rich; and
data.consentAgreement maps to --consent. A successful set means the device
accepted the settings; it does not prove that a notification reached the phone.

## Related

- [detection.md](detection.md): disabling detection rules removes push triggers.
- [events.md](events.md): the gateway event bus uses a different mechanism.
