# Roadmap

Tentative, in priority order. Nothing here is committed or scheduled — it's a wishlist, not a plan
with dates. See [CHANGELOG.md](CHANGELOG.md) for what already shipped (including auto-paste, see
MVP5 there) and [DECISIONS.md](DECISIONS.md) for the reasoning behind the current architecture
these build on top of.

1. **Live transcription** — show a partial transcript while still recording, instead of waiting for
   "Detener".
2. **Transcript history** — a lightweight real history of past transcriptions; today only the last
   one is persisted, plus a single-slot undo buffer (see [DECISIONS.md](DECISIONS.md)).
3. **Configurable shortcut / fallback shortcut** — a way to change the Fn modifier, or fall
   back to a different one (e.g. Control), for keyboards/setups where it turns out not to be
   reliable, or where using Fn conflicts with macOS's own "Press 🌐 Fn key to:" system action
   (see [DECISIONS.md](DECISIONS.md)) in a way the user can't or doesn't want to resolve by
   changing that system setting.
   `HotkeyModifierTrigger` (see [DECISIONS.md](DECISIONS.md)) already makes the modifier an
   injectable value internally; this item is about exposing that as an actual user-facing setting.
4. **Model/language selector** — choose between Whisper variants depending on the speed/accuracy
   trade-off each user prefers, and/or a language other than Spanish.
5. **Distribution cleanup** — notarization, DMG/installer, and whatever else App Store or
   direct-download distribution ends up requiring (the app icon itself already shipped).
