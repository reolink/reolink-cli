# Display & Peripherals: Light / Image / OSD / Audio / Privacy

## Light

Status-LED = small body LED. IR = invisible night-vision. Spotlight = manual white. Whiteled = same bulb, alarm-triggered.

```bash
# IR LED (night vision)
reolink-cli --camera front-door light ir get
reolink-cli --camera front-door light ir set --state auto    # or on / off

# Status indicator LED
reolink-cli --camera front-door light statusled get
reolink-cli --camera front-door light statusled set --state off

# Spotlight (manual; --duration is deprecated — re-arming extends the
# on-period, it does not pulse; use `light spotlight blink` for flashes)
reolink-cli --camera front-door light spotlight set --enable
reolink-cli --camera front-door light spotlight set --disable

# White LED alarm config
reolink-cli --camera front-door light whiteled get
reolink-cli --camera front-door light whiteled set --enable --brightness 80 --detect-type people,vehicle
```

## Image

`image tune` uses 0–255 (128 = neutral). If the user says "60%" → `~160`. Call it out so they can correct.

```bash
# Flip / mirror
reolink-cli --camera front-door image flip get
reolink-cli --camera front-door image flip set --flip
reolink-cli --camera front-door image flip set --no-flip --mirror
reolink-cli --camera front-door image flip set --no-flip --no-mirror

# Tune
reolink-cli --camera front-door image tune get
reolink-cli --camera front-door image tune set --bright 140 --contrast 150
reolink-cli --camera front-door image tune set --bright 128 --contrast 128 --saturation 128 --hue 128 --sharpen 128
```

## OSD (On-Screen Display)

```bash
reolink-cli --camera front-door osd get
reolink-cli --camera front-door osd set --name "Front Door"
reolink-cli --camera front-door osd set --datetime --name-overlay
reolink-cli --camera front-door osd set --no-datetime
```

"Rename" is ambiguous — `osd set --name` changes the ON-SCREEN label. To rename the device as shown in the Reolink app, use `config set device-name` (see `setup.md`).

## Audio

`audio volume` is the master; `audio config.volume` is per-profile. When the user says "volume N" they usually mean master.

```bash
reolink-cli --camera front-door audio config get
reolink-cli --camera front-door audio config set --volume 80
reolink-cli --camera front-door audio volume get
reolink-cli --camera front-door audio volume set 70        # master, 0-100
reolink-cli --camera front-door audio mute                 # alarm-audio only
reolink-cli --camera front-door audio unmute
reolink-cli --camera front-door audio replies              # list quick-reply clips
```

## Privacy Masks

Region JSON: array of `{block:{x, y, width, height}}` in device-pixel coordinates. Always `get` first to see current layout before editing.

```bash
reolink-cli --camera front-door privacy mask get
reolink-cli --camera front-door privacy mask set --enable
reolink-cli --camera front-door privacy mask set --disable
```

Disabling removes masking — previously hidden regions go into recordings. Warn user.
