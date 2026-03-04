# 🎯 ReconArt — Bug Bounty Reconnaissance Framework

> A modular, scope-aware recon framework built for bug bounty hunters. ReconArt automates the full recon pipeline — from attack surface discovery to live target analysis — while keeping you in control with manual review checkpoints and real-time Telegram alerts.

-----

## ✨ Features

- **Pre-Recon Intelligence** — Discover root domains via Amass, Shodan, and crt.sh before any active scanning begins
- **Passive Subdomain Enumeration** — Subfinder-powered discovery with automatic httpx probing
- **Active Subdomain Brute-Force** — High-throughput shuffleDNS + massdns with custom resolver optimization
- **Content Discovery** — URL harvesting via GAU, Waybackurls, and Katana (including JavaScript crawling)
- **GF Parameter Extraction** — Automatically flags interesting parameters and file extensions
- **Deep JS Analysis** — LinkFinder + SecretFinder pipeline for exposed endpoints and leaked secrets
- **Scope Enforcement** — Every output is filtered against `in_scope.txt` / `out_of_scope.txt` at every pipeline stage
- **Priority Target Detection** — Keyword-based matching against live targets with instant Telegram notifications
- **Workspace Management** — Organized per root-domain directory structure for clean, resumable sessions

-----

## 🏗️ Architecture

```
ReconArt/
├── reconart.sh                   # Main script
├── seeds.txt                     # Root domains from pre-recon phase
├── in_scope.txt                  # Scope whitelist (regex patterns, one per line)
├── out_of_scope.txt              # Scope blacklist (regex patterns, one per line)
├── resolvers.txt                 # Auto-updated DNS resolver list
├── priority_targets.txt          # Critical findings aggregated here
└── roots/
    └── root_example.com/
        ├── subdomains.txt        # Master subdomain list
        ├── subfinder_results.txt # Passive enum results
        ├── active_results.txt    # Brute-force results
        ├── active_unique.txt     # Net-new subs from active phase
        ├── httpx_live.txt        # Live targets (passive)
        ├── httpx_live_active.txt # Live targets (active)
        ├── endpoints.txt         # Harvested URLs
        ├── parameters.txt        # Interesting parameters
        ├── js_links.txt          # Discovered JS files
        ├── js_endpoints.txt      # Endpoints extracted from JS
        └── secrets.txt           # Secrets found in JS
```

-----

## ⚙️ Dependencies

Make sure the following tools are installed and accessible in your `$PATH`:

|Tool                                                        |Purpose                            |
|------------------------------------------------------------|-----------------------------------|
|[subfinder](https://github.com/projectdiscovery/subfinder)  |Passive subdomain enumeration      |
|[httpx](https://github.com/projectdiscovery/httpx)          |HTTP probing & fingerprinting      |
|[shuffledns](https://github.com/projectdiscovery/shuffledns)|Active DNS brute-force             |
|[massdns](https://github.com/blechschmidt/massdns)          |High-performance DNS resolver      |
|[gau](https://github.com/lc/gau)                            |Passive URL harvesting             |
|[waybackurls](https://github.com/tomnomnom/waybackurls)     |Wayback Machine URL fetching       |
|[katana](https://github.com/projectdiscovery/katana)        |Active web crawling                |
|[gf](https://github.com/tomnomnom/gf)                       |Pattern-based parameter extraction |
|[anew](https://github.com/tomnomnom/anew)                   |Append unique lines to files       |
|[linkfinder](https://github.com/GerbenJavado/LinkFinder)    |JS endpoint discovery              |
|[SecretFinder](https://github.com/m4ll0k/SecretFinder)      |JS secret/credential discovery     |
|[amass](https://github.com/owasp-amass/amass)               |ASN/org-based intel gathering      |
|[shodan](https://cli.shodan.io/)                            |Shodan CLI for IP/cert hunting     |
|[puredns](https://github.com/d3mondev/puredns)              |DNS resolution & wildcard filtering|
|[tldextract](https://pypi.org/project/tldextract/)          |Python lib for domain parsing      |
|[jq](https://stedolan.github.io/jq/)                        |JSON processing (crt.sh output)    |
|curl                                                        |HTTP requests                      |

-----

## 🔧 Setup

### 1. Clone and configure

```bash
git clone https://github.com/yourusername/reconart.git
cd reconart
chmod +x reconart.sh
```

### 2. Set Telegram credentials

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
export TELEGRAM_API_TOKEN="your_bot_token_here"
export TELEGRAM_CHAT_TOKEN="your_chat_id_here"
```

Then reload: `source ~/.bashrc`

### 3. Set up wordlists

```bash
mkdir -p ~/wordlists
# Place your subdomain wordlist at:
~/wordlists/all.txt

# Place your critical keyword list at:
~/wordlists/hq_critical_subdomain_keywords.txt
```

Recommended wordlists:

- [SecLists](https://github.com/danielmiessler/SecLists) — `Discovery/DNS/`
- [assetnote wordlists](https://wordlists.assetnote.io/)

### 4. Configure scope files

**`in_scope.txt`** — one regex pattern per line for in-scope targets:

```
example\.com
.*\.example\.com
```

**`out_of_scope.txt`** — one regex pattern per line for exclusions:

```
blog\.example\.com
status\.example\.com
```

-----

## 🚀 Usage

```bash
./reconart.sh
```

### Main Menu

```
0) Pre-Recon Intelligence      → Build seeds.txt (root domains)
1) Prepare & Sync Workspaces   → Import target list, organize per root domain
2) Recon Engine                → Run passive/active enumeration & content discovery
3) Manual Review               → View all live targets, export to all_live_targets.txt
4) Exit
```

### Recommended Workflow

```
Pre-Recon (0) → Sync Workspaces (1) → Passive Enum (2→1) → Active Brute (2→2) → Content Discovery (2→3)
```

-----

## 📡 Telegram Alerts

ReconArt sends real-time alerts for:

- 🚨 **In-scope critical subdomains** — matched against your keyword list
- 💎 **JS secrets found** — any credentials/tokens discovered in JavaScript files

To set up a Telegram bot: [BotFather](https://t.me/botfather) → create bot → get token → add to `.bashrc`

-----

## 🔒 Scope Enforcement

Scope filtering runs **automatically** at every stage of the pipeline:

1. After importing targets into workspaces
1. After passive enumeration results
1. After active brute-force results
1. During priority target analysis

Only domains matching `in_scope.txt` AND not matching `out_of_scope.txt` are processed further or alerted on.

-----

## 📋 Ports Scanned (Active Mode)

ReconArt probes an extended port list beyond 80/443 to catch internal services and non-standard deployments:

`80, 443, 3000, 4443, 5000, 8000, 8080, 8443, 8888, 9000, 9090, 10000` and [50+ more](https://github.com/yourusername/reconart/blob/main/reconart.sh#L120)

-----

## ⚠️ Legal Disclaimer

This tool is intended **exclusively for authorized security testing** — bug bounty programs, CTFs, and environments where you have explicit written permission. Unauthorized use against systems you do not own or have permission to test is illegal and unethical. The author assumes no responsibility for misuse.

Always verify scope before running any enumeration.

-----

## 🤝 Contributing

PRs and issues welcome. If you have a better keyword list, scope filter pattern, or tool integration to suggest, open an issue.

-----

*Built for the bug bounty grind. Stay in scope, stay legal.*