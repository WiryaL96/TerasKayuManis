"""Add a reviewed restaurant catalog through Supabase's server Data API.

Dry run: python scripts/import-menu.py
Apply:   python scripts/import-menu.py --apply --expected-project aiptdjypuccoakyfvdyl
Reads credentials from frontend/.env; never logs them. Existing products are
preserved. New categories stay hidden until all products and choices verify.
Backups and import results are written only to ignored .cache/menu-import/.
"""
import argparse
import json
from pathlib import Path
import re
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from deploy.render_env import parse_env

NAMESPACE = uuid.UUID('d770c254-e306-4e3d-aa93-d13426c6ecb2')
def stable_id(value):
    return str(uuid.uuid5(NAMESPACE, value))

def validate(data):
    cats = {c['slug'] for c in data['categories']}
    assert len(cats) == len(data['categories']), 'Duplicate category'
    assert len({p['slug'] for p in data['products']}) == len(data['products']), 'Duplicate product'
    for p in data['products']:
        assert p['category'] in cats and p['name'].strip()
        assert re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', p['slug'])
        assert type(p['price']) is int and 0 < p['price'] <= 100000000
        assert 1 <= p['source_page'] <= 15
        options = set()
        for v in p['variants']:
            assert (v['group_name'], v['name']) not in options
            options.add((v['group_name'], v['name']))
            assert type(v['price_modifier']) is int and v['price_modifier'] >= 0
        for a in p['addons']:
            assert a['name'].strip() and type(a['price']) is int and a['price'] > 0

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, default=ROOT/'data/menu-teraskayumanis-2026-10-12.json')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--expected-project')
    args = parser.parse_args()
    data = json.loads(args.data.read_text(encoding='utf-8'))
    validate(data)
    print(f"Validated {len(data['categories'])} categories, {len(data['products'])} products, "
          f"{sum(len(p['variants']) for p in data['products'])} variants; "
          f"{len(data['pending'])} pending entries.", flush=True)
    if not args.apply:
        return
    config = parse_env((ROOT/'frontend/.env').read_text(encoding='utf-8'))
    base = config['NUXT_SUPABASE_URL'].rstrip('/')
    if not args.expected_project or base != f'https://{args.expected_project}.supabase.co':
        raise ValueError('Expected project must match environment')
    key = config['NUXT_SUPABASE_SERVICE_KEY']
    def api(table, method='GET', rows=None, query='?select=*'):
        request = urllib.request.Request(base+'/rest/v1/'+table+query, method=method,
            data=json.dumps(rows).encode() if rows is not None else None,
            headers={'apikey': key, 'Authorization':'Bearer '+key,
                     'Content-Type':'application/json', 'Prefer':'return=representation'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read()
                return json.loads(body) if body else []
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'Catalog API HTTP {error.code} for {method} {table}') from None
    tables = ['categories','products','product_variants','addons','product_addons','settings']
    before = {t:api(t) for t in tables}
    cache = ROOT/'.cache/menu-import'
    cache.mkdir(parents=True,exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    (cache/f'backup-{stamp}.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    cats = {c['slug']:c for c in before['categories']}
    products = {p['slug']:p for p in before['products']}
    extras = {a['name']:a for a in before['addons']}
    existing_variants = {(v['product_id'],v['group_name'],v['name']):v for v in before['product_variants']}
    categories_to_add, products_to_add, variants_to_add, addons_to_add, links_to_add = [],[],[],[],[]
    existing_links = {(x['product_id'],x['addon_id']) for x in before['product_addons']}
    for c in data['categories']:
        if c['slug'] not in cats:
            row = dict(c,id=stable_id('category:'+c['slug']),is_active=False)
            cats[c['slug']] = row
            categories_to_add.append(row)
        elif cats[c['slug']]['name'] != c['name']:
            raise ValueError('Category slug conflict: '+c['slug'])
    for p in data['products']:
        fields = {k:p[k] for k in ['name','slug','description','price']}
        fields['category_id'] = cats[p['category']]['id']
        if p['slug'] in products:
            row = products[p['slug']]
            if any(row.get(k) != value for k,value in fields.items()):
                raise ValueError('Existing product differs; review manually: '+p['slug'])
        else:
            row = dict(fields,id=stable_id('product:'+p['slug']),is_available=True)
            products_to_add.append(row)
            products[p['slug']] = row
        for v in p['variants']:
            lookup = (row['id'],v['group_name'],v['name'])
            if lookup in existing_variants:
                if any(existing_variants[lookup].get(k) != value for k,value in v.items()):
                    raise ValueError('Existing variant differs: '+p['slug'])
            else:
                variants_to_add.append(dict(v,product_id=row['id'],is_available=True,
                    id=stable_id('variant:'+p['slug']+':'+v['group_name']+':'+v['name'])))
        for a in p['addons']:
            if a['name'] not in extras:
                addon = dict(a,id=stable_id('addon:'+a['name']),is_available=True)
                extras[a['name']] = addon
                addons_to_add.append(addon)
            elif extras[a['name']]['price'] != a['price']:
                raise ValueError('Existing addon price differs: '+a['name'])
            link = (row['id'],extras[a['name']]['id'])
            if link not in existing_links:
                links_to_add.append(dict(product_id=link[0],addon_id=link[1]))
                existing_links.add(link)
    for table,rows in [('categories',categories_to_add),('products',products_to_add),
                       ('product_variants',variants_to_add),('addons',addons_to_add),
                       ('product_addons',links_to_add)]:
        if rows:
            api(table,'POST',rows)
        print(f'{table}: {len(rows)} added',flush=True)
    current = {t:api(t) for t in tables}
    saved_products = {p['id']:p for p in current['products']}
    saved_variants = {(v['product_id'],v['group_name'],v['name']):v for v in current['product_variants']}
    saved_links = {(x['product_id'],x['addon_id']) for x in current['product_addons']}
    for p in data['products']:
        pid = products[p['slug']]['id']
        saved = saved_products[pid]
        assert all(saved[k]==p[k] for k in ['name','slug','price','description'])
        assert saved['category_id']==cats[p['category']]['id']
        for v in p['variants']:
            actual = saved_variants[(pid,v['group_name'],v['name'])]
            assert all(actual[k]==value for k,value in v.items())
        for a in p['addons']:
            assert (pid,extras[a['name']]['id']) in saved_links
    for c in data['categories']:
        cat = cats[c['slug']]
        # Activate only categories created by this importer, including a resumed import.
        if not cat['is_active'] and cat['id']==stable_id('category:'+c['slug']):
            api('categories','PATCH',{'is_active':True},query='?id=eq.'+cat['id'])
    after = {t:api(t) for t in tables}
    assert after['settings']==before['settings'], 'Unexpected settings change'
    (cache/f'result-{stamp}.json').write_text(json.dumps(after,indent=2),encoding='utf-8')
    print('Catalog verified and activated; existing products and settings preserved.',flush=True)

if __name__=='__main__':
    try:
        main()
    except Exception as error:
        # Omit tracebacks containing credentials or server response details.
        print(type(error).__name__+': '+str(error),file=sys.stderr)
        sys.exit(1)
