# vhs tape for the README demo GIF — the merge-gate hook in action.
#
# Records docs/demo/merge-gate-demo.sh (which runs the REAL hook against a throwaway QA scene:
# a clean GO with one item left "not executed" is blocked; once the gap is closed the merge is allowed).
#
# How to record (one-time):
#   1. Install vhs:  brew install vhs   (or: go install github.com/charmbracelet/vhs@latest)
#   2. From the repo root:  vhs docs/demo.tape
#   3. It writes docs/demo.gif — then uncomment the <img> line in README.md.
#
# Tweak FontSize/Width/Height/Theme to taste; everything else is timing.

Output docs/demo.gif

Require bash

Set Shell bash
Set FontSize 16
Set Width 1240
Set Height 760
Set Padding 26
Set Theme "Dracula"
Set TypingSpeed 55ms

# Build is driven entirely by the demo script (it clears, narrates, and paces itself).
Hide
Type "clear" Enter
Show
Sleep 600ms

Type "bash docs/demo/merge-gate-demo.sh"
Sleep 500ms
Enter

# Wait out the scripted beats (≈9 × 1.4s + the two gate runs). Bump if you raise DEMO_BEAT.
Sleep 15s
