# PTZ

Speed is 1–64 (not percent). If user says "speed 50", ask whether they mean % (→ 32) or literal 50.

Directions: `left right up down left-up left-down right-up right-down`.

## Move & Stop

```bash
reolink-cli --camera front-door ptz move left --speed 24
reolink-cli --camera front-door ptz stop

# Pulse move (gateway assists with start/stop timing)
reolink-cli --camera front-door ptz move right-up --speed 32 --duration-ms 500
```

## Presets (IDs 0–255)

```bash
reolink-cli --camera front-door ptz preset list
reolink-cli --camera front-door ptz preset goto 1
reolink-cli --camera front-door ptz preset set 1 "Entrance"
reolink-cli --camera front-door ptz preset delete 1
```

## Zoom / Focus

```bash
reolink-cli --camera front-door ptz zoom get
reolink-cli --camera front-door ptz zoom set --pos 100
reolink-cli --camera front-door ptz focus get
reolink-cli --camera front-door ptz focus set --pos 50
reolink-cli --camera front-door ptz focus auto --enable
reolink-cli --camera front-door ptz focus auto --disable
```

## Patrol

```bash
reolink-cli --camera front-door ptz patrol list
reolink-cli --camera front-door ptz patrol start
reolink-cli --camera front-door ptz patrol stop
```

## Guard Position

```bash
reolink-cli --camera front-door ptz guard get
reolink-cli --camera front-door ptz guard snapshot           # save current as guard
reolink-cli --camera front-door ptz guard goto               # move to guard
reolink-cli --camera front-door ptz guard set --enable --timeout 60
reolink-cli --camera front-door ptz guard set --disable
```

## Auto-Tracking

Detect types for tracking: `motion people vehicle face dog_cat visitor package cry`.

```bash
reolink-cli --camera front-door ptz autotrack get
reolink-cli --camera front-door ptz autotrack set --enable --detect-type people,vehicle
reolink-cli --camera front-door ptz autotrack set --enable --mode 1 --priority people,vehicle
reolink-cli --camera front-door ptz autotrack set --disable
```
