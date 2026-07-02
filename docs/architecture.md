# Architecture Deep Dive

## The Residential IP Advantage

The core insight: **datacenter IPs are flagged as bot traffic. Residential IPs are not.**

Cloud providers (AWS, GCP, Azure, and most VPS hosts) operate from known datacenter IP ranges. Services like Cloudflare, Amazon, and X/Twitter maintain blocklists of these ranges. When a request comes from a datacenter IP, they challenge it with CAPTCHAs or block it entirely.

A Raspberry Pi or desktop PC on a home network has an IP assigned by a residential ISP (Spectrum, AT&T, Comcast, etc.). These IPs are treated as real users because, statistically, they are. This is the same mechanism that services like BrightData and Oxylabs sell access to — but priced at $100+/mo for proxy access to what you already have.

## Data Flow

### 1. Fetch Phase

Two parallel fetches:

**Amazon (lightweight):**
```
GET https://www.amazon.com/dp/B0DRCZZ7HH
→ parse title, price from HTML
→ n8n HTTP Request node is sufficient
```

Amazon product pages are heavy but the price is embedded in the initial HTML. No JavaScript required for the price — it's in `<span class="a-price">`. An HTTP GET + regex or LLM parse is enough.

**CamelCamelCamel (requires JS):**
```
Puppeteer/Playwright → navigate to camelcamelcamel.com/product/B0DRCZZ7HH
→ wait for chart to render
→ extract price history data from the page or API calls
```

CamelCamelCamel is a SPA (single-page app). The chart data is loaded dynamically via XHR. Puppeteer running on the home lab can execute JavaScript, wait for the chart, and extract the underlying data — something that's impossible from a simple HTTP request. The Cloudflare challenge is transparent to a real browser on a residential IP.

### 2. Parse Phase

Raw HTML or JSON is sent to a local LLM:

```
POST http://localhost:11434/api/generate
{
  "model": "llama3.2",
  "prompt": "Extract the current price from this Amazon product page HTML. 
            Return ONLY a JSON object: {\"price\": number, \"currency\": \"USD\"}.
            HTML: <truncated>...",
  "stream": false
}
```

The LLM is great at this — extracting structured data from messy, truncated HTML without fragile regex or CSS selectors that break when Amazon changes their markup.

### 3. Decision Phase

```javascript
if (currentPrice < threshold) {
  // ALERT: deal detected
} else {
  // Log and move on
}
```

### 4. Notification Phase

**Email (via Himalaya CLI):**
```bash
himalaya write --to johnmccarley4@gmail.com \
  --subject "⚡ Price Drop: 320W GaN Charger — $42.99" \
  --body "$(cat /tmp/price-alert.txt)"
```

**Telegram (via n8n Telegram node or HTTP):**
```
POST https://api.telegram.org/bot<token>/sendMessage
```

## n8n Workflow Structure

The workflow in `workflows/price-watch.json` implements this as an n8n workflow with the following nodes:

```
[Schedule Trigger]
    │
    ├── [HTTP: Amazon ASIN B0DRCZZ7HH]
    │       │
    │       └── [HTTP: Local LLM parse]
    │               │
    │               └── [Set: currentPrice]
    │
    ├── [HTTP: Amazon ASIN B0CT2NQ7WG]  
    │       └── ... (same pattern)
    │
    └── [HTTP: Amazon ASIN B09C5RG6KV]
            └── ... (same pattern)
                    │
                    ▼
            [Merge: all prices]
                    │
                    ▼
            [IF: any price < threshold]
                    │
            ┌───────┴───────┐
            ▼               ▼
        [Email]        [Telegram]
        [Alert]         [Alert]
```

## Extending

### Adding X/Twitter deal search

Install xurl CLI and add an Execute Command node:
```bash
xurl search '"320W GaN charger" deal OR discount OR sale' -n 10
```

### Adding Slickdeals RSS

Add an RSS Feed Read node:
```
https://slickdeals.net/newsearch.php?rss=1&q=gan+charger
```

### Price history tracking

Add a database (SQLite or n8n's built-in) to store historical prices. The local LLM can then do trend analysis:
> "This product has dropped 15% over the last 30 days. Current price of $42.99 is the lowest in 6 months."
