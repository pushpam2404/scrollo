# Troubleshooting

## Nothing happens when I scroll

1. **Is it on?** Open the menu bar panel. The master switch must be on and **Volume** above zero.
2. **Accessibility.** *System Settings → Privacy & Security → Accessibility* must list **Scrollo** switched on. If you build Scrollo yourself with an ad-hoc signature, macOS forgets the grant on every rebuild: remove Scrollo from the list with **−**, add it again, and see [DEVELOPMENT.md](DEVELOPMENT.md#keeping-the-accessibility-grant-across-rebuilds) for a permanent fix.
3. **Which app?** Scrollo is silent in apps that do not report their scroll position (browsers and web-based apps). Try Preview or Finder. To click everywhere, turn on *Settings → Behavior → Also click in apps that don't report scrolling*.
4. **Output.** Make sure your Mac's output volume is up and not muted. Scrollo plays through the system output device, so if your headphones disconnected, check the new default.
5. **Menu bar icon missing.** It may be hidden behind the notch when the menu bar is crowded. Quit a few menu bar apps, or use a menu bar manager.

## It clicks at the top or bottom of a page

- It clicks for up to about a quarter second the first time it meets an edge in an app, then remembers.
- Make sure **Only click when the content moves** is on (*Settings → Behavior*).
- The app may not report its scroll position, so it cannot be judged. Please [report it](https://github.com/pushpam2404/scrollo/issues/new/choose) with the app's name.

## macOS says Scrollo cannot be opened

Releases are not notarized. Use **System Settings → Privacy & Security → Open Anyway**, or:

```sh
xattr -dr com.apple.quarantine /Applications/Scrollo.app
```

## The haptic strengths feel the same

Haptics need a Force Touch trackpad and use five fixed actuator patterns, so differences are subtle on some models. Use **Settings → Haptics → Feel all levels** to compare. They only fire if the trackpad is the device macOS routes haptics to.

## The full-screen toolbar or menu bar will not hide

That is not Scrollo. In Chromium browsers check **View → Always Show Toolbar in Full Screen**, and check for other menu bar utilities that draw over the top of the screen.

## Collecting diagnostics

Scrollo writes decisions to `~/Library/Logs/Scrollo.log`, for example:

```
probe com.apple.Preview scrollbar -> silent (at edge pos=0.0000)
probe learned polarity com.apple.Preview|t = 1
```

Attach the last few lines (with anything private removed) to a bug report. Delete the file any time; it is capped at about 300 KB.
