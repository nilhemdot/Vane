#!/usr/bin/env bash
# Recreate the searxng container with the API-key engines (Brave, Exa, Tavily) enabled.
# Keys are read from `export NAME=...` lines in ~/.bashrc and written only to
# searxng/settings.local.yml (gitignored via /searxng), never to the tracked settings.yml.
# usage: scripts/searxng-keys.sh [--print]   (--print writes the merged settings to stdout and stops)
set -euo pipefail
REPO=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}

key() { grep -oP "^export $1=\K\S+" ~/.bashrc | tr -d "\"'" || true; }
BRAVE="$(key BRAVE_API_KEY)"; EXA="$(key EXA_API_KEY)"; TAVILY="$(key TAVILY_API_KEY)"

# settings.yml ends with the engines list, so appended entries join it; engines without a key are skipped
merged() {
  cat "$REPO/searxng/settings.yml"
  # `if` rather than `[ ] &&`: a false test as the function's last command would abort under set -e
  if [ -n "$BRAVE" ]; then
    printf "  - name: braveapi\n    api_key: '%s'\n    inactive: false\n" "$BRAVE"
  fi
  if [ -n "$EXA" ]; then
    printf "  - name: exaapi\n    api_key: '%s'\n    inactive: false\n" "$EXA"
  fi
  # SearxNG has no Tavily engine; json_engine POSTs to its API. shortcut: the query is inserted unescaped, so a " in it breaks that request
  if [ -n "$TAVILY" ]; then
    cat <<EOF
  - name: tavily
    engine: json_engine
    shortcut: tav
    categories: [general, web]
    method: POST
    search_url: https://api.tavily.com/search
    request_body: '{{"query": "{query}", "max_results": 10}}'
    headers:
      Authorization: 'Bearer $TAVILY'
      Content-Type: application/json
    results_query: results
    url_query: url
    title_query: title
    content_query: content
    timeout: 10
    disabled: false
EOF
  fi
}

if [ "${1:-}" = "--print" ]; then merged; exit 0; fi

echo "keys found: brave=${BRAVE:+yes} exa=${EXA:+yes} tavily=${TAVILY:+yes}" >&2
merged | sudo tee "$REPO/searxng/settings.local.yml" >/dev/null

sudo docker rm -f searxng >/dev/null
sudo docker run -d --name searxng --restart unless-stopped \
  --network vane-net -p 127.0.0.1:8080:8080 \
  -v "$REPO/searxng:/etc/searxng" \
  -e SEARXNG_SETTINGS_PATH=/etc/searxng/settings.local.yml \
  -e SEARXNG_SECRET="$(openssl rand -hex 32)" \
  searxng/searxng:latest
