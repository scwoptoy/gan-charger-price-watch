#!/bin/bash
# check-price.sh — Quick price check for a single Amazon product
# Usage: ./scripts/check-price.sh <ASIN> [threshold_dollars]
# Example: ./scripts/check-price.sh B0DRCZZ7HH 45

set -euo pipefail

ASIN="${1:?Usage: $0 <ASIN> [threshold]}"
THRESHOLD="${2:-999999}"
LLM_ENDPOINT="${LLM_ENDPOINT:-http://localhost:11434/api/generate}"
LLM_MODEL="${LLM_MODEL:-llama3.2}"

echo "🔍 Checking Amazon price for ASIN: $ASIN"
echo ""

# Fetch Amazon product page to temp file
TMPFILE=$(mktemp /tmp/amazon-XXXXXX.html)
trap 'rm -f $TMPFILE' EXIT

curl -sL \
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept-Language: en-US,en;q=0.9" \
  "https://www.amazon.com/dp/$ASIN" > "$TMPFILE"

HTML_SIZE=$(stat -c%s "$TMPFILE")
if [ "$HTML_SIZE" -lt 100 ]; then
  echo "❌ Failed to fetch Amazon page (got ${HTML_SIZE} bytes)"
  exit 1
fi

# Extract product title (fast regex fallback)
TITLE=$(grep -oPm1 '<span[^>]*id="productTitle"[^>]*>\K[^<]+' "$TMPFILE" | xargs)
echo "📦 Product: ${TITLE:-Unknown}"

# Find price-relevant HTML section (skip JS boilerplate at top)
HTML_TRIM=$(grep -oPm1 '.{0,200}(?:a-price|priceblock|apexPriceToShow|ourprice).{0,3000}' "$TMPFILE")
# Fallback: if no price section found, grab a chunk around 'price' keyword
if [ -z "$HTML_TRIM" ]; then
  HTML_TRIM=$(grep -oPm1 '.{0,50}price.{0,3000}' "$TMPFILE")
fi
# Last resort: first 12K chars
if [ -z "$HTML_TRIM" ]; then
  HTML_TRIM=$(head -c 12000 "$TMPFILE")
fi

# Also grab raw price via regex as a fallback hint for the LLM
RAW_PRICE=$(grep -oPm1 'a-offscreen[^>]*>\$\K[\d.]+' "$TMPFILE")
[ -z "$RAW_PRICE" ] && RAW_PRICE=$(grep -oPm1 '"price":\s*"?\K[\d.]+' "$TMPFILE")

# Send to local LLM for price extraction
echo "🤖 Asking local LLM to extract price..."
RESPONSE=$(curl -s "$LLM_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "$LLM_MODEL" \
    --arg html "$HTML_TRIM" \
    --arg hint "$RAW_PRICE" \
    '{
      model: $model,
      prompt: ("Extract the current price from this Amazon product HTML. " + (if $hint != "" then ("The price might be $" + $hint + ". ") else "" end) + "Look for the number inside a-offscreen span or a-price element. Return ONLY this exact JSON with no other text: {\"price\": <number>, \"currency\": \"USD\", \"found\": true} or if no price found: {\"price\": null, \"currency\": \"USD\", \"found\": false}\n\nHTML:\n" + $html),
      stream: false,
      options: { temperature: 0.1 }
    }')"
)

PRICE_JSON=$(echo "$RESPONSE" | jq -r '.response // empty' 2>/dev/null)
PRICE=$(echo "$PRICE_JSON" | jq -r '.price // empty' 2>/dev/null)
FOUND=$(echo "$PRICE_JSON" | jq -r '.found // false' 2>/dev/null)

echo ""
if [ "$FOUND" = "true" ] && [ -n "$PRICE" ] && [ "$PRICE" != "null" ]; then
  echo "💰 Current price: \$$PRICE"

  # Compare against threshold
  if awk "BEGIN {exit !($PRICE < $THRESHOLD)}"; then
    echo "⚡ DEAL ALERT: Price \$$PRICE is below threshold of \$$THRESHOLD!"
    exit 0
  else
    echo "📊 Price is above threshold of \$$THRESHOLD — no alert."
  fi
else
  echo "⚠️  Could not extract price from page."
  echo "   LLM response: ${PRICE_JSON:-$RESPONSE}"
  exit 2
fi
