# CLI

`hearthbox` helps you manage your setup after Install: utilities and helper commands to
update it and check on its services. It's linked into the Hearthbox user's
`~/.local/bin`, and runs as that user, without root:

| Command | What it does |
|---------|--------------|
| `hearthbox pull` | get new versions of the repo from its git remote, then apply them. Stops without merging if `~/repo` has commits of its own: pull those with git, then run `hearthbox update` |
| `hearthbox update` | apply `~/repo` as it is, e.g. after you edit it |

`pull` and `update` apply the repo with `scripts/update.sh` (see [how updates work](development.md#hearthbox-pull-and-hearthbox-update)).

## Services

`<service>` is a service's name, as `hearthbox services list` shows it (e.g. `jellyfin`).

| Command | What it does |
|---------|--------------|
| `hearthbox services list` | every service this host should run, and its state (`active`, `failed`, ...), including one that never started |
| `hearthbox services status <service>` | the service's state in detail: since when, why it stopped or failed, and its last log lines |
| `hearthbox services logs <service>` | the service's logs. Anything after the name goes to `journalctl`: `-f` follows them live, `-b` since the last boot, `-n 100` the last 100 lines |
| `hearthbox services restart <service>` | restart the service, e.g. after it failed, or after you change its config or its `.container` file, so it uses the new one. Checks its unit first, and doesn't restart it if the unit has errors |
| `hearthbox services restart all` | the same for every service, and stops the services whose unit is gone (e.g. a service you removed) |
