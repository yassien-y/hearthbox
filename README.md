# Hearthbox

One installer turns a Linux machine you own into a complete home server: services,
names to reach them by, private access from anywhere, and updates, all in one place.

- **The whole system, not just the apps.** One install sets up the Hearthbox user, network
  rules, DNS or a private network (Headscale or NetBird), HTTPS, and every service, and
  keeps them easy to update.
- **Easy to reach.** Open services by name (e.g. `https://jellyfin.hearthbox`) from your
  network or through Headscale or NetBird. No IPs or ports to remember, even if the
  server's address changes.
- **Private and secure.** Every service runs rootless, over HTTPS, and no web interface
  is exposed to the internet. In internet mode, only the server of the VPN you pick at
  install (Headscale or NetBird) is, and its client on the server is the one part that
  runs as root.
- **Modular.** Pick the service groups you want at install: media, vault and AI, with
  household coming soon. See [the services](docs/services.md).
- **Everything in one place.** A dashboard shows every service and the server's
  health, and SearXNG gives you private web search.
- **Built for Linux.** Podman containers run as systemd services, with nftables for
  networking. No extra runtimes.
- **Your setup is a Git repo.** Run it as it comes, change it, or share your own
  version.

## Is this for me?

Yes, whether you're technical or not: it's a solid base for your home server.
- **New to home servers?** It works as it comes: answer a few questions, and it's running.
- **Technical?** Build on it: every part is plain config in a Git repo you can change.

To reach it from anywhere, you also need a public domain: a domain name you own.

## Design principles

- **Minimal dependencies.** As native as possible: tools as close to the kernel as
  possible, and as few dependencies and runtimes as possible.
- **Security.** Root runs only when necessary, every service runs in a container (in
  internet mode, the VPN's client runs on the server itself), and ports are exposed only
  when absolutely necessary.
- **Minimal footprint.** The system is [easy to uninstall](docs/setup.md#uninstall): it
  removes everything Install set up, and keeps the files your services serve, in
  `/srv/hearthbox`.
- **Reproducible.** The whole setup lives in a Git repo, so it can be rebuilt on any
  machine, every change is recorded and can be undone, and Git can merge new versions
  with your own changes.

## Docs

- [Setup](docs/setup.md): step-by-step instructions to install it
- [Services](docs/services.md): every service by group, and its ports
- [CLI](docs/cli.md): helper commands to manage your setup
- [Development](docs/development.md): changing the repo: adding a service, changing the scripts, how the network works, and how Install and updates work

## License

GPL-3.0-or-later: see [LICENSE](LICENSE).
