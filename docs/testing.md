# Testing Guide

## Test Products (migrated from Hermes cron jobs)

These are the three products we track. Use them as the test suite when validating the n8n workflow.

| # | Product | ASIN | Amazon URL | Threshold |
|---|---------|------|------------|-----------|
| 1 | 320W 10-Port GaN III USB-C Charger | B0DRCZZ7HH | [Amazon](https://www.amazon.com/dp/B0DRCZZ7HH) | $45 |
| 2 | Anker Prime 200W 6-Port GaN Desktop Charger | B0CT2NQ7WG | [Amazon](https://www.amazon.com/dp/B0CT2NQ7WG) | $55 |
| 3 | Anker 65W 3-Port GaN Foldable USB-C Charger | B09C5RG6KV | [Amazon](https://www.amazon.com/dp/B09C5RG6KV) | $25 |

## Quick Smoke Test

### 1. Verify the CLI script works for each product

```bash
# Test product 1 — 320W GaN Charger
./scripts/check-price.sh B0DRCZZ7HH 45

# Test product 2 — Anker 200W
./scripts/check-price.sh B0CT2NQ7WG 55

# Test product 3 — Anker 65W
./scripts/check-price.sh B09C5RG6KV 25
```

**Expected:** Each command prints the current price and whether it's a deal.

### 2. Verify the LLM endpoint is reachable

```bash
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2",
  "prompt": "Say hello and confirm you are running.",
  "stream": false
}'
```

**Expected:** JSON response with the model's reply.

### 3. Import and test the workflow in n8n

1. Open n8n → **Import from File** → `workflows/price-watch.json`
2. Set environment variables in n8n:
   - `LLM_ENDPOINT` → `http://localhost:11434/api/generate` (or your llama.cpp server)
   - `LLM_MODEL` → `llama3.2`
   - `THRESHOLD_320W` → `45`
   - `THRESHOLD_ANKER_200W` → `55`
   - `THRESHOLD_ANKER_65W` → `25`
3. Click **Test Workflow** (manual execution)
4. Check the output of the **Log Summary** node — verify all three products returned prices

## Troubleshooting

### "Could not extract price" in LLM output

The LLM couldn't find a price in the HTML. Try:
- Increase `HTML_TRIM` size in the Code nodes (currently 8000 chars)
- Try a different model (e.g., `mistral` instead of `llama3.2`)
- Check that the Amazon page loaded correctly (non-200 status, CAPTCHA page)

### Amazon returns a CAPTCHA page

This means Amazon flagged the request as bot traffic. Possible fixes:
- **Residential IP:** Make sure n8n is running on your home lab (Pi or PC), not a VPS
- **User-Agent:** Verify the workflow uses a recent Chrome/Firefox User-Agent header
- **Rate limiting:** Don't run the workflow more than once per hour

### LLM endpoint unreachable

- Check Ollama is running: `systemctl status ollama` or `ollama serve`
- Verify the endpoint URL: `curl $LLM_ENDPOINT`
- For llama.cpp, the endpoint is typically `http://localhost:8080/completion`

## Adding a New Product

1. Find the ASIN on Amazon (e.g., `B0XXXXXX` in the URL)
2. Add a new "Fetch Amazon" → "Prepare" → "LLM Extract" → "Compare" chain in the workflow
3. Connect it to the Merge node
4. Set the threshold in n8n environment variables

Or duplicate an existing product chain and update the ASIN, threshold variable, and names.
