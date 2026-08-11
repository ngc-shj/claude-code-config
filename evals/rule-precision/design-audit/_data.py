"""Shared loaders for the design audit.

Inputs are PINNED. `inputs.sha1` lists every file this audit reads with its blob
hash at the base commit; `verify_inputs()` checks that the path set and the
hashes both still match before any number is produced. Globbing the adjudication
directories would otherwise let a later round's sheet change these results
silently.
"""
import csv, collections, glob, itertools, math, os, statistics as st
EVALS=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def _blob_sha1(path):
    data = open(path, 'rb').read()
    import hashlib
    return hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()


def verify_inputs():
    """Every pinned path exists with its pinned hash, and no extra sheet crept in."""
    man = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'inputs.sha1')
    want = {}
    for line in open(man):
        if line.startswith('#') or not line.strip():
            continue
        h, rel = line.split()
        want[rel] = h
    bad = []
    for rel, h in sorted(want.items()):
        full = os.path.join(EVALS, rel)
        if not os.path.exists(full):
            bad.append(f'MISSING  {rel}')
        elif _blob_sha1(full) != h:
            bad.append(f'CHANGED  {rel}')
    seen = {rel for rel in want if '/adjudications/' in rel}
    for d in {os.path.dirname(r) for r in seen}:
        on_disk = {f'{d}/{n}' for n in os.listdir(os.path.join(EVALS, d))
                   if n.endswith('.tsv')}
        for extra in sorted(on_disk - seen):
            bad.append(f'UNPINNED {extra}  (a sheet this audit was not written against)')
    if bad:
        raise SystemExit('input verification failed:\n  ' + '\n  '.join(bad)
                         + '\n\nThe audit reads a fixed set of files. Re-pin '
                           'inputs.sha1 and re-run every number if this is intended.')
    return len(want)


def verdicts(dirs, seed=None):
    out=dict(seed or {})
    for d in dirs:
        ps=sorted(glob.glob(os.path.join(d,'*.tsv')))
        if not ps: continue
        ss=[{r['cluster_id']:r['verdict'].strip() for r in csv.DictReader(open(p,newline=''),delimiter='\t')} for p in ps]
        for cid in ss[0]:
            out[cid]=collections.Counter(s.get(cid) for s in ss).most_common(1)[0][0]
    return out
def load(rd, verdict):
    f2c={}
    for r in csv.DictReader(open(f"{rd}/clusters.tsv",newline=''),delimiter='\t'):
        for fid in r['member_ids'].split(','): f2c[fid.strip()]=r['cluster_id']
    by=collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(list)))
    for f in csv.DictReader(open(f"{rd}/findings.tsv",newline=''),delimiter='\t'):
        by[f['arm']][int(f['review'])][f['part']].append(f)
    return f2c, by
def tcrit(df):
    T={1:12.706,2:4.303,4:2.776,6:2.447,8:2.306,10:2.228,12:2.179,14:2.145,16:2.120,
       20:2.086,24:2.064,28:2.048,30:2.042,40:2.021,48:2.011,60:2.000,80:1.990,120:1.980,1000:1.962}
    k=sorted(T)
    if df<=k[0]: return T[k[0]]
    if df>=k[-1]: return T[k[-1]]
    lo=max(x for x in k if x<=df); hi=min(x for x in k if x>=df)
    return T[lo] if lo==hi else T[lo]+(df-lo)/(hi-lo)*(T[hi]-T[lo])
def welch(a,b):
    na,nb=len(a),len(b); va,vb=st.variance(a),st.variance(b)
    se=math.sqrt(va/na+vb/nb); d=st.mean(a)-st.mean(b)
    df=(va/na+vb/nb)**2/((va/na)**2/(na-1)+(vb/nb)**2/(nb-1))
    t=tcrit(df); return d,se,df,d-t*se,d+t*se
ROUNDS={}
seed={r['cluster_id']:r['verdict'].strip() for r in
      csv.DictReader(open(f"{EVALS}/round-16/seed/inventory.tsv",newline=''),delimiter='\t')}
ROUNDS['round 20']=(f"{EVALS}/round-20",
    verdicts([f"{EVALS}/round-{n}/adjudications" for n in (17,18,19,20)], seed=seed), 9)
ROUNDS['round 21']=(f"{EVALS}/round-21", verdicts([f"{EVALS}/round-21/adjudications"]), 9)
ROUNDS['round 22']=(f"{EVALS}/round-22",
    verdicts([f"{EVALS}/round-21/adjudications", f"{EVALS}/round-22/adjudications"]), 25)
def series(name, arm, metric, parts=('a','b','c')):
    rd, verdict, n = ROUNDS[name]
    f2c, by = load(rd, verdict)
    return [metric([f for p in parts for f in by[arm][i][p]], f2c, verdict) for i in range(1,n+1)]
CM=lambda f: f['severity'] in ('Critical','Major')
PRIM=lambda fs,f2c,v: sum(1 for f in fs if CM(f) and v[f2c[f['id']]]=='not-a-defect')
REAL=lambda fs,f2c,v: len({f2c[f['id']] for f in fs if v[f2c[f['id']]]=='real'})
