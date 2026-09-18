# Sea Snake — Visual Style Guide

Storm/mythical direction: dark, atmospheric, a gentle rather than menacing serpent.

## Fonts (Google Fonts)
```css
@import url('https://fonts.googleapis.com/css2?family=Cinzel:wght@500;600&family=Work+Sans:wght@400;600&display=swap');
```
- **Cinzel** (500/600) — title, buttons, anything mythic/display
- **Work Sans** (400/600) — score labels, small UI text

## Color palette
| Token | Hex / value | Use |
|---|---|---|
| Deep navy | `#0b1220` | background top |
| Storm teal | `#10202b` | background upper-mid |
| Deep sea | `#0a2b34` | background lower-mid |
| Abyss | `#04141a` | background bottom |
| Board border | `rgba(150,200,190,0.32)` | game board outline |
| Snake body (gradient) | `#2fae8b → #1c6f66` | body segments, 135deg |
| Snake head (gradient) | `#45c9a1 → #1f7a70` | head, 135deg |
| Bioluminescent glow | `#3ec1a3` | accent / editable "mood" color |
| Pale gold | `#e8d9a0` | title glow, whiskers, button text/border |
| Foam | `#cfe8dc` | primary text |
| Pearl (food) | `#ffffff → #e8d9a0` radial | food item |

Full background:
```css
background:
  radial-gradient(ellipse 500px 300px at 20% -10%, rgba(120,140,160,0.22), transparent 60%),
  radial-gradient(ellipse 400px 250px at 90% 5%, rgba(90,110,130,0.18), transparent 60%),
  linear-gradient(180deg, #0b1220 0%, #10202b 35%, #0a2b34 65%, #04141a 100%);
```

Board interior:
```css
background: radial-gradient(ellipse at 50% 30%, rgba(20,60,70,0.9), rgba(4,15,20,0.98));
border-radius: 20px;
box-shadow: 0 0 24px rgba(30,80,90,0.4), inset 0 0 40px rgba(0,0,0,0.55);
```

## Atmosphere effects
- **Rain overlay:** `repeating-linear-gradient(100deg, rgba(255,255,255,0.035) 0px 1px, transparent 1px 16px)`
- **Plankton speckle grid:** `radial-gradient(circle, rgba(255,255,255,0.09) 1px, transparent 1.5px)` at 24px background-size
- **Lightning accent:** a single thin (2-3px) soft white streak, low opacity, slight rotation — sparingly, not a jagged bolt

## Glow values
- Title: `text-shadow: 0 0 14px rgba(207,232,220,0.45), 0 0 26px rgba(232,217,160,0.2)`
- Snake body: `box-shadow: 0 0 10px rgba(60,200,170,0.5)`
- Snake head: `box-shadow: 0 0 16px rgba(60,200,170,0.65)`
- Pearl: `box-shadow: 0 0 14px rgba(232,217,160,0.75)`

## Shape language (this is what keeps it "mythical, not threatening")
- Body segments: **rounded rectangles**, ~12–14px radius — not sharp squares, not full circles
- Head: larger, asymmetric rounded shape (`border-radius: 50% 50% 50% 20%`)
- Eyes: big, round, white with small dark pupils — proportionally large = friendly/non-threatening
- Two thin curved pale-gold "whiskers" off the head (like a friendly dragon, not fangs)
- Occasional small triangular fin on a mid-body segment for character
- Food: a simple glowing pearl (circle), not a hard geometric shape

## UI copy
- Title: **SEA SNAKE**
- Stats: **SCORE** and **DEPTH** (e.g. "512m") instead of generic "best"
- Primary button: **DIVE IN**
- Board corner radius: 20px · Buttons: fully pill-shaped (999px)

## Notes for implementation
These values are engine-agnostic — they'll translate directly whether the game renders via Canvas 2D (draw calls using these hex/gradient values), CSS/DOM sprites, or a framework. The core "feel" comes from: dark saturated teal/navy palette, soft glow on everything, rounded (not sharp) shapes, and oversized friendly eyes on the head.
