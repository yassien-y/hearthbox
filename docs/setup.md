# Setup

Follow these steps in order. You type the commands in a terminal: open one (often
Ctrl+Alt+T, or search for "Terminal"), paste or type a command, and press Enter.

## What you need

- **A computer running a recent Linux** that will be your server, and that you can
  install software on: Ubuntu 26.04 or newer, Debian 13 or newer, a current Fedora,
  openSUSE Tumbleweed or Arch. Older versions, like Ubuntu 24.04, aren't supported (for now).
- **No VPN running on that computer** (NordVPN, Proton VPN and the like). A VPN sends
  the computer's traffic and name lookups through itself, which breaks the setup.
- **Access to your router's settings page.** Some internet providers' routers lock it.
  Every router's settings page looks different. You need to know how to:
  - Reserve a fixed address for a device (DHCP reservation)
  - Set the DNS server the router hands out to devices
  - Forward ports to a device (IPv4), or allow ports in with a firewall rule (IPv6)

## Modes

Install offers two modes:

| | Local mode | Internet mode |
|---|---|---|
| Reachable from | Devices on your home network | Anywhere |
| Install on your devices | Nothing installed | Zero trust VPN app (Tailscale or NetBird) |
| Cost | Free | The public domain's yearly fee |

To change modes, an [uninstall](#uninstall) is required.

## Important terms

- **Root and `sudo`:** root is the computer's administrator account: it can change
  anything on it. `sudo` runs one command as root.
- **Hearthbox user:** the account used to run everything, referred to as
  `<hearthbox-user>`. For security, every [service](services.md) runs as this user instead of root. The
  services and their files belong to this user. To manage them, log in to the account with
  `sudo -iu <hearthbox-user>`. It has no password: only someone who can use `sudo` can
  switch to it.
- **Public domain:** a domain you own, like `example.com`, referred to as `<public-domain>`.
  Optional for local setups, required on internet setups.
- **Internal domain:** the domain you open your services at, referred to as
  `<internal-domain>`. Unlike a public domain, it isn't reachable from the internet, only
  from your own devices, so you don't need to own it. It can't be the same as your public
  domain. Examples:
  - `hearthbox.com`: the dashboard is at `https://home.hearthbox.com`.
  - `hearthbox`: the dashboard is at `https://home.hearthbox`.
- **Service group:** a group of apps that can be installed together.

---

## 1. Install the required packages

The required packages are Podman, git, nftables and curl. Install them with one of the
following commands:

```bash
sudo apt install podman git nftables curl            # Ubuntu, Debian
sudo dnf install podman git nftables curl            # Fedora
sudo zypper install podman git nftables curl         # openSUSE
sudo pacman -S --needed podman git nftables curl     # Arch
```

## 2. Run Install

Run this:

```bash
sudo bash -c "$(curl -fsSL <install-url>)"   # not available yet: the repo has no public URL
```

This downloads Install and runs it. Install downloads the rest of the setup itself,
and deletes anything temporary when it's done.

> **Note:** to share your setup and config with someone, or use it on another machine,
> make your own copy of the repo (a fork) first, and install from it. See
> [your own version of the setup](development.md#your-own-version-of-the-setup).

Install asks a few questions. Default values are shown in square brackets, `[like this]`:
press Enter to accept the default, or type in your own value.

If Install is interrupted for any reason, for example because your SSH connection dropped,
run the same command again: it continues with the answers you gave, and keeps what it
already set up.

### Local vs internet

The system can be installed in 2 modes, local and internet:

**Local mode:** nothing on your server is open to the internet. Devices don't need an app
to connect to your server. Pick this if you don't need to access your server outside of
your router's network.

**Internet mode:** your server can be accessed from anywhere with an internet connection.
A specific app must be used to access your server securely (see
[Tailscale (Headscale) vs NetBird](#tailscale-headscale-vs-netbird)). You also need a public domain. Pick this if
you need to access your server outside of your router's network, like on your phone over
mobile data.

### Tailscale (Headscale) vs NetBird

In internet mode, you can pick between two apps to connect to your server: Tailscale
(Headscale) and NetBird. Both offer a secure way to access your server. They differ in how people and
devices get access:

**[Tailscale](https://tailscale.com) ([Headscale](https://headscale.net)):** the simple
option. To add a device, you let it in by running a command on your server. Pick this for
yourself and a few people you trust.

**[NetBird](https://netbird.io):** each person gets their own login, with a password and an
authenticator code. You manage users, devices and access rules through the web dashboard.
Pick this if more people will use your server.

If you're not sure which to pick, pick Tailscale (Headscale).

## 3. Trust your server's certificate

The services use HTTPS, with a certificate your server makes itself. A device trusts it
once you install your server's root certificate on it. On each phone and computer, open
`http://ca.<internal-domain>/root.crt` (with `http://`, not `https://`), and:

- **iPhone, iPad:** allow the download, then in Settings, open "Profile Downloaded" and
  install it. Then turn it on in Settings > General > About > Certificate Trust
  Settings: without that, nothing trusts it.
- **Android:** in Settings, search for "CA certificate" and install the downloaded file
  as one. Chrome and Bitwarden trust it. Firefox only after you enable "Use third-party
  CA certificates" in its settings.
- **Windows:** open the file, Install Certificate, and pick "Trusted Root Certification
  Authorities".
- **macOS:** open the file, which adds it to Keychain Access, then set it to "Always
  Trust" there.
- **Linux:** each browser has its own list: add it in the browser's certificate
  settings, as an authority.

The certificate can only vouch for names under your internal domain, so trusting it lets
your server vouch for nothing else.

## 4. Open the dashboard

In a browser on any device on your network, open `https://home.<internal-domain>`.
Type the `https://` part: without it, the browser may search for the name instead.

The dashboard links to every service you picked.

If something doesn't open, see which services are running:

```bash
sudo -iu <hearthbox-user> hearthbox services list
```

---

## Uninstall

```bash
sudo -i                 # a root shell: Uninstall needs root
cd ~<hearthbox-user>/repo
./uninstall.sh
exit                    # leave the root shell, and the folder, which is now gone
```

It shows what it will remove and asks before doing anything. It deletes the
Hearthbox user and everything in its home, including the apps' data, and removes
the port redirects and, in internet mode, the VPN's client (NetBird's, or the Tailscale
client with its state in `/var/lib/tailscale`). Your media and downloads in
`/srv/hearthbox` are kept, and so are the packages the setup needed: Podman, git and
nftables (and curl, in internet mode). Remove them yourself if nothing else uses them.

Then undo your router settings: in local mode, set its DNS server back to automatic, or
devices on your network can't open websites.
In internet mode, close ports 443 and 3478 to the server, and delete the
`hs.<public-domain>` or `nbs.<public-domain>` DNS record. You can also remove your
server's root certificate from your devices.
