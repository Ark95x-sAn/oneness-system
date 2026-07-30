# Rescore Net95x property operations board
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
cd $root

$cmd = @"
import json
from pathlib import Path
from datetime import date

today = date.today()
data = json.loads(Path(r'C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem\\memory\\vault\\1-Projects\\Net95xApp\\data.json').read_text(encoding='utf-8'))
props = {p['id']: p for p in data.get('PROPERTIES', [])}
wos = data.get('WORK_ORDERS', [])
c = data.get('HV_COSTS', {'rent_call':25,'re_list':600,'lease_renewal':150,'fix_high':700,'fix_med':300,'fix_low':120})
cf = {'high':c['fix_high'],'med':c['fix_med'],'low':c['fix_low']}

def pd(s):
    try: return date.fromisoformat(s)
    except: return None

mvs = []
def add(d): mvs.append(d)

for pid,p in props.items():
    if p.get('status') in ('late','plan'):
        cash = p.get('rent',0); cost = c['rent_call']; sc = cash / max(25,cost)
        add({'rank':None,'score':round(sc,1),'kind':'rent','id':'RENT-'+pid,'name':'Collect '+p.get('status')+' rent - '+p.get('tenant',''),'where':p.get('name')+' - '+p.get('addr')+' - rent $'+str(cash),'cash':cash,'cost':cost,'payback_days':round(cost/(cash/365)) if cash else None,'cta':'Call tenant today','why':'One-time recovery of $'+str(cash)})
    if p.get('status') == 'vacant':
        cash = p.get('rent',0)*12; cost = c['re_list']; sc = cash / max(25,cost)
        add({'rank':None,'score':round(sc,1),'kind':'vacant','id':'VACANT-'+pid,'name':'Re-list '+p.get('name',''),'where':p.get('name')+' - monthly $'+str(p.get('rent',0)),'cash':cash,'cost':cost,'payback_days':round(cost/(cash/365)) if cash else None,'cta':'Finish turn and list','why':'Annual run-rate $'+str(cash)})
    led = pd(p.get('leaseEnd'))
    if led and 0 <= (led-today).days <= 120:
        cash = p.get('rent',0)*12; cost = c['lease_renewal']; sc = cash / max(25,cost)
        add({'rank':None,'score':round(sc,1),'kind':'lease','id':'LEASE-'+pid,'name':'Renew lease - '+p.get('tenant',''),'where':p.get('name')+' - lease ends '+p.get('leaseEnd'),'cash':cash,'cost':cost,'payback_days':None,'cta':'Reach out for renewal','why':'Secure $'+str(cash)+' annual run-rate'})

for wo in wos:
    if wo.get('status') in ('open','working'):
        p = props.get(wo.get('prop')); cash = p.get('rent',0)*12 if p else 12000; pr = wo.get('priority','med'); cost = cf.get(pr,c['fix_med']); sc = cash / max(25,cost)
        where = (p.get('name') if p else wo.get('prop'))+' - '+wo.get('id')+' - '+pr+' - '+wo.get('status')
        add({'rank':None,'score':round(sc,1),'kind':'work','id':wo.get('id'),'name':wo.get('title'),'where':where,'cash':cash,'cost':cost,'payback_days':round(cost/(cash/365)) if cash else None,'cta':'Schedule fix','why':'Protect $'+str(cash)+' run-rate'})

mvs.sort(key=lambda x:x['score'], reverse=True)
for i,m in enumerate(mvs,1): m['rank']=i
hero_pull = sum(m['cash'] for m in mvs if m['kind']=='rent')
hero_arr = sum(m['cash'] for m in mvs if m['kind'] in ('vacant','lease')) + sum(p.get('rent',0)*12 for p in props.values())
res = {'today':today.isoformat(),'hero':{'cash_to_pull_this_month':hero_pull,'annual_run_rate':hero_arr,'moves_on_board':len(mvs)},'moves':mvs}
Path(r'C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem\\memory\\analysis\\net95x_hv_board.json').write_text(json.dumps(res,indent=2),encoding='utf-8')
print('rescored', len(mvs), 'moves')
"@

& "$root\venv\Scripts\python.exe" -c $cmd
