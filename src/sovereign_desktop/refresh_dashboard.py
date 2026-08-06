import json, datetime, glob
from pathlib import Path

root = Path(r'C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem')
map_path = root / 'memory' / 'analysis' / 'sovereign_desktop_map.json'
html_path = root / 'sovereign_commander.html'
template_path = root / 'src' / 'sovereign_desktop' / 'dashboard_template.html'
pipeline_dir = root / 'memory' / 'agency' / 'pipelines'

def load_recent_pipelines(limit=10):
    records = []
    if pipeline_dir.exists():
        for p in sorted(pipeline_dir.glob('*.json'), key=lambda x: x.stat().st_mtime, reverse=True):
            try:
                data = json.loads(p.read_text(encoding='utf-8'))
                records.append({
                    'id': data.get('id', p.stem),
                    'blueprint': data.get('blueprint'),
                    'status': data.get('status'),
                    'completed': data.get('completed'),
                })
            except Exception:
                continue
            if len(records) >= limit:
                break
    return records

def load_blueprints():
    try:
        result = __import__('subprocess').run(
            ['python', str(root / 'src' / 'agency_pipeline' / 'pipeline.py'), '--list'],
            capture_output=True, text=True, timeout=30, check=False
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception:
        pass
    return {}

def build_html(map_path_override=None, html_path_override=None):
    mp = Path(map_path_override) if map_path_override else map_path
    hp = Path(html_path_override) if html_path_override else html_path
    map_data = json.loads(mp.read_text(encoding='utf-8'))
    apps = map_data.get('connector_matrix', [])
    running = sum(1 for a in apps if a.get('running'))
    detected = sum(1 for a in apps if a.get('detected'))
    app_json = json.dumps(apps)
    assets_json = json.dumps(map_data.get('oneness_assets', {}))
    blueprints_json = json.dumps(load_blueprints())
    pipelines_json = json.dumps(load_recent_pipelines())

    if not template_path.exists():
        raise FileNotFoundError(f"Dashboard template not found: {template_path}")
    template = template_path.read_text(encoding='utf-8')
    html = (template
        .replace('{RUNNING}', str(running))
        .replace('{DETECTED}', str(detected))
        .replace('{APPS_JSON}', app_json)
        .replace('{ASSETS_JSON}', assets_json)
        .replace('{BLUEPRINTS_JSON}', blueprints_json)
        .replace('{PIPELINES_JSON}', pipelines_json)
        .replace('{GENERATED_AT}', datetime.datetime.now(datetime.timezone.utc).isoformat()))
    hp.write_text(html, encoding='utf-8')
    return hp

if __name__ == '__main__':
    p = build_html()
    print(json.dumps({'status':'ok','wrote':str(p)}, indent=2))