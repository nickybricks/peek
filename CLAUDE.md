# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

## Projekt: Peek

Ein macOS-Fensterwechsler. `Cmd-Tab` zeigt alle Fenster aller Apps und Spaces,
`Option-Tab` nur die der aktiven App. Swift Package ohne Abhängigkeiten, ~500 Zeilen.

**Bewusst ohne Einstellungen.** Keine anpassbaren Shortcuts, kein Preferences-Fenster.
Wer Konfiguration will, nimmt AltTab. Feature-Wünsche an diesem Prinzip messen: Was das
Menü um mehr als eine Zeile wachsen lässt, gehört vermutlich nicht rein.

**Bauen:** `./build.sh` — baut, signiert, installiert nach `/Applications/Peek.app`,
startet neu. Kein Xcode-Projekt, alles über `swift build`.

**Berechtigungen:** Bedienungshilfen (Tastatur-Abgriff) und Bildschirmaufnahme
(Thumbnails). Signatur stabil halten — bei Ad-hoc-Signatur gilt jeder Build für macOS als
neue App und beide Berechtigungen müssen neu erteilt werden. Nach Änderungen an Bundle-ID
oder Signatur alte Einträge mit `tccutil reset Accessibility de.algner.peek` aufräumen,
sonst fragt macOS endlos trotz gesetztem Haken.

## Git Push & Release

Wenn der Nutzer bittet, „zu pushen" oder „zu releasen": einen **Semantic-Version-Bump**
mitgeben und selbst über die Höhe entscheiden.

**EINE Zahl für Tag und App.** Git-Tag und `CFBundleShortVersionString` in `Info.plist`
tragen dieselbe Version. `./release.sh <version>` setzt die Plist-Werte selbst — wer einen
Tag setzt, lässt also `release.sh` laufen oder bumpt die Plist im selben Commit.

Bump aus dem Umfang der Änderungen ableiten:

| Änderungstyp | Bump | Beispiel |
| --- | --- | --- |
| Bugfixes, Copy, kleine Tweaks | **Patch** (`0.1.0`→`0.1.1`) | Sortier-Fix, Menü-Wortlaut |
| Neue Features, größere Ergänzungen | **Minor** (`0.1.0`→`0.2.0`) | neuer Shortcut-Modus, Multi-Monitor |
| Breaking Changes, große Rewrites | **Major** (`0.1.0`→`1.0.0`) | Architektur-Umbau |

Aktuelle Version aus dem höchsten Tag ableiten (`git tag --sort=-v:refname | head -1`);
noch keine Tags → erster Release ist `v0.1.0` (bzw. der passende Bump davon).

**Niemals committen** (schon in `.gitignore`): `.build/`, `build/`, `.claude/`, `.DS_Store`.

Ablauf:

```bash
# 1. Nur echte Quell-Dateien stagen
git add <geänderte Quelldateien>
# 2. Commit (Version in der Message)
git commit -m "v{VERSION}: {kurze Beschreibung}"
# 3. Annotierten Tag setzen
git tag -a v{VERSION} -m "v{VERSION}: {kurze Beschreibung}"
# 4. Mit Tags pushen (sonst legt GitHub keine Release-Referenz an)
git push origin main --tags
```

Bei einem Release mit Download-Artefakt zusätzlich: `./release.sh {VERSION}` und das
erzeugte `build/Peek.zip` an den GitHub-Release hängen. Das Skript notarisiert, wenn ein
`notarytool`-Keychain-Profil existiert — sonst warnt es, und Nutzer sehen beim Öffnen eine
Gatekeeper-Warnung.

Commit-Messages weiterhin mit `Co-Authored-By: Claude …` abschließen.
