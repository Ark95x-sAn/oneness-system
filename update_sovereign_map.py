"""Update the sovereign desktop system map and refresh the dashboard."""
import sys, json, datetime
sys.path.insert(0, r'C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\src')
from pathlib import Path
from sovereign_desktop.orchestrator import scan
from sovereign_desktop.refresh_dashboard import build_html

root = Path(r'C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem')
map_path = root / 'memory' / 'analysis' / 'sovereign_desktop_map.json'

map_data = json.loads(map_path.read_text(encoding='utf-8'))
apps = scan()
map_data['connector_matrix'] = apps
map_data['apps'] = {a['id']: a for a in apps}
map_data['generated_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
map_path.write_text(json.dumps(map_data, indent=2), encoding='utf-8')
build_html()
print(json.dumps({'status':'ok','apps':len(apps),'running':sum(1 for a in apps if a['running']),'detected':sum(1 for a in apps if a['detected'])}, indent=2))
