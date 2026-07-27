---
description: Discover Reolink devices on the local network (UDP broadcast, 2s)
---

Run `reolink-cli discover --output json` and parse the `data.devices[]` array. Report each device as one line:

```
<host>  uid=<uid>  "<name-from-scopes>"
```

If no devices found, say so plainly and mention that UDP broadcast doesn't cross subnets — if the user's cameras are on another VLAN they will not show up here.

Do not re-scan with longer timeouts unless the user explicitly asks. The default 2 s already catches everything on the local broadcast domain.
