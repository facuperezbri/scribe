# Roadmap

Tentative, in priority order. Nothing here is committed or scheduled — it's a wishlist, not a plan
with dates. See [CHANGELOG.md](CHANGELOG.md) for what already shipped (including auto-paste, see
MVP5 there) and [DECISIONS.md](DECISIONS.md) for the reasoning behind the current architecture
these build on top of.

1. **Live transcription** — show a partial transcript while still recording, instead of waiting for
   "Detener".
2. **Transcript history** — a lightweight real history of past transcriptions; today only the last
   one is persisted, plus a single-slot undo buffer (see [DECISIONS.md](DECISIONS.md)).
3. **Configurable shortcut / fallback shortcut** — a way to change the Fn + Espacio combo, or fall
   back to a different one, for keyboards/setups where it turns out not to be reliable.
   `HotkeyTrigger` (see [DECISIONS.md](DECISIONS.md)) already makes the combo an injectable value
   internally; this item is about exposing that as an actual user-facing setting.
4. **Hold-to-talk mode** — record while a key is held down instead of toggling with two presses, as
   an alternative to the current always-toggle behavior.
5. **Model/language selector** — choose between Whisper variants depending on the speed/accuracy
   trade-off each user prefers, and/or a language other than Spanish.
6. **Distribution cleanup** — notarization, DMG/installer, and whatever else App Store or
   direct-download distribution ends up requiring (the app icon itself already shipped).
