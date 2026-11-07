# GameLens

**Real-time dialogue translator overlay for macOS games — built for people learning English by playing.**

Point it at the dialogue box in your game. When a new line appears, the Chinese translation
floats just below it. Press a hotkey and the translation **vanishes instantly** — read the
English yourself first, peek only when you're stuck.

[中文说明](README.md)

![overlay](overlay-preview.png)

## Why this exists

Most screen translators on macOS are "screenshot → popup". They don't do the one thing a
language learner actually needs: **stay out of the way**. GameLens keeps the translation
computed and ready, but hidden, so revealing it costs zero milliseconds.

## Features

- **Click-through overlay** — never steals focus from the game, never blocks mouse input
- **Global hotkey** (`⌥T` by default) to hide / show instantly; translations are pre-computed
- **Timed peek mode** — show for N seconds, then auto-hide
- **Bilingual or translation-only** — optionally show the recognized English line above the Chinese
- **4 translation engines** — Apple on-device (offline), Google, DeepL, or any OpenAI-compatible API
- **AI gloss** — with an LLM engine, append a one-line note on idioms / phrasal verbs
- **Markdown history** — every line is logged to `~/Documents/GameLens/对话记录.md` for review
- Zero third-party dependencies, ~2,300 lines of Swift, native AppKit

## Requirements

- macOS 14.0+ (Apple on-device translation needs macOS 26.0+)
- Xcode Command Line Tools: `xcode-select --install`
- **Screen Recording permission** (required to read the game's pixels)

## Build

```bash
git clone https://github.com/<you>/GameLens.git
cd GameLens
./build.sh          # → dist/GameLens.app
```

Then drag `dist/GameLens.app` into `/Applications`, launch it, and grant Screen Recording
permission when asked. Grant it **after** moving the app — the permission is tied to the app's
identity, and moving it later will revoke it.

Or one-shot:

```bash
./install.sh        # build + copy to /Applications + launch
```

## Usage

1. Run the game in **windowed or borderless** mode (exclusive fullscreen covers system overlays).
2. Menu bar 💬 → **框选识别区域…** → drag a box around the dialogue text only.
3. New lines get translated automatically and appear under the dialogue box.
4. Press `⌥T` to hide / show.

### Learning modes

| Mode | Setting | Effect |
| --- | --- | --- |
| Assisted reading | always visible | full bilingual subtitles |
| **Read first, then peek** | press `⌥T` manually | hidden by default, reveal on demand |
| **Timed peek** | `auto-hide` = 5s in Settings | reveal for 5 seconds, then it disappears |

## Translation engines

Menu bar → Settings → Engine.

| Engine | Network | Notes |
| --- | --- | --- |
| Auto | depends | Apple on-device first, falls back to Google |
| Apple (offline) | no | needs the language pack downloaded once |
| Google | yes | no API key; may be blocked in some regions |
| DeepL | yes | needs an API key |
| Custom API | yes | any OpenAI-compatible endpoint (DeepSeek, Kimi, OpenRouter, local Ollama) |

To install the offline language pack, open Apple's built-in **Translate** app and translate
one English sentence to Chinese. The pack is shared system-wide.

With a custom LLM endpoint, enable **AI gloss** to get a short note about slang or grammar
under the translation.

## Known limitations

- **Exclusive fullscreen games will cover the overlay.** Use windowed / borderless mode.
- Text only — **no speech recognition**. The game needs subtitle text on screen.
- Vertical text, stylized fonts, and fast-scrolling subtitles reduce OCR accuracy.
- Select a small region. A huge region slows OCR down.

## Privacy

Screenshots are captured in memory and never written to disk. Only recognized **text** is sent
to the translation service you choose (and only if you choose an online engine). History is
written locally to `~/Documents/GameLens/`.

## How it works

- Capture: `ScreenCaptureKit` `SCScreenshotManager`, restricted to the selected rect
- OCR: `Vision` `VNRecognizeTextRequest` (accurate)
- Translate: `Translation` framework / Google / DeepL / any OpenAI-compatible API
- Overlay: `NSPanel` at `CGWindowLevelForKey(.screenSaverWindow)`, click-through,
  `canJoinAllSpaces` + `fullScreenAuxiliary`
- Hotkey: Carbon `RegisterEventHotKey` (no Accessibility permission needed)
- Debouncing: a line counts as "new" only after two identical OCR passes, which avoids
  typewriter effects and fade-in flicker

## License

MIT — see [LICENSE](LICENSE).
