# Desktop interaction design

This is the intended Australis graphical shell design. Phase 7 builds the
window and compositor behavior, Phase 8 improves software rendering and
performance, and Phase 14 supplies the finished desktop shell and apps.

## Workspace and top bar

- A single top bar spans the display. There is no taskbar or dock.
- With no maximized window, the finished bar is semi-translucent with a
  frosted blur of the content behind it. Phase 7's live bar is opaque and
  dark; blur is part of Phase 8 software rendering.
- When a window is maximized, the bar becomes solid black. The maximized
  window's title bar visually joins the top bar, with one set of window
  controls in the combined bar.
- Restoring that window moves its title bar and controls back into the window
  and returns the top bar to its ordinary appearance.

## Windows and controls

- Floating windows have no visible border and have rounded corners.
- Close, minimize, and maximize controls are coloured circles in the Mac
  style: red, yellow, and green. Their action icons appear on hover; the
  coloured circles remain visible at other times.
- Maximize and restore use the same green control. A maximized window fills
  the workspace below the top bar, without a duplicate title bar.
- Invisible edge hit regions allow resizing a floating window without adding
  a visible border. Hit testing must keep controls and resize regions distinct.
- The compositor owns stacking, clipping, focus, cursor targeting, and
  damage. A window only receives pointer and keyboard input when routing
  selects it; a client cannot paint into the top bar or another window.

## Phase boundaries

- Phase 7 should prove the behavior with two independent windows, including
  moving, resizing, maximizing, restoring, focusing, and closing them.
- Phase 8 can add frosted rendering as part of software composition and
  performance work. The finished top-bar content, launcher, login flow,
  and desktop applications belong to Phase 14. The basic top-bar surface
  and maximise transition exist in Phase 7 so the window protocol accounts
  for them.
- A minimized window remains alive and hidden. The Phase 7 top bar shows
  one chip for each live window, grey when minimized; selecting its chip
  restores and focuses it. A richer window menu belongs to the finished
  desktop shell.

## Interaction check

With two windows open, moving and resizing one leaves the other intact.
Maximizing the focused window joins its title bar and controls to the top bar
and turns the bar black. Restoring returns the window's rounded floating
decoration and the frosted bar. Hovering each coloured control reveals its
icon; clicking performs the corresponding action. The pointer and keyboard
continue to reach only the intended window throughout these transitions.
