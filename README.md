# Azure OpenAI Local Proxy for Codex

Small local proxy that forwards Codex/OpenAI-style requests to Azure OpenAI using a bearer token.

## Why?
- We (at NCATS IFX) have a local deployment of Azure OpenAI that we use for development and testing.
- Codex works with MS Foundry, but only if you provide a stable API key
- Codex only works with MS Foundry given an API key, not Azure Entra ID :(
- This works around that by using a local proxy to inject the API key and adjusting the headers.
- It's lame, but it works for now.

## What it does

- Runs a FastAPI proxy on `127.0.0.1:8000`
- Injects `Authorization: Bearer <token>` from `AZURE_OPENAI_API_KEY`
- Ensures `api-version` is present on forwarded requests
- Filters web search tool entries from request body (`web_search`, `web_search_preview`)

## Requirements

- Python 3.9+
- `pip`
- `curl`
- Azure service principal credentials (`TENANT_ID`, `CLIENT_ID`, `CLIENT_SECRET`)

## Setup steps

### Step 1: Install dependencies

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Make scripts executable:

```bash
chmod +x proxy.sh codex.sh
```

### Step 2: Set Azure credentials in your shell

#### zsh (`~/.zshrc`)

Add these to `~/.zshrc`:

```bash
export TENANT_ID="your-tenant-id"
export CLIENT_ID="your-client-id"
export CLIENT_SECRET="your-client-secret"
```

Restart your terminal, or apply immediately with this command:

```bash
source ~/.zshrc
```

#### bash (`~/.bashrc` or `~/.bash_profile`)

Add these to your bash startup file:

```bash
export TENANT_ID="your-tenant-id"
export CLIENT_ID="your-client-id"
export CLIENT_SECRET="your-client-secret"
```

Apply with:

```bash
source ~/.bashrc
```

#### fish (`~/.config/fish/config.fish`)

Add these to `~/.config/fish/config.fish`:

```fish
set -x TENANT_ID "your-tenant-id"
set -x CLIENT_ID "your-client-id"
set -x CLIENT_SECRET "your-client-secret"
```

Apply with:

```fish
source ~/.config/fish/config.fish
```

Verify values are present:

```bash
echo "$TENANT_ID"
echo "$CLIENT_ID"
test -n "$CLIENT_SECRET" && echo "CLIENT_SECRET is set"
```

### Step 3: Configure Codex (`~/.codex/config.toml`)

Create or update `~/.codex/config.toml` so Codex points to the local proxy:

```toml
model = "ifx-gpt-5.3-codex"        # must match your Azure deployment name
model_provider = "azure"
model_reasoning_effort = "medium"

[model_providers.azure]
name     = "Azure OpenAI"
base_url = "http://127.0.0.1:8000/openai"
env_key  = "AZURE_OPENAI_API_KEY"
wire_api = "responses"
```

### Step 4: Launch proxy and Codex in separate terminals

Terminal 1 (proxy):

```bash
./proxy.sh
```

Terminal 2 (Codex):

```bash
./codex.sh
```

## Environment variables

Used by `proxy.sh` and `codex.sh`:
- `TENANT_ID` (required)
- `CLIENT_ID` (required)
- `CLIENT_SECRET` (required)

Runtime token sharing:

- `proxy.sh` fetches a bearer token and writes it to `.codex-token`
- `codex.sh` reads `.codex-token` to set `AZURE_OPENAI_API_KEY`
- Override token file path with `CODEX_TOKEN_FILE`

Used by `proxy.py`:

- `AZURE_OPENAI_API_KEY` (required, set before starting the proxy)
- `AZURE_BASE_URL` (optional, default `https://ncatsaopenai.openai.azure.com`)
- `AZURE_API_VERSION` (optional, default `2025-04-01-preview`)
- `PROXY_TIMEOUT_SECONDS` (optional, default `60`)

## Notes

- Proxy logs are written to `proxy.log`.
