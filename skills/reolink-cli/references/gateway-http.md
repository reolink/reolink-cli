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

## Streaming Endpoints (token via query)

Browser-native elements (`<video src>`, `<img src>`) use the query-string token.
The token supplies the device credentials server-side — **never put `user` /
`password` in a URL**; the gateway rejects requests without a valid token.

```bash
# Events NDJSON
curl -Ns "http://127.0.0.1:9000/api/events?token=$TOKEN&types=motion,people"

# Snapshot JPEG
curl -s -o /tmp/snap.jpg "http://127.0.0.1:9000/api/snapshot?token=$TOKEN&host=192.168.1.43:9000&stream=sub"

# Recording download
curl -s -o /tmp/clip.h264 "http://127.0.0.1:9000/api/vod/download?token=$TOKEN&host=192.168.1.43:9000&fileName=$NAME"
```

There is a fourth streaming endpoint, `/api/preview/video` (live video for
browser `<video src>` elements), with the same token-in-query rule.

## Response Shapes

```jsonc
// Success
{"status":"success","data":{...}}

// Error — HTTP status equals .code
{"status":"error","code":403,"message":"invalid or expired token"}
```

## Removed in v0.1.2

`POST /api/login` and `POST /api/request` now return HTTP 410. Use `POST /api` + Bearer instead.
