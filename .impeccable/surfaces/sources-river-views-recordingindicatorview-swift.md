---
version: 1
slug: "sources-river-views-recordingindicatorview-swift"
primary_target: "Sources/River/Views/RecordingIndicatorView.swift"
related_targets: ["Sources/River/Views/MenuBarPresentation.swift","Sources/River/Resources/Info.plist"]
---

# Surface: River identity — app icon, menu bar glyph set, recording indicator

Mode: Operate. Visitor: someone mid-thought in another app who pressed the key; the indicator must confirm "listening" in a glance and never take focus. Untouched this pass: menu bar dropdown, Settings layout, onboarding structure. Anti-goals: cute or mascot-like, generic AI aesthetic, heavy or decorative chrome. Presence: small but unmistakable.

## Direction contract

THESIS: Audio level wakes the mark. A fixed silhouette is always present at low ink, and speech brings its parts to full ink in stages, so the identity is legible in how the mark responds to the voice. Refuses the category default of a microphone symbol beside a bar meter.

OWN-WORLD: Charcoal #23262B / #2E3238 with ink #ECEEF1 and one accent, dark turquoise #1F7F86 or red sand #C4674A (choice open). Uniform ink on marks, no per-stroke accent. Rounded corners, concentric radii. Flat vector, no bevels. Two indicator candidates: a capsule microphone head measured from a reference photo (three groove groups), and a three-strand river with a separated rest state.

STORY: The user sees River is listening the instant they speak, watches the mark respond to their own voice, and forgets it when it fades.

FIRST VIEWPORT: The floating panel, bottom-center, charcoal ground, 16pt radius: state word at left, the mark in the middle, elapsed time at right. Empty and filled states are the same size. Menu bar: the accepted five-slat microphone glyph with Ready, Listening, Transcribing states.

FORM: User-pinned direction (beats the roll); seed key dd02b7c1, roll assigned Caption Cell, superseded by the maintainer's brief. Locked state and rejected attempts: docs/design/identity-studies.md. App icon open.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
