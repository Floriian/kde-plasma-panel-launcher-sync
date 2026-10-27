# KDE Plasma Panel Launcher Sync

Keeps the pinned applications of the task manager in sync across all panels in KDE Plasma, which is useful when you run a cloned panel on each monitor.

Plasma can clone a panel (since 6.3), but the clone is an independent copy: pinning or unpinning an app on one panel does not affect the others. This tool watches the Plasma panel configuration and, whenever the pinned apps change on any panel, copies that list to every other task manager widget.

## Files

| File | Purpose |
|------|---------|
| `panel-launcher-sync.sh` | Performs one sync: finds the panel whose launcher list changed and copies it to all others. |
| `panel-launcher-watch.sh` | Watches the Plasma config file and runs the sync script on every change. |
| `panel-launcher-sync.service` | systemd user service that starts the watcher automatically on login. |

## Requirements

- KDE Plasma 6 (Plasma 5 should also work if `qdbus` is available)
- `qdbus6` or `qdbus` (shipped with Qt tools; usually already installed on Plasma systems)
- `inotify-tools`
- systemd (for the automatic start)

Install `inotify-tools` with your distribution's package manager:

```bash
sudo pacman -S inotify-tools      # Arch / Manjaro / EndeavourOS
sudo apt install inotify-tools    # Debian / Ubuntu / Kubuntu
sudo dnf install inotify-tools    # Fedora
sudo zypper install inotify-tools # openSUSE
```

## Installation

1. Copy the scripts and the service file into place:

   ```bash
   mkdir -p ~/.local/bin ~/.config/systemd/user
   cp panel-launcher-sync.sh panel-launcher-watch.sh ~/.local/bin/
   chmod +x ~/.local/bin/panel-launcher-*.sh
   cp panel-launcher-sync.service ~/.config/systemd/user/
   ```

2. Before the first run, make sure the panel on your **primary screen (screen 0)** has the pinned apps you want. On the first run it is used as the source and its list overwrites all other panels.

3. Enable and start the service:

   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now panel-launcher-sync.service
   ```

## Updating an existing installation

If you already installed an earlier version, copy the new script over the old one and restart the service:

```bash
cp panel-launcher-sync.sh panel-launcher-watch.sh ~/.local/bin/
chmod +x ~/.local/bin/panel-launcher-*.sh
systemctl --user restart panel-launcher-sync.service
```

The service runs one sync about 5 seconds after starting. If no state file exists yet (`~/.local/state/panel-launcher-sync/last`), this first sync uses the panel on screen 0 as the source.

## Verifying it works

Check the service status:

```bash
systemctl --user status panel-launcher-sync.service
```

Then pin or unpin an app on any panel and follow the log:

```bash
journalctl --user -u panel-launcher-sync -f
```

The other panels should update within a few seconds.

You can also run a single sync manually at any time:

```bash
~/.local/bin/panel-launcher-sync.sh
```

## Configuration

By default the tool syncs the **Icons-only Task Manager** (`org.kde.plasma.icontasks`). If you use the regular **Task Manager**, set the widget ID in the service file by adding this line to the `[Service]` section:

```ini
Environment=PANEL_SYNC_WIDGET=org.kde.plasma.taskmanager
```

Then reload and restart:

```bash
systemctl --user daemon-reload
systemctl --user restart panel-launcher-sync.service
```

## How it works

Plasma stores all panel and widget settings in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`. The watcher uses `inotifywait` to detect writes to that file, waits until there has been no new event for 2 seconds (debounce), then runs the sync script.

The sync script reads every task manager's launcher list through Plasma's scripting API (`org.kde.PlasmaShell.evaluateScript` over D-Bus). It remembers the last synced list in `~/.local/state/panel-launcher-sync/last`, picks the panel whose list differs from it as the source, and writes that list to every widget that does not already match. Because matching widgets are left untouched, the config write caused by the sync itself does not start an endless loop.

Reordering needs special handling: the task manager does not rearrange existing icons when only the order of its launcher list changes. When the script detects a pure reorder, it first writes the list without the moved icons, waits one second, then writes the full list, so the task manager re-inserts the moved icons at their new positions.

## Limitations

- **Short delay.** Plasma writes its configuration to disk a few seconds after a change, so the other panels update with a small delay, not instantly.
- **Brief flicker when reordering.** When you move an icon, the moved icons disappear from the other panels for about a second before reappearing in their new position.
- **Only pinned apps are synced.** Other widgets, panel layout and task manager settings are not synced. For those, re-clone the panel after making changes.
- **Simultaneous edits.** If you change pinned apps on two different panels within the same few seconds, the first one found wins.

## Troubleshooting

- **Pinned apps don't appear on the other panel**: work through the checks below in order.

  1. Check that the service is running:

     ```bash
     systemctl --user status panel-launcher-sync.service
     ```

  2. Check that Plasma writes the config file when you pin an app. Stop the service, run the command below, then pin something:

     ```bash
     systemctl --user stop panel-launcher-sync.service
     inotifywait -m -e close_write,moved_to ~/.config | grep appletsrc
     ```

     You should see a `MOVED_TO plasma-org.kde.plasma.desktop-appletsrc` line within a few seconds. Start the service again afterwards.

  3. List every panel, widget and launcher list as Plasma sees them:

     ```bash
     qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
     panels().forEach(function(p) {
       print("panel " + p.id + " screen " + p.screen + "\n");
       p.widgets().forEach(function(w) {
         w.currentConfigGroup = ["General"];
         print("  " + w.type + " -> " + String(w.readConfig("launchers", [])) + "\n");
       });
     });'
     ```

     Every panel should contain the same task manager widget type (see [Configuration](#configuration)).

  4. Run a single sync with tracing to see where it stops:

     ```bash
     bash -x ~/.local/bin/panel-launcher-sync.sh
     ```

     If you see `'[' 1 -ge 2 ']'` followed by `exit 0` even though you have several panels, the panel lists were not split correctly; make sure you are running the latest version of the script.

- **A panel reports `screen -1`**: some Plasma versions report `-1` for panels on secondary screens. This does not affect syncing, because the source is chosen by which list changed, not by screen number. It only matters on the very first run, when the screen 0 panel is used as the source.
- **`qdbus/qdbus6 not found`**: install your distribution's Qt tools package (for example `qt6-tools` on Arch or `qdbus-qt6` on Debian/Ubuntu).
- **Panels don't visibly update**: restart Plasma with `systemctl --user restart plasma-plasmashell`.
- **Service fails at login**: Plasma may not have been ready yet. The service restarts automatically after 5 seconds; check `journalctl --user -u panel-launcher-sync` for details.
- **Wrong list was used as the source**: stop the service, delete `~/.local/state/panel-launcher-sync/last`, fix the panel on screen 0, then start the service again.

## Uninstallation

```bash
systemctl --user disable --now panel-launcher-sync.service
rm ~/.config/systemd/user/panel-launcher-sync.service
rm ~/.local/bin/panel-launcher-sync.sh ~/.local/bin/panel-launcher-watch.sh
rm -r ~/.local/state/panel-launcher-sync
systemctl --user daemon-reload
```
