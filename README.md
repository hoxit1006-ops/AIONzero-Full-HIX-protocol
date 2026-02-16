# HIX Protocol Landing + Data API Surface

HIX Protocol is a lightweight web landing experience for showcasing live network stats, global miner leaderboard data, mobile app onboarding, and wallet readiness (manual Solana address entry + Phantom connect).

> **Important:** This repository currently ships a static frontend with direct Supabase reads from the browser. For production hardening, move secrets and write operations behind a secure backend/API layer.

## Features

- **Realtime-ish network metrics** pulled from Supabase REST endpoints.
- **Top miner leaderboard** with resilient rendering and safe DOM updates.
- **Wallet onboarding hub**:
  - Manual Solana wallet entry (basic Base58-format validation).
  - One-click Phantom connect when extension is present.
  - Local persistence via `localStorage`.
- **Mobile app download cards** and social/community links.
- **PWA basics** (`manifest.json`, `sw.js`).

## Repository Structure

- `index.html` — Main landing page (HTML/CSS/JS in one file).
- `manifest.json` — PWA manifest.
- `sw.js` — Service worker bootstrap.
- `supabase-schema.sql`, `COMPLETE-DATABASE-SCHEMA.sql`, `LEADERBOARD-COMPLETE.sql`, `PREMIUM-PASSES-COMPLETE.sql` — SQL references and schema docs.
- `TERMS.md`, `PRIVACY.md`, `DISCLAIMER.md` — Legal policy documents.

## Local Development

Run locally with a static server:

```bash
python3 -m http.server 4173
```

Then open:

- `http://127.0.0.1:4173/index.html`

## Deployment

This project can be deployed to Netlify/Vercel/GitHub Pages as a static site.

### Netlify

- `netlify.toml` is already present.
- Connect repository to Netlify and deploy from the default branch.

## Security Notes (Read Before Production)

1. **Do not expose privileged database keys** in client-side JavaScript.
2. Restrict Supabase RLS policies for all tables.
3. Move wallet-registration writes to a server endpoint with validation + abuse protection.
4. Add CSP headers and strict transport security in production.
5. Consider adding anti-bot controls (rate limit, Turnstile, etc.) for public forms.

## Legal and Compliance Notes

- Review and customize `TERMS.md` and `PRIVACY.md` for your jurisdiction.
- If you collect biometric, motion, health-adjacent, or geolocation data, consult counsel for region-specific compliance obligations (e.g., GDPR/CCPA/BIPA where applicable).
- Keep your legal docs aligned with actual data practices.

## GitHub: How to push this live

From your local machine:

```bash
git remote add origin <YOUR_GITHUB_REPO_URL>
git push -u origin work
```

Then open a Pull Request from `work` into your main branch on GitHub.

If this repository already has `origin` configured:

```bash
git push
```

## Disclaimer

This repository and website are provided "as is" without warranties of any kind. Nothing here is legal, investment, tax, or financial advice.
