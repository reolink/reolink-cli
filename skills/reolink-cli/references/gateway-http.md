# Gateway HTTP API (non-CLI clients)

Single entry `POST /api` with Bearer token and `{action, path, params}` body. Only exception: `set auth.login` is pre-auth (it issues the token).

## Start the Gateway

```bash
reolink-cli gateway start --addr 127.0.0.1:9000 &
```

## Login → Token

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:9000/api \
  -H 'Content-Type: application/json' \
  -d '{
        "action": "set",
        "path":   "auth.login",
        "params": {
          "username": "admin",
          "password": "secret",
          "host":     "192.168.1.43:9000",
          "protocol": "auto"
        }
      }' | jq -r .data.token)
export AUTH="Authorization: Bearer $TOKEN"
```

Response shape: `{"status":"success","data":{"token":"…","info":{…}}}`

## Authenticated Calls

```bash
# Read
curl -s -X POST http://127.0.0.1:9000/api -H "$AUTH" \
  -d '{"action":"get","path":"system.info"}'
curl -s -X POST http://127.0.0.1:9000/api -H "$AUTH" \
  -d '{"action":"get","path":"image.tune"}'
curl -s -X POST http://127.0.0.1:9000/api -H "$AUTH" \
  -d '{"action":"get","path":"osd"}'

# Write
curl -s -X POST http://127.0.0.1:9000/api -H "$AUTH" \
  -d '{"action":"set","path":"image.tune","params":{"bright":140,"contrast":150}}'

# Reboot (no params)
curl -s -X POST http://127.0.0.1:9000/api -H "$AUTH" \
  -d '{"action":"set","path":"system.reboot"}'
```

## Real Hub child binding

Use a token issued by logging in to the **parent Hub on channel 0**, with a
reachable Hub LAN address and compatible firmware. POST either body below to
`/api` with that Bearer token. Read `system.info` before and after the change
to inspect channels. This changes actual bindings, not the local alias registry.

```jsonc
// Add by child IPv4 address; password is the child's current password.
{"action":"set","path":"hub.add","params":{
  "channel":0,"ip":"192.0.2.30","port":9000,
  "userName":"admin","password":"<CHILD_PASSWORD>"
}}
// Unbind; password is the new standalone password to set on the child.
{"action":"set","path":"hub.remove","params":{
  "channel":0,"port":0,"userName":"admin","password":"<STANDALONE_PASSWORD>"
}}
```

`channel` (0–63), `port`, `userName`, and `password` are required. For addition,
provide exactly one of `ip` or `uid`; a UID is sent to the Hub for pairing.
Removal requires empty/omitted `ip` and `uid` and a nonempty password. User names
and passwords must fit 31 bytes. Construct request bodies in memory; keep
passwords out of URLs, command arguments, logs, and response dumps.

The HTTP API has no interactive confirmation: obtain the user's intended Hub,
channel, and permission before submitting. Allow at least 120s on the HTTP
client; the device operation can wait 64s. Disable automatic retries for these
mutations. A timeout means unknown outcome; inspect channels before another
attempt. Responses expose `data.channel`, `data.operation`, and numeric channel
fields under `data.result.channels`. They do not return child credentials.
Local aliases are unchanged; use `device expand` after a confirmed addition.
Wi-Fi reassignment is not exposed. See [setup.md](setup.md#real-hub-child-binding-and-unbinding)
for device error meanings and the CLI workflow.

## Streaming Endpoints (token via query)

Browser-native elements (`<video src>`, `<img src>`) use the query-string token.
The token supplies the device credentials server-side — **never put `user` /
`password` in a URL**; the gateway rejects requests without a valid token.

```bash
# Live video for a browser <video src> element
curl -Ns "http://127.0.0.1:9000/api/preview/video?token=$TOKEN&host=192.168.1.43:9000&stream=sub"

# Stop that stream
curl -s -X POST "http://127.0.0.1:9000/api/preview/stop?token=$TOKEN"

# Events NDJSON
curl -Ns "http://127.0.0.1:9000/api/events?token=$TOKEN&types=motion,people"

# Snapshot JPEG
curl -s -o /tmp/snap.jpg "http://127.0.0.1:9000/api/snapshot?token=$TOKEN&host=192.168.1.43:9000&stream=sub"

# Recording download
curl -s -o /tmp/clip.h264 "http://127.0.0.1:9000/api/vod/download?token=$TOKEN&host=192.168.1.43:9000&fileName=$NAME"
```

## Dashboard Endpoints

The gateway's built-in dashboard drives itself through these. They are stable
enough to script against, but the CLI is the supported surface — reach for these
only when you are building a UI.

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/health` | GET | liveness; no token required |
| `/api/features` | GET | what this build supports (same data as `features`) |
| `/api/cameras` | GET / POST | list the registry / add an entry |
| `/api/discover` | GET | LAN discovery, same probes as `discover` |
| `/api/doctor` | GET | health checks; `/api/doctor/fix` (POST) applies them |
| `/api/recent-ops` | GET | recent operations, for the dashboard's activity list |

This table and the streaming list above are the complete set the gateway
serves. If you find one that is not here, the docs are stale — please say so.

## Response Shapes

```jsonc
// Success
{"status":"success","data":{...}}

// Error — HTTP status equals .code
{"status":"error","code":403,"message":"invalid or expired token"}
```

## Removed in v0.1.2

`POST /api/login` and `POST /api/request` now return HTTP 410. Use `POST /api` + Bearer instead.
