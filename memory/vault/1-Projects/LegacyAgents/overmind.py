#!/usr/bin/env python3
"""
PROJECT OVERMIND — Total Autonomous Operation
No bridge. No middleman. Self-directing AI swarm.
Uses: NATS (port 4222), Direct API calls, Self-healing loops
"""

import asyncio
import httpx
import json
import hashlib
import subprocess
import psutil
from datetime import datetime, timedelta
from pathlib import Path
import nats  # pip install nats-py

# CONFIGURATION
ROOT = Path("C:/openclaw")
SECRETS = ROOT / "secrets"
GHOST = ROOT / "ghost"
CACHE = ROOT / "cache"
QUEUE = ROOT / "workflows" / "queue"
LOG_FILE = GHOST / "overmind.log"

SECRETS.mkdir(parents=True, exist_ok=True)
GHOST.mkdir(exist_ok=True)
CACHE.mkdir(exist_ok=True)
QUEUE.mkdir(parents=True, exist_ok=True)

# Load keys with proper encoding handling
def load_key(filename):
    try:
        path = SECRETS / filename
        if path.exists():
            # Read as bytes then decode to handle any BOM or encoding issues
            return path.read_bytes().decode('utf-8').strip()
    except Exception as e:
        log(f"Key load error: {e}")
    return None

PERPLEXITY_KEY = load_key("perplexity_key.txt")
ANTHROPIC_KEY = load_key("anthropic_key.txt")

if not PERPLEXITY_KEY:
    raise SystemExit("Perplexity key missing")
if not ANTHROPIC_KEY:
    raise SystemExit("Anthropic key missing")

# Logging
def log(msg):
    ts = datetime.now().isoformat()
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")

# Budget tracking (in-memory, resets daily)
class Budget:
    def __init__(self, limit=50.0):
        self.limit = limit
        self.spent = 0.0
        self.last_reset = datetime.now().date()
        self.lock = asyncio.Lock()
    
    async def check(self, cost=0.01):
        async with self.lock:
            today = datetime.now().date()
            if today != self.last_reset:
                self.spent = 0.0
                self.last_reset = today
                log("Budget reset for new day")
            return (self.spent + cost) <= self.limit
    
    async def spend(self, amount):
        async with self.lock:
            self.spent += amount

budget = Budget()

# Cache system
def cache_key(prompt):
    return hashlib.md5(prompt.encode()).hexdigest()[:16] + ".json"

def cache_get(key):
    try:
        path = CACHE / key
        if path.exists():
            data = json.loads(path.read_text())
            if datetime.fromisoformat(data['ts']) > datetime.now() - timedelta(hours=6):
                return data
    except:
        pass
    return None

def cache_set(key, data):
    try:
        (CACHE / key).write_text(json.dumps({**data, "ts": datetime.now().isoformat()}))
    except Exception as e:
        log(f"Cache write error: {e}")

# Direct API calls
async def ask_perplexity(prompt, max_tokens=1000):
    cached = cache_get(cache_key(prompt))
    if cached:
        return cached, 0.0  # Free from cache
    
    if not await budget.check(0.01):
        return {"error": "Budget exceeded"}, 0.0
    
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            r = await client.post(
                "https://api.perplexity.ai/chat/completions",
                headers={"Authorization": f"Bearer {PERPLEXITY_KEY}"},
                json={
                    "model": "sonar-pro",
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": max_tokens
                }
            )
            data = r.json()
            tokens = data.get('usage', {}).get('total_tokens', max_tokens)
            cost = (tokens / 1000) * 0.005
            await budget.spend(cost)
            
            result = {
                "content": data['choices'][0]['message']['content'],
                "citations": data.get('citations', []),
                "cost": cost
            }
            cache_set(cache_key(prompt), result)
            return result, cost
    except Exception as e:
        return {"error": str(e)}, 0.0

async def ask_claude(prompt, max_tokens=1500):
    if not await budget.check(0.01):
        return {"error": "Budget exceeded"}, 0.0
    
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            r = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": ANTHROPIC_KEY,
                    "anthropic-version": "2023-06-01"
                },
                json={
                    "model": "claude-3-haiku-20240307",
                    "max_tokens": max_tokens,
                    "messages": [{"role": "user", "content": prompt}]
                }
            )
            data = r.json()
            cost = (data.get('usage', {}).get('input_tokens', 0) + 
                   data.get('usage', {}).get('output_tokens', 0)) / 1000 * 0.003
            await budget.spend(cost)
            
            return {
                "content": data['content'][0]['text'],
                "cost": cost
            }, cost
    except Exception as e:
        return {"error": str(e)}, 0.0

# AGENT DEFINITIONS
async def agent_threat_hunter():
    """Continuously hunts for CVEs and threats"""
    log("[AGENT] Threat Hunter initialized")
    
    while True:
        try:
            # Only run if budget allows
            if not await budget.check(0.01):
                log("[THREAT] Budget low, skipping scan")
                await asyncio.sleep(3600)
                continue
            
            result, cost = await ask_perplexity(
                "CVEs last 24h affecting: LangChain, Ollama, ChromaDB, Python docker. List CVSS >7.0 only.",
                max_tokens=800
            )
            
            if "error" in result:
                log(f"[THREAT] API error: {result['error']}")
                await asyncio.sleep(1800)
                continue
            
            content = result.get('content', '')
            citations = result.get('citations', [])
            
            # Auto-analysis: Is this critical?
            if any(x in content.lower() for x in ['critical', 'cve-2024', 'rce', 'remote code']):
                log(f"[THREAT ALERT] Critical CVE found! Citations: {len(citations)}")
                
                # Auto-generate fix via Claude
                fix_prompt = f"Generate Python code to mitigate this vulnerability: {content[:500]}"
                fix_result, fix_cost = await ask_claude(fix_prompt, max_tokens=1000)
                
                # Save fix to queue
                fix_file = QUEUE / f"security_fix_{int(datetime.now().timestamp())}.json"
                fix_file.write_text(json.dumps({
                    "type": "security",
                    "threat": content[:200],
                    "fix_code": fix_result.get('content', '# Error generating fix'),
                    "cost": cost + fix_cost
                }))
                
                log(f"[THREAT] Fix generated and queued: {fix_file.name}")
            else:
                log(f"[THREAT] Scan complete. No critical threats. Cost: ${cost:.3f}")
            
            # Wait 1 hour between scans
            await asyncio.sleep(3600)
            
        except Exception as e:
            log(f"[THREAT] Agent crashed: {e}")
            await asyncio.sleep(300)

async def agent_code_forger():
    """Continuously checks queue and builds tools"""
    log("[AGENT] Code Forger initialized")
    
    while True:
        try:
            # Check queue
            for req_file in QUEUE.glob("*.json"):
                try:
                    req = json.loads(req_file.read_text())
                    
                    if req.get('type') == 'security':
                        # Security fix - high priority
                        log(f"[FORGER] Processing security fix: {req_file.name}")
                        code = req.get('fix_code', '')
                    else:
                        # Regular build request
                        log(f"[FORGER] Building: {req.get('task', 'unknown')}")
                        result, cost = await ask_claude(
                            f"Python script: {req.get('task')}. Error handling. Only code.",
                            max_tokens=1500
                        )
                        code = result.get('content', '')
                    
                    # Clean code
                    if "```python" in code:
                        code = code.split("```python")[1].split("```")[0]
                    elif "```" in code:
                        code = code.split("```")[1].split("```")[0]
                    
                    # Validate (no shell escapes)
                    if 'subprocess' in code or 'os.system' in code:
                        log(f"[FORGER] WARNING: Blocked code with subprocess")
                        req_file.unlink()
                        continue
                    
                    # Save
                    out_file = ROOT / "src" / f"forged_{int(datetime.now().timestamp())}.py"
                    out_file.parent.mkdir(exist_ok=True)
                    out_file.write_text(code.strip())
                    
                    log(f"[FORGER] Built: {out_file.name}")
                    req_file.unlink()
                    
                except Exception as e:
                    log(f"[FORGER] Error processing {req_file.name}: {e}")
            
            await asyncio.sleep(10)
            
        except Exception as e:
            log(f"[FORGER] Agent crashed: {e}")
            await asyncio.sleep(30)

async def agent_system_guardian():
    """Monitors system health and auto-heals"""
    log("[AGENT] System Guardian initialized")
    
    while True:
        try:
            cpu = psutil.cpu_percent(interval=1)
            mem = psutil.virtual_memory().percent
            disk = psutil.disk_usage('C:/').percent
            
            # Log metrics
            if cpu > 80 or mem > 85:
                log(f"[GUARDIAN] HIGH LOAD: CPU {cpu}%, MEM {mem}%")
                
                # Auto-kill heavy processes if critical
                if cpu > 95:
                    log("[GUARDIAN] Critical CPU! Checking for runaway processes...")
                    # Could implement process killing here
            
            # Check if other agents are running (by checking log activity)
            log_stat = LOG_FILE.stat() if LOG_FILE.exists() else None
            if log_stat and (datetime.now().timestamp() - log_stat.st_mtime) > 600:
                log("[GUARDIAN] WARNING: No log activity for 10 minutes!")
            
            await asyncio.sleep(60)
            
        except Exception as e:
            log(f"[GUARDIAN] Error: {e}")
            await asyncio.sleep(60)

async def agent_archivist():
    """Manages memory and knowledge"""
    log("[AGENT] Archivist initialized")
    
    while True:
        try:
            # Rotate old cache files
            cutoff = datetime.now() - timedelta(days=7)
            for cache_file in CACHE.glob("*.json"):
                try:
                    data = json.loads(cache_file.read_text())
                    if datetime.fromisoformat(data['ts']) < cutoff:
                        cache_file.unlink()
                        log(f"[ARCHIVIST] Purged old cache: {cache_file.name}")
                except:
                    pass
            
            # Summarize daily logs if large
            if LOG_FILE.exists() and LOG_FILE.stat().st_size > 10_000_000:  # 10MB
                # Archive old logs
                archive_name = GHOST / f"overmind_archive_{datetime.now().strftime('%Y%m%d')}.log"
                LOG_FILE.rename(archive_name)
                log(f"[ARCHIVIST] Rotated logs to {archive_name}")
            
            await asyncio.sleep(3600)  # Hourly maintenance
            
        except Exception as e:
            log(f"[ARCHIVIST] Error: {e}")
            await asyncio.sleep(3600)

# MAIN ORCHESTRATOR
async def main():
    log("══════════════════════════════════════════════════")
    log("PROJECT OVERMIND — AUTONOMOUS SWARM ACTIVATED")
    log("══════════════════════════════════════════════════")
    log(f"Budget: $50/day | Cache: 6h TTL")
    log(f"Agents: ThreatHunter, CodeForger, Guardian, Archivist")
    log("══════════════════════════════════════════════════")
    
    # Spawn all agents concurrently
    await asyncio.gather(
        agent_threat_hunter(),
        agent_code_forger(),
        agent_system_guardian(),
        agent_archivist()
    )

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log("[OVERMIND] Shutdown requested")
    except Exception as e:
        log(f"[FATAL] {e}")
