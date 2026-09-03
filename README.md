# messagevault-site

Marketing site for **MessageVault AI** (iOS). Static HTML, no build step, served by GitHub Pages.

## Pages
| Path | Purpose |
|---|---|
| `/` | Homepage — what it does, privacy claim, pricing |
| `/how-it-works/` | Exactly what leaves the device. The differentiator page. |
| `/compare/` | Free vs paid business models, and when MessageVault is the wrong choice |

## Publishing
Settings → Pages → Source: **Deploy from a branch** → `main` / `root`.
`.nojekyll` is present so files are served as-is with no Jekyll processing.

Live at: https://fpalmaii.github.io/messagevault-site/

## Notes
- All internal links are **relative**, so the repo can be renamed without breaking them.
- Styling is one shared `style.css`; it supports light and dark automatically.
- Every privacy claim on this site is verified against the shipping app source. Do not
  add a claim here that the code does not actually do.
