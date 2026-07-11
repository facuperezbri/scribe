# Roadmap

Tentative, in priority order. Nothing here is committed or scheduled — it's a wishlist, not a plan
with dates. See [CHANGELOG.md](CHANGELOG.md) for what already shipped and [DECISIONS.md](DECISIONS.md)
for the reasoning behind the current architecture these build on top of.

1. **Auto-paste** — paste the transcription result directly into whichever app was focused before
   the shortcut was pressed, instead of requiring a manual "Copiar" + ⌘V. The global Fn + Espacio
   shortcut, its permission UX, and window activation are already in place as building blocks. See
   [MVP5_AUTO_PASTE_PLAN.md](MVP5_AUTO_PASTE_PLAN.md) for the readiness/design notes.
2. **Live transcription** — show a partial transcript while still recording, instead of waiting for
   "Detener".
3. **Transcript history** — a real history of past transcriptions; today only the last one is
   persisted, plus a single-slot undo buffer (see [DECISIONS.md](DECISIONS.md)).
4. **Model selector** — choose between Whisper variants depending on the speed/accuracy trade-off
   each user prefers.
5. **Distribution cleanup** — notarization, DMG/installer, and whatever else App Store or
   direct-download distribution ends up requiring (the app icon itself already shipped).

Note: earlier drafts of this roadmap used "MVP3"/"MVP5"/"MVP6"/"MVP7" labels for these same items.
Those numbers are dropped here because they'd already collided with the MVP3/MVP4 names used for
work that has since shipped (see [CHANGELOG.md](CHANGELOG.md)) — plain descriptive names don't have
that problem.
