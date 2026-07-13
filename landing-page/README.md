# grove landing page

The source for **[grove.shivgodhia.com](https://grove.shivgodhia.com)** — a static,
zero-build landing page for grove.

## What's here

| File | Purpose |
|------|---------|
| `index.html` | The page |
| `styles.css` | All styles (dappled-forest theme, light + dark) |
| `grove.js` | Theme toggle, copy buttons, ambient canvas, prompt loader |
| `fonts/` | Self-hosted variable fonts (Fraunces, Inter, JetBrains Mono) |
| `favicon.svg` | Favicon |
| `install-prompt.txt` | **Generated** — the full guided-setup prompt, extracted from the repo README |
| `build-prompt.sh` | Regenerates `install-prompt.txt` from `../README.md` |
| `_headers` | Cloudflare Pages cache headers |

## Single source of truth for the install prompt

The full guided-setup prompt lives in the repo's top-level `README.md` (the first
four-backtick fenced block). `build-prompt.sh` extracts it into `install-prompt.txt`,
which the page fetches at runtime. **Don't edit `install-prompt.txt` by hand** — edit
the README, then rerun the build. This keeps the README and the page from drifting.

```sh
./build-prompt.sh
```

## Local preview

```sh
cd landing-page
./build-prompt.sh          # regenerate the prompt (safe to re-run)
python3 -m http.server 8731
# open http://localhost:8731
```

## Deploy — Cloudflare Pages

Hosted on Cloudflare Pages, connected to this GitHub repo.

- **Production branch:** `main`
- **Build command:** `bash landing-page/build-prompt.sh`
- **Build output directory:** `landing-page`
- **Root directory:** repo root (so the build script can read `../README.md`)

Cloudflare rebuilds on every push to `main`. The custom domain
`grove.shivgodhia.com` is attached in the Pages project's **Custom domains** tab,
which provisions the DNS record and TLS certificate automatically.

Fonts are self-hosted (SIL Open Font License) — no external CDN, no network
dependency at runtime.
