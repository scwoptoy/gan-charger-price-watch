# GaN Charger Price Watch

DIY price tracking for GaN USB-C chargers using **n8n + local LLM** running on a home lab with a residential IP — the cheat code that makes scraping actually work in 2025.

## Why This Works

Cloud services (AWS, GCP, etc.) get blocked by Cloudflare and bot detection. A Raspberry Pi on your home network has a residential IP — the same IP that loads Amazon and CamelCamelCamel in your browser. That means:

| Source | Cloud Cron | Home Lab |
|--------|-----------|----------|
| Amazon product pages | ❌ Captcha | ✅ Direct access |
| CamelCamelCamel | ❌ Cloudflare block | ✅ Loads normally |
| Slickdeals / DealNews | ⚠️ Flaky | ✅ RSS feeds |
| X/Twitter search | ❌ Login wall | ✅ Via xurl CLI |

## Architecture

```
┌──────────────────────────────────────────────────┐
│                 HOME LAB (Pi 5 or PC)             │
│                                                   │
│  n8n workflow (cron: daily/weekly)                │
│  ┌────────────┐    ┌──────────────┐              │
│  │ HTTP Node  │    │ Puppeteer    │              │
│  │ (Amazon,   │    │ Node (CCC,   │              │
│  │  RSS)      │    │  JS-heavy)   │              │
│  └─────┬──────┘    └──────┬───────┘              │
│        │                  │                       │
│        ▼                  ▼                       │
│  ┌──────────────────────────────┐                 │
│  │  Local LLM (Ollama/llama.cpp)│                 │
│  │  Parse HTML, extract prices, │                 │
│  │  compare to thresholds       │                 │
│  └──────────────┬───────────────┘                 │
│                 │                                  │
│                 ▼                                  │
│  ┌──────────────────────────────┐                 │
│  │  IF price < threshold        │                 │
│  │  → Email (Himalaya)          │                 │
│  │  → Telegram                  │                 │
│  └──────────────────────────────┘                 │
└──────────────────────────────────────────────────┘
```

## Products Tracked

| Product | ASIN | Threshold |
|---------|------|-----------|
| 320W 10-Port GaN III USB-C Charger | B0DRCZZ7HH | TBD |
| Anker Prime 200W 6-Port GaN | B0CT2NQ7WG | TBD |
| Anker 65W 3-Port GaN Foldable | B09C5RG6KV | TBD |

## Setup

### Prerequisites

- **n8n** running on your home lab (Pi 5 or PC)
- **Ollama** or **llama.cpp** server with a capable model (e.g., llama 3, mistral)
- **Himalaya CLI** for email delivery (or n8n email node)
- **xurl CLI** (optional, for X/Twitter deal search)

### Quick Start

```bash
# Clone the repo
git clone https://github.com/scwoptoy/gan-charger-price-watch.git
cd gan-charger-price-watch

# Copy and fill in environment
cp .env.example .env

# Import workflow into n8n
# n8n → Import from File → workflows/price-watch.json

# Test a single product
./scripts/check-price.sh B0DRCZZ7HH
```

### Environment Variables (`.env`)

```
# Local LLM endpoint
LLM_ENDPOINT=http://localhost:11434/api/generate
LLM_MODEL=llama3.2

# Thresholds (dollars) — alert if price drops below
THRESHOLD_320W=45
THRESHOLD_ANKER_200W=55
THRESHOLD_ANKER_65W=25

# Notifications
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
EMAIL_TO=johnmccarley4@gmail.com
```

## Workflow Details

### `price-watch.json` — Main n8n workflow

1. **Schedule Trigger** — runs on cron (e.g., daily at 9am)
2. **HTTP Request** — fetches Amazon product page by ASIN
3. **Puppeteer** — loads CamelCamelCamel for price history (bypasses Cloudflare)
4. **HTTP Request** — calls local LLM endpoint with raw HTML, asks for structured price extraction
5. **IF Node** — compares extracted price against threshold
6. **Email / Telegram** — sends alert if deal detected

### `scripts/check-price.sh` — CLI quick check

Standalone bash script to check one product's current price without n8n. Useful for manual checks and testing.

## Why DIY Over Paid APIs

| Approach | Cost | Reliability |
|----------|------|-------------|
| Keepa API | $19/mo | ✅ Always works |
| Amazon PAAPI | Free* | ⚠️ Revoked if < 3 sales/180 days |
| BrightData proxies | $100+/mo | ✅ Bypasses everything |
| **Home lab + n8n** | **$0/mo** | ✅ Residential IP = trusted |

## Contributing

This is a personal project. PRs welcome if you're tracking similar products.

## License

MIT
