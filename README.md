# Claude Desktop/CLI → Free Model Gateway

Claude Code **CLI** aur **Claude Desktop app** ko ek local proxy ke through free models par chalane ka setup.
Apni **ek API key** daalein — baaki sab khud set ho jata hai.

```
Claude Desktop / Claude Code CLI
            │  (Anthropic format)
            ▼
   LiteLLM proxy  http://127.0.0.1:4000
            │
            ├──→ Experiential Labs (free models)     [primary]
            └──→ OpenRouter free models              [auto fallback]
```

---

## Requirements

- Windows 10/11 (PowerShell)
- Python 3.10+
- Claude Desktop app ya Claude Code CLI
- Ek model provider key (neeche options)

---

## Quick Start (naya laptop)

```powershell
git clone <repo-url>
cd <repo>
powershell -ExecutionPolicy Bypass -File install.ps1
```

Script khud:
1. `litellm` + `pypdf` install karti hai
2. `.env` banati hai aur **API key poochhti hai**
3. Proxy start karti hai (`127.0.0.1:4000`)
4. Claude CLI settings ko proxy par lagati hai (purani settings ka backup `backup/` mein)
5. Claude Desktop ko **3p gateway mode** mein set karti hai
6. Plugin marketplace (314 plugins) local bana deti hai

Phir **Claude Desktop restart** karein. Bas.

> Sirf CLI chahiye, Desktop na chhuein:
> `powershell -ExecutionPolicy Bypass -File install.ps1 -SkipDesktop`

---

## API Key kahan se lein?

`.env` file (install ke baad ban jati hai):

```env
EXPERIENTIAL_API_KEY=xpl_...      # zaroori
OPENROUTER_API_KEY=sk-or-v1-...   # optional fallback
GATEWAY_LOCAL_KEY=dummy-bypass-key
```

| Provider | Key | Notes |
|---|---|---|
| [Experiential Labs](https://api.experientiallabs.ai) | `xpl_...` | Free models: GPT-6 Luna, DeepSeek V4 Flash, MiMo, GPT-5.6 Luna |
| [OpenRouter](https://openrouter.ai) | `sk-or-v1-...` | Free tier (50 req/day) — sirf fallback |

**Key kabhi commit mat karein** — `.env` gitignored hai.

---

## Model slots (app picker mein jo dikhta hai)

| App model naam | Asli model | Images? | Cost |
|---|---|---|---|
| `claude-sonnet-4-5-20250929` | GPT-6 Luna | ✅ | FREE |
| `claude-haiku-4-5-20251001` | GPT-6 Luna (fast) | ✅ | FREE |
| `claude-flash-free` | DeepSeek V4 Flash | → Luna par auto-shift | FREE |
| `claude-pro-2-6` | MiMo v2.6 Pro | → Luna par auto-shift | FREE |
| `claude-luna-5-6` | GPT-5.6 Luna | ✅ | cheap |
| `claude-opus-5-5` | Claude Opus 5.5 | ✅ | paid |

**Pic attach ki?** Image block aate hi hook text-only routes (MiMo/DeepSeek) ko
GPT-6 Luna par shift kar deta hai — aapko kuch karna nahi.

Ye naam app **sirf Anthropic-style** accept karta hai — isliye free models isi tarah map hue hain.
Jab Experiential Labs ka quota khatam hota hai, LiteLLM **khud-ba-khud OpenRouter free par switch** kar deta hai (`router_settings.fallbacks`).

---

## Features (jugaad)

1. **PDF/Document support** — free models PDF input nahi lete. `custom_hooks.py`
   request ke andar PDF ko locally text mein convert kar deta hai → koi bhi free model
   document parh leta hai.
2. **Image/Pic support** — MiMo/DeepSeek text-only routes image par 400 dete hain.
   Hook image block dekhte hi request ko **GPT-6 Luna (vision)** par auto-shift kar
   deta hai → screenshots/pics/chat images har model par padh jate hain.
   URL-type images (`source.type:"url"`) khud locally download karke base64 bana
   deta hai (jo hosts provider ke server-fetch ko block karte hain unke liye).
3. **`max_tokens ≥ 16` fix** — Desktop app health probes `max_tokens:1` bhejte hain,
   gateway 429/400 deta tha; hook use 16 par raise kar deta hai.
4. **Auto fallback** — primary 429/quota de to OpenRouter free (image-capable) models
   apne aap.
5. **Detached proxy** — proxy window band hone par bhi chalta rehta hai.

---

## Roz ka istemal

```powershell
# Proxy start (boot ke baad / reboot ke baad)
powershell -ExecutionPolicy Bypass -File start-proxy.ps1

# Status check
Invoke-RestMethod http://127.0.0.1:4000/health/liveliness

# Logs
logs\proxy.out.log
logs\proxy.err.log
```

Claude Desktop **restart** karna zaroori hai jab bhi `config.yaml` badlein.

---

## Apna model add karna

`config.yaml` mein entry daalein:

```yaml
  - model_name: claude-pro-2-6          # app mein yahi naam dikhega
    litellm_params:
      model: "anthropic/tumhara-model"   # provider ka asli model
      api_base: "https://api.tumhara-provider.com"
      api_key: "os.environ/MERA_API_KEY"
      drop_params: true
      additional_drop_params: ["thinking"]
```

Aur `.env` mein `MERA_API_KEY=...` add kar dein.

---

## Connectors / Plugins / Skills

- **Plugins**: setup ke baad Claude Desktop → *Configure third-party inference* →
  **Plugins** page par local marketplace (314 plugins) dikhega.
- **Connectors (Figma, Drive, GitHub…)**: wahi window → **Connectors** → `+ Add server`
  (built-in: GitHub, Web search; templates: Microsoft 365, Box; ya apna remote MCP URL),
  ya session mein agent se bolo: *"connectors search karke add karo"*.
- **Skills**: app built-in skills (`pdf`, `docx`, `xlsx`…) use karta hai — inhe PDF
  wala hook support karta hai.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Port 4000 already in use | `Get-NetTCPConnection -LocalPort 4000` → PID `Stop-Process` |
| Proxy health fail | `logs\proxy.err.log` dekhein (keys ya path issue) |
| App model picker mein nahi | App restart; `configLibrary\_meta.json` check |
| Pic/PDF read nahi raha | Proxy restart (`custom_hooks.py` naya load ho) — phir bhi na ho to `logs\proxy.err.log` |
| PDF wala error | Proxy restart (hook `custom_hooks.py` load hone ke liye) |
| 429 quota exhausted | Fallback khud chalta hai — `.env` mein `OPENROUTER_API_KEY` dalein |
| CLI ne purana response diya | `~/.claude/settings.json` mein `ANTHROPIC_BASE_URL` check |

Purani configs ka backup `backup/` mein hota hai.

---

## Files

| File | Kaam |
|---|---|
| `install.ps1` | One-click setup |
| `start-proxy.ps1` | Proxy launcher (detached + logs) |
| `config.yaml` | Model routing (keys `.env` se) |
| `custom_hooks.py` | PDF→text jugaad + max_tokens fix |
| `.env` | Aapki API keys (**gitignored**) |
| `desktop/gateway-config.json` | App ka gateway + model picker list |

## Security

- `.env` repo mein **kabhi** nahi jata (`.gitignore`)
- Proxy sirf `127.0.0.1` par sunta hai (localhost-only)
- Gateway API key app ko sirf bypass ke liye chahiye — asli provider key sirf proxy ke andar rehti hai
