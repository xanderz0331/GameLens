# GameLens

**A "peek on demand" translation overlay for learning English from games, TV shows and videos.**

Box a small area of your screen. When new text appears, the Chinese translation floats right below it.
Press a hotkey and the translation **vanishes instantly** — read the English yourself first, peek only when stuck.

[中文说明](README.md)

![overlay](overlay-preview.png)

## Use it for

| | |
| --- | --- |
| 🎮 **English-only games** | dialogue, subtitles, item descriptions |
| 🎬 **TV shows / movies** | raw or English-subbed, translation under the subtitle line |
| 🎥 **Videos & lectures** | YouTube, documentaries, interviews — look up a line on demand |

> It reads **on-screen text only** — no speech recognition. The content needs subtitles or text.

## Why it's different

Most screen translators are "press → popup → close", which breaks your flow. Subtitle plugins
translate everything permanently, so you never practice.

GameLens keeps the translation **computed but hidden**. Revealing it costs zero milliseconds,
so you can genuinely try to read first and cheat second.

## Requirements

- macOS 14.0+ (Apple on-device translation needs macOS 26.0+)
- Xcode Command Line Tools: `xcode-select --install`
- Screen Recording permission

## Build & install

```bash
git clone https://github.com/xanderz0331/GameLens.git
cd GameLens
./install.sh          # build + copy to /Applications + launch
```

or just `./build.sh` → `dist/GameLens.app`, then drag it into `/Applications` and grant
Screen Recording **after** moving it (the permission is tied to the app's identity).

## Usage

1. Launch it — a 💬 icon appears in the menu bar (no Dock icon, it's a menu bar app).
2. Grant Screen Recording → System Settings › Privacy & Security › Screen Recording → enable GameLens.
3. 💬 → **框选识别区域…** → drag a box around the text area only.
4. New text gets translated automatically.

Press `⌥T` to hide / show the translation.

### Learning modes

| Mode | Setting | Effect |
| --- | --- | --- |
| Assisted | always visible | full bilingual subtitles |
| **Read first, peek later** | press `⌥T` | hidden by default, reveal on demand |
| **Timed peek** | auto-hide = 5s | reveal for 5 seconds, then disappears |

## Pausing and quitting

It's a menu bar app — there is no Dock icon. Everything lives in the 💬 menu.

| Goal | How | Result |
| --- | --- | --- |
| Pause for a while | 💬 → **暂停识别（停止抓屏）** | capture and OCR stop completely, overlay hides, icon becomes ⏸ |
| Done for today | 💬 → **退出 GameLens（彻底关闭）** | process exits, menu bar icon disappears |
| App stuck / icon gone | `⌘⌥Esc` → Activity Monitor → `GameLens` → ⨯ | force quit |

- It **does not start at login** — no LaunchAgent, no login item, no background agent.
- Quitting uses zero CPU and memory, and captures nothing.
- Quitting does **not** revoke the Screen Recording permission; you won't be asked again.
- To remove everything: `rm -rf ~/Documents/GameLens && defaults delete com.local.gamelens`.

## Translation engines

| Engine | Network | Notes |
| --- | --- | --- |
| Auto | depends | Apple on-device first, falls back to Google |
| Apple (offline) | ❌ | download the language pack once via the built-in Translate app |
| Google | ✅ | no key needed |
| DeepL | ✅ | API key required |
| Custom API | ✅ | any OpenAI-compatible endpoint (DeepSeek, Kimi, OpenRouter, local Ollama) |

With a custom LLM endpoint, enable **AI gloss** to get a one-line note about slang or grammar.

## Known limitations

- **Exclusive fullscreen games cover the overlay.** Use windowed / borderless mode.
- **DRM-protected streaming (Netflix, Apple TV+, Disney+) captures as black** — a macOS-level
  restriction that affects every screen recorder. Bilibili, YouTube and local files are fine.
- Text only, no speech recognition.
- Vertical text, stylized fonts and fast-scrolling subtitles reduce OCR accuracy.

## Privacy

Screenshots stay in memory and are never written to disk. Only recognized **text** is sent to
the translation service you choose, and only for online engines. History is written locally.

## License

MIT — see [LICENSE](LICENSE).
