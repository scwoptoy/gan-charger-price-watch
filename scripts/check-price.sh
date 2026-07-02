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

# Fetch Amazon product page
HTML=$(curl -sL \
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  -H "Accept-Language: en-US,en;q=0.9" \
  "https://www.amazon.com/dp/$ASIN" 2>&1)

if [ -z "$HTML" ]; then
  echo "❌ Failed to fetch Amazon page"
  exit 1
fi

# Trim HTML to manageable size for LLM (first 8K chars usually contains price)
HTML_TRIM=$(echo "$HTML" | head -c 8000)

# Extract product title (fast regex fallback)
TITLE=$(echo "$HTML" | grep -oP '<span[^>]*id="productTitle"[^>]*>\K[^<]+' | head -1 | xargs)
echo "📦 Product: ${TITLE:-Unknown}"

# Send to local LLM for price extraction
echo "🤖 Asking local LLM to extract price..."
RESPONSE=$(curl -s "$LLM_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "$LLM_MODEL" \
    --arg html "$HTML_TRIM" \
    '{
      model: $model,
      prompt: "You are a price extraction tool. Extract the CURRENT PRICE from this Amazon product page HTML. Look for price patterns like $XX.XX or $XXX.XX in the HTML. Return ONLY a valid JSON object with these fields: {\"price\": number_or_null, \"currency\": \"USD\", \"found\": true_or_false}. If you cannot find a price, set price to null and found to false. Do not include any other text.",
      stream: false,
      options: { temperature: 0 }
    }')"

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
