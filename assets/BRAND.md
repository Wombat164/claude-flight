# Brand

One idea, held consistently: **an attitude indicator at night**.

An artificial horizon tells a pilot one thing at a glance -- am I level, or am I
about to hit something. That is exactly what this project reports about a session
it cannot see. The prompt cursor rides the horizon line: level means alive and
taking input.

Keep that. It is the part nobody else in this space is using.

## Palette -- "night cockpit"

Real instrument-panel colours, not UI-framework defaults. The earlier palette was
stock GitHub Primer, which made the mark read as GitHub chrome rather than as a
brand.

| Token | Hex | Use |
|---|---|---|
| panel | `#0A0E14` | backgrounds, the instrument body |
| panel-raised | `#111823` | gradient partner, cards |
| sky | `#1B3A5C` | upper half of the dial (`#12283F` at the top of the gradient) |
| ground | `#6B4A2A` | lower half of the dial (`#4A3320` at the bottom) |
| **horizon** | **`#00E5A0`** | **the signature.** The horizon line, healthy state, accent |
| caution | `#FFB000` | the cursor, warnings, the footgun notice |
| bezel | `#7C8899` | instrument bezel, muted text |
| text | `#E8E6E3` | warm off-white, never pure `#FFF` |

Rules:

- `#00E5A0` is the one colour people should remember. Spend it on the horizon,
  the healthy state, and one accent per surface. Not on decoration.
- Amber means *caution*, always. Never use it decoratively -- this project's
  README leads with a footgun warning, and the palette should not undercut it.
- Never pure black or pure white. `#0A0E14` and `#E8E6E3`.
- Blue is scenery, not brand. It is the sky inside the dial and nothing else.

## Type

Monospace throughout: `ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`.
The wordmark sets `claude-flight` with the hyphen in horizon green -- the one
piece of colour in the lockup.

The docs site pairs Schibsted Grotesk (headings) with Source Sans Pro (body) and
IBM Plex Mono (code).

## Assets

| File | Use |
|---|---|
| `logo.svg` | the mark alone, 64x64. Works on light and dark: the dial carries its own dark panel |
| `wordmark.svg` | horizontal lockup, mark + wordmark + strapline. Inherits `currentColor` for the wordmark so it adapts |
| `social-preview.svg` | 1280x640 OG card. Export to PNG for GitHub's social preview field |

## Voice

Plain, specific, and honest about risk. The README warns before it sells, and the
docs say "the script wins" when they disagree with it. Aviation vocabulary is
load-bearing -- envelope protection, level, held, stood down -- not decoration.

Strapline: **keep it level, keep it alive**.
