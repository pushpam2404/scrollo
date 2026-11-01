# Contributing to Scrollo

Thanks for helping! Scrollo is a small native Mac app, so contributing is easy to get started with.

## Reporting a bug

Use the [bug report form](https://github.com/pushpam2404/scrollo/issues/new/choose). The most useful reports include:

- macOS version and Mac model, and whether you use natural scrolling
- the **app** where it misbehaves (this matters most: behavior depends on what the app reports)
- what you expected and what happened
- the last few lines of `~/Library/Logs/Scrollo.log`

## Suggesting a feature

Open a [feature request](https://github.com/pushpam2404/scrollo/issues/new/choose). Describe the problem first; ideas for the solution are welcome too.

## Setting up

```sh
git clone https://github.com/pushpam2404/scrollo.git && cd scrollo
./build.sh
```

You need only the Xcode Command Line Tools. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for signing (so the Accessibility grant survives rebuilds), the diagnostics tool and the layout of the code.

## Pull requests

1. Fork, then create a branch from `main` (`fix/edge-in-pages`, `feat/new-sound`).
2. Keep the change focused; one topic per pull request.
3. Follow the surrounding style. Comments say *why*. No new third-party dependencies.
4. Make sure it builds (`./build.sh --no-install`) and that you tried it. For scroll-detection changes, run the diagnostics tool against a real app and include the results.
5. Update `CHANGELOG.md` under **Unreleased**.
6. Open the pull request using the template.

## Adding a sound

Sounds must be **CC0 or otherwise freely redistributable**. Add a short (under 0.4 s) WAV to `Resources/Sounds/`, register it in `Sources/SoundBank.swift`, and credit the author and source in `Resources/Sounds/CREDITS.txt`.

## Code of conduct

Be kind and constructive. Assume good intent. Harassment of any kind is not tolerated.
