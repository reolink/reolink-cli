---
description: List registered Reolink aliases (from ~/.config/reolink/aliases.toml)
---

Run `reolink-cli device list --output json` and print each alias on one line as:

```
<alias>  <host|uid>  tags=[<tags>]  <description>
```

Omit the password/hasPassword column (the CLI already masks it; don't repeat what's sensitive). If the alias list is empty, tell the user to register one with `reolink-cli device add <alias> --host <ip> --user admin`.
