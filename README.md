# Speedify Browser

A small Docker-based experiment for running selected desktop
applications through Speedify without routing the rest of the host
through the VPN.

The current implementation supports Firefox. The next intended step is
to add qBittorrent while keeping the same basic design: only
applications deliberately launched inside the container should use
Speedify.

This README is deliberately fairly detailed. It records the decisions
and problems encountered during the experiment so that the project can
be picked up later --- by a person or an LLM --- without having to
rediscover the important parts.

## Current state

The Firefox workflow is working end-to-end:

1.  Launch **VPN Browser** from the XFCE application menu.
2.  The host launcher checks whether Docker is already running.
3.  If necessary, it starts Docker.
4.  Docker starts the Speedify container.
5.  The Speedify daemon starts and restores the existing login.
6.  The Speedify GUI appears.
7.  The entrypoint requests a VPN connection and waits until it has
    remained connected for 10 seconds.
8.  Firefox starts and uses the Speedify connection.
9.  Closing the Speedify GUI does not control the VPN or container.
10. Closing Firefox ends the entrypoint and shuts down
    Speedify/container.
11. If the launcher originally started Docker, it stops both
    `docker.service` and `docker.socket`.
12. If Docker was already running before the launcher was invoked, it is
    left running.

This behaviour has been tested in both Docker lifecycle cases.

## Host environment

The experiment was developed on CachyOS with XFCE and X11.

The current project directory is:

``` text
~/speedify-browser
```

Docker is intentionally not required to run continuously. The launcher
starts and stops it as necessary.

The host is configured so that `sudo` does **not** prompt for a
password. The launcher therefore uses `sudo systemctl ...` directly even
though it is normally started from a `.desktop` entry with
`Terminal=false`.

Do not add password-prompt handling merely because the launcher contains
`sudo`: passwordless `sudo` is an intentional assumption of this
particular installation.

## Repository and persistent data

The source is stored in a private GitHub repository.

Persistent application data lives below:

``` text
data/
```

and the whole directory is excluded by `.gitignore`.

In particular, **never commit the Speedify key material or
authentication state**.

The important persistent directories are conceptually:

``` text
data/
├── firefox/
└── speedify/
    ├── keys/
    └── logs/
```

Firefox's profile is persisted so bookmarks, extensions and settings
survive container recreation.

Speedify requires both its data and encryption keys to survive
recreation.

## Speedify authentication discovery

Initially only this directory was persisted:

``` text
/usr/share/speedify/logs
```

That was insufficient. A freshly created container reported:

``` text
LOGGED_OUT
```

even when `logs/` had been copied from a successfully authenticated
session.

Inspecting Speedify's help revealed:

``` text
-k <keyctl path>
Path to a directory for storing keyctl-encrypted RSA keys and seed files
used for encrypting settings and auth tokens (default: .keys)
```

Speedify is started by its supplied startup script as:

``` bash
./speedify -d logs -k .keys &
```

The `.keys` directory contains files including:

``` text
rsa_key.seed
rsa_key.der
```

The solution was therefore to persist **both**:

``` text
/usr/share/speedify/logs
/usr/share/speedify/.keys
```

The Compose configuration mounts them approximately as:

``` yaml
- ./data/speedify/logs:/usr/share/speedify/logs
- ./data/speedify/keys:/usr/share/speedify/.keys
```

After logging in once with both mounts present, a completely new
container was started and `speedify_cli state` returned:

``` json
{
    "state": "LOGGED_IN"
}
```

This was the conclusive authentication-persistence test.

The keys and logs form a pair. An old copy of `logs/` without the
corresponding keys should not be considered a usable authenticated
backup.

## Speedify networking

The container needs access to TUN and network administration:

``` yaml
devices:
  - /dev/net/tun:/dev/net/tun

cap_add:
  - NET_ADMIN
```

A major stability problem was traced to reverse-path filtering.

Speedify's own `SpeedifyStartup.sh` runs `DisableRpFilter.sh`, but
`/proc/sys` is read-only from inside the container and the script prints
errors when it tries to modify those values.

The important fix is to set the namespace values through Docker Compose:

``` yaml
sysctls:
  net.ipv4.conf.all.rp_filter: "0"
  net.ipv4.conf.default.rp_filter: "0"
```

Before this change Speedify could enter `CONNECTED` briefly and fall
back to `CONNECTING`, with the tunnel sending traffic but receiving
none. After adding these sysctls the VPN became quick and stable.

Do **not** remove these settings just because `SpeedifyStartup.sh` still
prints warnings about its own attempts to modify `/proc/sys`.

There is no need to use `privileged: true`.

## Speedify GUI

The supported GUI launcher is:

``` text
/usr/share/speedifyui/speedify_ui
```

Do not directly use `speedify_ui_webkit60` as the normal launcher.

The GUI uses WebKit and required:

``` yaml
security_opt:
  - seccomp=unconfined
```

Without this, WebKit failed while attempting to create namespaces.

The GUI also produced warnings about `/dev/dri/card1`, Radeon/DRI and
ALSA. These warnings proved non-fatal and should not be treated as the
cause of a missing GUI unless new evidence indicates otherwise.

A less obvious issue was that the GUI process could start successfully
but create no visible window when the container had no pseudo-TTY.
Process inspection showed both:

``` text
speedify_ui
speedify_ui_webkit60
```

alive, yet no window appeared.

Launching exactly the same wrapper from an interactive shell in the same
running container produced the window.

The working Compose configuration therefore includes:

``` yaml
stdin_open: true
tty: true
```

and the entrypoint launches the UI simply as:

``` bash
"$SPEEDIFY_UI" &
```

Do not restore the earlier redirection to `/dev/null` and
`/tmp/speedify-ui.log` without a specific reason. Providing the
pseudo-TTY and launching the wrapper normally was the change that made
automatic GUI startup work.

## X11

The host X socket is mounted:

``` yaml
- /tmp/.X11-unix:/tmp/.X11-unix:rw
```

and `DISPLAY` is passed through:

``` yaml
environment:
  DISPLAY: ${DISPLAY}
```

The current host launcher permits the container's root user to access X:

``` bash
xhost +SI:localuser:root >/dev/null
```

This is intentionally pragmatic rather than an attempt at a hardened
desktop-container design.

A future improvement could run Firefox/qBittorrent as a user matching
the host UID/GID and tighten X11 access. That is not required for the
qBittorrent feature and should not be mixed into that work unless
desired.

## Entrypoint lifecycle

The current entrypoint starts the Speedify daemon, launches the GUI,
requests a connection and waits for a stable VPN before starting
Firefox.

The important structure is:

``` bash
SPEEDIFY=/usr/share/speedify
SPEEDIFY_UI=/usr/share/speedifyui/speedify_ui
```

Speedify is started using its supplied script:

``` bash
./SpeedifyStartup.sh
```

The GUI is backgrounded:

``` bash
"$SPEEDIFY_UI" &
```

The entrypoint then runs:

``` bash
./speedify_cli connect
```

and polls `speedify_cli state`.

A `CONNECTED` result is not immediately accepted. The script waits
another 10 seconds and verifies that the state is still `CONNECTED`.
Firefox is only started after that stability check passes.

Firefox deliberately remains in the foreground:

``` bash
firefox-esr
```

Its lifetime therefore controls the lifetime of the container.

The entrypoint has a cleanup trap which shuts down the Speedify
GUI/processes and calls `SpeedifyShutdown.sh`.

This means the Speedify GUI itself is not the lifecycle owner. It can be
closed without terminating the VPN. Firefox is currently the lifecycle
owner.

## Host launcher

The host-side `vpn-browser` script owns the Docker lifecycle.

The required behaviour is:

``` text
Docker already running?
    yes -> leave Docker running when finished
    no  -> start Docker and stop it when finished
```

The current logic records whether `docker.service` was active before
launch.

If Docker was not running:

``` bash
sudo systemctl start docker.service
```

The launcher waits until:

``` bash
docker info
```

succeeds, grants X access, changes to the project directory and runs:

``` bash
docker compose up --abort-on-container-exit
```

During cleanup it always performs:

``` bash
docker compose down
```

If Docker was not running before the launcher started, cleanup performs:

``` bash
sudo systemctl stop docker.service docker.socket
```

Stopping **both** units is important. Stopping only `docker.service`
leaves `docker.socket` active and allows socket activation to start
Docker again.

This has been tested with Docker initially inactive and initially
active.

## XFCE application shortcut

There is currently a manually created user desktop entry at:

``` text
~/.local/share/applications/vpn-browser.desktop
```

It is approximately:

``` ini
[Desktop Entry]
Name=VPN Browser
Comment=Browse using Speedify VPN
Exec=/home/scandal/speedify-browser/vpn-browser
Icon=web-browser
Terminal=false
Type=Application
Categories=System;Network;
StartupNotify=true
```

A useful discovery: do **not** put this in `Exec=`:

``` ini
Exec=$HOME/speedify-browser/vpn-browser
```

Desktop entries do not perform shell expansion of `$HOME`. That caused
GLib/XFCE not to recognise the application correctly.

### Planned installer

The `.desktop` entry is not currently part of the repository.

A planned improvement is an `install.sh` script which creates the
application-menu shortcut automatically. It should determine the user's
home/project path at installation time and write an absolute `Exec=`
path.

The installer may also perform other harmless setup/validation, but
persistent Speedify credentials and application data must remain outside
Git.

## Firefox storage

The Firefox profile is host-mounted so it survives rebuilds.

The host's Downloads directory is also mounted into the container,
allowing files downloaded in the VPN browser to appear directly in the
normal host download location.

The current prototype runs Firefox as root inside the container. This
can result in host-mounted files being root-owned. Moving desktop
applications to a host-UID/GID user is a possible future improvement,
but it has deliberately not been allowed to destabilise the now-working
VPN setup.

Firefox ESR comes from Debian. Updating the image/rebuilding the
container is the intended way to obtain package updates rather than
modifying the running container.

## Next feature: qBittorrent

The next intended feature is qBittorrent support.

Only two applications are expected to need Speedify:

-   Firefox
-   qBittorrent

Do not generalise the project into an arbitrary VPN application
framework unless requirements change.

The intended conceptual architecture is:

``` text
Docker / Speedify network namespace
├── Firefox
└── qBittorrent
```

Normal host traffic must continue to bypass Speedify.

A sensible eventual user-facing model is likely to provide separate
launch modes:

``` text
VPN Browser
    Speedify + Firefox
    lifetime controlled by Firefox

VPN Torrent
    Speedify + qBittorrent
    lifetime controlled by qBittorrent
```

A combined mode could be considered later if useful, in which case the
container would remain alive until both applications have exited.

The current Firefox workflow should remain a known-good baseline while
qBittorrent is introduced.

### qBittorrent safety consideration

qBittorrent should ideally be explicitly bound to Speedify's tunnel
interface:

``` text
connectify0
```

rather than merely relying on the container's default route.

That gives an additional fail-closed property: if the Speedify tunnel
disappears, qBittorrent should not silently fall back to the container's
ordinary `eth0` path.

This matters more for a long-running torrent client than for the
browser.

Before implementing this, verify qBittorrent's current network-interface
binding behaviour inside the container rather than assuming a particular
configuration key.

Its configuration and downloads should be persisted/mounted separately
from Firefox.

## Potential VPN-drop handling

The current entrypoint fails closed at **startup**: Firefox is not
launched until Speedify is stably `CONNECTED`.

It does not yet provide a fully proven runtime kill switch if Speedify
disconnects after Firefox has started.

For qBittorrent this deserves explicit attention. Possible approaches
include:

-   binding qBittorrent to `connectify0`;
-   using a Speedify-supported Internet Kill Switch if appropriate;
-   monitoring Speedify state and terminating the protected application
    if the VPN drops.

Avoid complicated firewall rules unless needed; Speedify server
endpoints are dynamic and the working setup should not be destabilised
unnecessarily.

## Things already proven --- avoid rediscovering them

When continuing this project, treat the following as established unless
later evidence contradicts them:

1.  `/dev/net/tun` plus `NET_ADMIN` is sufficient; `privileged: true` is
    not required.
2.  The `rp_filter` Compose sysctls are important for a stable Speedify
    tunnel.
3.  Speedify authentication requires persistent `logs/` **and** matching
    `.keys/`.
4.  `/usr/share/speedifyui/speedify_ui` is the correct GUI wrapper.
5.  `seccomp=unconfined` is currently required for the WebKit GUI.
6.  `stdin_open: true` and `tty: true`, combined with launching
    `"$SPEEDIFY_UI" &`, made the GUI appear automatically.
7.  EGL/DRI and ALSA warnings occur even when the GUI works.
8.  Closing the Speedify GUI does not need to stop the VPN.
9.  Firefox can deliberately control the current container lifetime by
    remaining in the foreground.
10. Docker must only be stopped by the host launcher if it was not
    running before launch.
11. When shutting Docker down, stop both `docker.service` and
    `docker.socket`.
12. The XFCE `.desktop` `Exec=` field requires an actual executable
    path; `$HOME` is not expanded there.
13. Passwordless `sudo` is an intentional assumption on the current
    host.

## Suggested next steps

When development resumes:

1.  Commit/preserve the currently working Firefox baseline before
    changing it.
2.  Add qBittorrent to the image.
3.  Decide on a small entrypoint argument/mode mechanism rather than
    duplicating all Speedify startup logic.
4.  Persist qBittorrent configuration and mount the desired download
    location.
5.  Bind qBittorrent to `connectify0` if testing confirms that provides
    the desired fail-closed behaviour.
6.  Give qBittorrent its own host launcher/lifecycle.
7.  Add an `install.sh` which creates the XFCE application shortcuts
    using absolute paths.
8.  Only after both modes work reliably, consider refactoring shared
    launcher logic or changing applications from root to a host-UID
    user.

The priority is to preserve the working Firefox path while adding the
torrent-client path incrementally.
