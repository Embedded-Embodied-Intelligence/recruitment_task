ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(b.shape); print(b.columns.tolist())
for c in b.columns:
    vc=b[c].value_counts()
    print('---',c,'nunique',b[c].nunique(),'empty',(b[c].str.strip()=='').sum())
    if b[c].nunique()<40: print(vc.to_dict())
    else: print(b[c].sample(15,random_state=1).tolist())
" ; echo; cat suppliers.csv; echo; cat maintenance.csv | awk -F, '{print $3}' | sort | uniq -c; grep -v mold_cleaning maintenance.csv; awk -F, 'NR>1{print $2}' maintenance.csv | sort | uniq -c

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup rows',len(d), 'ids',d.batch_id.nunique())
print(d.head(12).to_string())
# exact dups?
print('exact dup rows', b.duplicated().sum())
# how do dup pairs differ
diffcols={}
for bid,g in d.groupby('batch_id'):
    for c in b.columns:
        if g[c].nunique()>1: diffcols[c]=diffcols.get(c,0)+1
print(diffcols)
print(b.batch_id.str.match(r'^B-\d{5}$').value_counts())
print(b[~b.batch_id.str.match(r'^B-\d{5}$')].batch_id.head())
"

python3 -c "
import pandas as pd, re
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
def kind(s):
    if re.match(r'^\d{4}-\d{2}-\d{2}$',s): return 'iso'
    m=re.match(r'^(\d{2})/(\d{2})/(\d{4})$',s)
    if m:
        a,c=int(m.group(1)),int(m.group(2))
        if a>12: return 'DMY'
        if c>12: return 'MDY'
        return 'amb'
    return 'other:'+s
k=b.production_date.map(kind)
print(k.value_counts())
print(b[k.str.startswith('other')].production_date.unique()[:20])
print('shift raw', b['shift'].unique())
# mold temp distribution
mt=pd.to_numeric(b.mold_temp,errors='coerce')
print('mold nonnum',mt.isna().sum())
print(pd.cut(mt,[0,100,150,180,190,200,230,260,300,380,400,500,1000]).value_counts().sort_index())
print('hum', pd.to_numeric(b.humidity_pct,errors='coerce').describe())
print('hum empty', (b.humidity_pct=='').sum())
for c in ['machine_age_years','ambient_temp_c','cycle_time_s','units_produced','defective_units','qc_inspection_min']:
    x=pd.to_numeric(b[c],errors='coerce'); print(c,x.isna().sum(),x.describe()[['min','50%','max']].tolist())
"

cat > $TMPDIR/prep.py <<'EOF'
import pandas as pd, re, numpy as np
def parse_date(s):
    if re.match(r'^\d{4}-\d{2}-\d{2}$',s): return pd.Timestamp(s)
    a,c,y=s.split('/'); a,c=int(a),int(c)
    if a>12: return pd.Timestamp(int(y),c,a)
    if c>12: return pd.Timestamp(int(y),a,c)
    return None
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
b['date_raw']=b.production_date
b['date']=b.production_date.map(parse_date)
EOF
python3 -c "
import sys; sys.path.insert(0,'$TMPDIR')
exec(open('$TMPDIR/prep.py').read())
b['mt']=b.mold_temp.astype(float)
b['F']=b.mt>300
print(b.groupby('line').F.agg(['sum','mean']))
d=b[b.date.notna()].copy()
print(d.groupby(['line',d.date.dt.to_period('M')]).F.mean().unstack(0).round(2))
print(d[d.F].date.min(), d[d.F].date.max())
print(b[b.F & (b.line=='L1')].date.dropna().sort_values().head(3))
h=b.humidity_pct
print('hum values <0 or >100 or ==0:', h[(h.astype(float)<=0)].value_counts().head())
print(sorted(h.unique(), key=lambda x: float(x) if x else -999)[:8])
print(b.line.unique())
" 

python3 -c "
exec(open('$TMPDIR/prep.py').read())
b['mt']=b.mold_temp.astype(float)
l3=b[b.line=='L3']
print('L3 non-F rows:'); print(l3[l3.mt<=300][['date_raw','mold_temp']].head(30).to_string())
print(l3[l3.mt<=300].mt.describe())
b['mtC']=np.where(b.mt>300,(b.mt-32)*5/9,b.mt)
d=b[b.date.notna()]
print(d.groupby(['line',d.date.dt.to_period('M')]).mtC.mean().unstack(0).round(1))
print('hum blank', (b.humidity_pct.str.strip()=='').sum())
hh=pd.to_numeric(b.humidity_pct,errors='coerce')
print('hum <0:',(hh<0).sum(),' ==0:',(hh==0).sum(),' >100:',(hh>100).sum())
print(sorted(hh.dropna().unique())[:5], sorted(hh.dropna().unique())[-5:])
"

python3 -c "
exec(open('$TMPDIR/prep.py').read())
b['shift_n']=b['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
b['sup']=b.supplier_code.str.strip().str.upper()
cols=['batch_id','line','shift_n','operator_id','sup','machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
b['date_key']=b.date.dt.strftime('%Y-%m-%d').fillna(b.date_raw)
# content key ignoring date format but using row values as strings
print('raw exact dups', b.duplicated(subset=[c for c in b.columns if c not in ['date','date_key','shift_n','sup']]).sum())
print('normalised content dups (no date fmt):', b.duplicated(subset=['date_key']+cols).sum())
print('dup by batch_id+line', b.duplicated(['batch_id','line']).sum(), ' unique (batch_id,line)', b[['batch_id','line']].drop_duplicates().shape[0])
print('unique batch_id', b.batch_id.nunique())
u=b.drop_duplicates(subset=['date_key']+cols)
print('after content dedup',len(u),' unique (id,line)',u[['batch_id','line']].drop_duplicates().shape[0])
g=u[u.duplicated(['batch_id','line'],keep=False)].sort_values(['batch_id','line'])
print(len(g)); print(g[['batch_id','date_raw','line','shift','operator_id','sup','units_produced','defective_units','mold_temp']].head(20).to_string())
"

python3 -c "
exec(open('$TMPDIR/prep.py').read())
import itertools
# candidate dates for ambiguous rows
def cands(s):
    if re.match(r'^\d{4}-',s): return [pd.Timestamp(s)]
    a,c,y=map(int,s.split('/'))
    out=[]
    for m,dd in [(a,c),(c,a)]:
        try: out.append(pd.Timestamp(y,m,dd))
        except: pass
    return sorted(set(out))
lo,hi=pd.Timestamp('2025-01-06'),pd.Timestamp('2025-09-30')
b['cands']=b.date_raw.map(cands)
b['in']=b.cands.map(lambda L:[x for x in L if lo<=x<=hi])
print('n in-range candidates distribution', b['in'].map(len).value_counts().to_dict())
# unambiguous monotonic check
u=b[b.cands.map(len)==1].copy(); u['d']=u.cands.str[0]
print('file-order monotone (unambig):', (u.d.diff().dt.days.fillna(0)>=0).mean(), ' n',len(u))
print('out-of-order examples:'); print(u[u.d.diff().dt.days<0][['batch_id','date_raw']].head())
print(u.d.min(),u.d.max())
"

cat >> $TMPDIR/prep.py <<'EOF'
def _cands(s):
    if re.match(r'^\d{4}-',s): return [pd.Timestamp(s)]
    a,c,y=map(int,s.split('/'))
    out=[]
    for m,dd in [(a,c),(c,a)]:
        try: out.append(pd.Timestamp(y,m,dd))
        except ValueError: pass
    return sorted(set(out))
LO,HI=pd.Timestamp('2025-01-06'),pd.Timestamp('2025-09-30')
b['cands']=b.date_raw.map(_cands)
b['inr']=b.cands.map(lambda L:[x for x in L if LO<=x<=HI])
# neighbour anchor: median of unambiguous dates in a window of file rows
unamb=b.cands.map(len)==1
anchor=b['cands'].str[0].where(unamb)
anch=anchor.rolling(21,center=True,min_periods=3).median()
# for each row choose the in-range candidate closest to the local anchor
def pick(i):
    L=b.at[i,'inr']
    if len(L)==1: return L[0]
    if len(L)==0: return pd.NaT
    a=anch.iloc[i]
    return min(L,key=lambda x: abs((x-a).days))
b['date_fix']=[pick(i) for i in range(len(b))]
b['date_fix']=pd.to_datetime(b.date_fix)
EOF
python3 -c "
exec(open('$TMPDIR/prep.py').read())
print('no date:', b.date_fix.isna().sum())
amb=b.inr.map(len)==2
print('ambiguous both-in-range', amb.sum())
# decisiveness: gap in days between candidates and distance to anchor
x=b[amb].copy()
x['gap']=x.inr.map(lambda L:abs((L[1]-L[0]).days))
x['da']=[abs((r.date_fix-anch.iloc[i]).days) for i,r in x.iterrows()]
x['alt']=[abs(((L[0] if L[1]==r.date_fix else L[1])-anch.iloc[i]).days) for i,(L,r) in enumerate(zip(x.inr,x.itertuples()))] if False else None
print(x.gap.describe())
print('monotone check after fix', (b.sort_index().date_fix.diff().dt.days.fillna(0)>=-3).mean())
print(b.date_fix.dt.to_period('M').value_counts().sort_index())
"

python3 - <<'EOF'
import os
p=os.path.join(os.environ['TMPDIR'],'prep.py')
s=open(p).read()
s=s.replace("anchor=b['cands'].str[0].where(unamb)\nanch=anchor.rolling(21,center=True,min_periods=3).median()",
"anchor=b['cands'].str[0].where(unamb).map(lambda t: t.toordinal() if pd.notna(t) else np.nan)\nanch=anchor.rolling(21,center=True,min_periods=3).median()")
s=s.replace("    a=anch.iloc[i]\n    return min(L,key=lambda x: abs((x-a).days))",
"    a=anch.iloc[i]\n    return min(L,key=lambda x: abs(x.toordinal()-a))")
open(p,'w').write(s)
EOF
python3 -c "
exec(open('$TMPDIR/prep.py').read())
print('no date:', b.date_fix.isna().sum())
amb=b.inr.map(len)==2
print('ambiguous both-in-range', amb.sum())
print(b.date_fix.dt.to_period('M').value_counts().sort_index())
# sanity: fixed-date monotonic relative to file order
s=b.date_fix
print('share of rows within 3 days of prior row:', ((s.diff().dt.days.fillna(0)).abs()<=3).mean())
print('max jump', s.diff().dt.days.abs().max())
"

cat > $TMPDIR/clean.py <<'EOF'
import os, sys
sys.path.insert(0, os.environ['TMPDIR'])
exec(open(os.path.join(os.environ['TMPDIR'], 'prep.py')).read())
raw_n = len(b)
b['shift_n'] = b['shift'].str.strip().str.lower().map({'day': 'Day', 'd': 'Day', 'night': 'Night', 'n': 'Night'})
b['supplier_code_n'] = b.supplier_code.str.strip().str.upper()
num = ['machine_age_years', 'ambient_temp_c', 'mold_temp', 'humidity_pct', 'cycle_time_s',
       'units_produced', 'defective_units', 'qc_inspection_min', 'rework_cost_eur']
blank_as_nan = b[num].replace('', np.nan)
for c in num:
    b[c] = pd.to_numeric(blank_as_nan[c], errors='coerce')
b['date'] = b.date_fix
key = ['batch_id', 'line', 'date', 'shift_n', 'operator_id', 'supplier_code_n'] + num
b['is_dup'] = b.duplicated(subset=key, keep='first')
# mold temperature: L3 logs Fahrenheit, 0 means no reading
b['mold_temp_raw'] = b.mold_temp
b.loc[b.mold_temp == 0, 'mold_temp'] = np.nan
f = b.line.eq('L3') & (b.mold_temp > 300)
b.loc[f, 'mold_temp'] = (b.loc[f, 'mold_temp'] - 32) * 5 / 9
b['mold_F_converted'] = f
# humidity: negative values are sentinels, blanks are missing
b.loc[b.humidity_pct < 0, 'humidity_pct'] = np.nan
b['defect_rate'] = b.defective_units / b.units_produced
c = b[~b.is_dup].copy()
c.to_pickle(os.path.join(os.environ['TMPDIR'], 'clean.pkl'))
EOF
python3 -c "
import os,sys
exec(open(os.path.join(os.environ['TMPDIR'],'clean.py')).read())
print('raw',raw_n,'dups',b.is_dup.sum(),'clean',len(c))
print(c[num+['defect_rate']].describe().T.round(3).to_string())
print('defective>units', (c.defective_units>c.units_produced).sum())
print('shift', c.shift_n.value_counts(dropna=False).to_dict(), 'sup', c.supplier_code_n.value_counts().to_dict())
print('humidity missing', c.humidity_pct.isna().sum(), 'mold missing', c.mold_temp.isna().sum())
print('F converted', c.mold_F_converted.sum())
"

echo $TMPDIR && ls $TMPDIR | head && python3 -c "
import os,sys
exec(open(os.path.join(os.environ['TMPDIR'],'clean.py')).read())
print('raw',raw_n,'dups',b.is_dup.sum(),'clean',len(c))
print(c[num+['defect_rate']].describe().T.round(3).to_string())
print('defective>units', (c.defective_units>c.units_produced).sum())
print('shift', c.shift_n.value_counts(dropna=False).to_dict(), 'sup', c.supplier_code_n.value_counts().to_dict())
print('humidity missing', c.humidity_pct.isna().sum(), 'mold missing', c.mold_temp.isna().sum())
print('F converted', c.mold_F_converted.sum())
"

SP=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; mkdir -p $SP; ls -la $SP; ls -la $TMPDIR/prep.py $TMPDIR/clean.py 2>&1 | head

python3 /tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py

python3 /tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py && python3 -c "
import pandas as pd
c=pd.read_pickle('/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.pkl')
print('unique (id,line)', c[['batch_id','line']].drop_duplicates().shape[0])
print('A3 overall', c.defective_units.sum()/c.units_produced.sum())
print('A4 median mold C (valid)', c.mold_temp.dropna().median())
print('A2 humidity invalid (clean rows)', c.humidity_pct.isna().sum())
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import pandas as pd, numpy as np
c=pd.read_pickle('$S/clean.pkl')
c['post']=(c.line=='L1')&(c.date>='2025-04-14')
c['period']=np.where((c.line=='L1')&(c.date<'2025-04-14'),'L1 pre',np.where((c.line=='L1'),'L1 post','other'))
print(c.groupby(['period']).mold_temp.describe().round(2))
print(c.groupby('line').mold_temp.describe().round(2))
print(c.groupby(['line','mold_F_converted']).mold_temp.median())
print(c.groupby(['line',c.date.dt.month]).defect_rate.mean().unstack(0).round(4))
" && grep -n "" /tmp/edabench_claude_lq28c_fe/maintenance.csv | grep -E "L1" | head -30

python3 -c "import statsmodels, sklearn; print(statsmodels.__version__, sklearn.__version__)" 2>&1; S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad; python3 -c "
import pandas as pd
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
for l in ['L1','L2','L3','L4']:
    d=m[(m.line==l)].date.sort_values()
    print(l, [x.strftime('%m-%d') for x in d], 'max gap', d.diff().dt.days.max())
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
f='defect_rate ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift_n) + C(supplier_code_n) + C(line)'
m=smf.glm('defective_units + fail ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift_n) + C(supplier_code_n) + C(line)', data=c, family=sm.families.Binomial()).fit()
print(m.summary().tables[1])
" 2>&1 | head -60

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import pandas as pd, numpy as np
c=pd.read_pickle('$S/clean.pkl')
print(c[['defective_units','defect_rate','units_produced','qc_inspection_min','rework_cost_eur','cycle_time_s','mold_temp','humidity_pct','ambient_temp_c','machine_age_years']].corr(numeric_only=True).round(3).to_string())
print('rework/defect ratio', (c.rework_cost_eur/c.defective_units).describe().round(3).to_dict())
print('rework/units ratio', (c.rework_cost_eur/c.units_produced).describe().round(3).to_dict())
print(c.groupby(pd.qcut(c.defect_rate,5)).qc_inspection_min.mean())
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
mc=m[m.event=='mold_cleaning']
def dsc(r):
    d=mc[(mc.line==r.line)&(mc.date<=r.date)].date
    return (r.date-d.max()).days if len(d) else np.nan
c['dsc']=c.apply(dsc,axis=1)
print('dsc missing', c.dsc.isna().sum()); print(c.dsc.describe())
# qc inspection regression
q=smf.ols('qc_inspection_min ~ defective_units + units_produced + C(line)', data=c).fit()
print('qc R2 with defects', round(q.rsquared,3))
q2=smf.ols('qc_inspection_min ~ units_produced + C(line)', data=c).fit(); print('qc R2 w/o defects', round(q2.rsquared,3))
print(q.params.round(4).to_dict())
c.to_pickle('$S/clean2.pkl')
print(c.groupby(pd.cut(c.dsc,[-1,3,7,10,14,21,28,40,70])).defect_rate.agg(['mean','count']).round(4))
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
c['pre']=((c.line=='L1')&(c.date<'2025-04-14')).astype(int)
base='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift_n) + C(supplier_code_n) + C(line)'
m=smf.glm('defective_units + fail ~ '+base+' + dsc', data=c, family=sm.families.Binomial()).fit(scale='X2')
print(m.params.round(4).drop([p for p in m.params.index if 'operator' in p]).to_string())
print('pvalues:'); print(m.pvalues[['mold_temp','humidity_pct','cycle_time_s','machine_age_years','ambient_temp_c','C(shift_n)[T.Night]','dsc']].round(4).to_string())
print('op p-values range', m.pvalues[[p for p in m.params.index if 'operator' in p]].round(3).max())
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, patsy
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
base='mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift_n) + C(supplier_code_n) + C(line) + dsc'
X=patsy.dmatrix(base,c,return_type='dataframe')
print(X.shape, np.linalg.matrix_rank(X.values), X.columns.tolist()[:3])
print(pd.Series(np.linalg.svd(X.values,compute_uv=False)).tail(4).values)
print(c.groupby('line').supplier_code_n.value_counts().unstack().to_string())
print(pd.crosstab(c.supplier_code_n, c.line))
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, patsy
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
print(pd.crosstab(c.operator_id,c.line).to_string())
print(pd.crosstab(c.operator_id,c.shift_n).T.to_string())
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
terms={'mold_temp':'mold_temp','humidity_pct':'humidity_pct','cycle_time_s':'cycle_time_s','machine_age_years':'machine_age_years','ambient_temp_c':'ambient_temp_c','operator':'C(operator_id)','shift':'C(shift_n)','supplier':'C(supplier_code_n)','dsc':'dsc','line':'C(line)'}
allt=list(terms.values())
def fit(ts):
    f='defective_units + fail ~ '+(' + '.join(ts) if ts else '1')
    return smf.glm(f,data=c,family=sm.families.Binomial()).fit()
full=fit(allt); phi=full.pearson_chi2/full.df_resid
print('dispersion', round(phi,3))
for k,t in terms.items():
    if k=='line': continue
    r=fit([x for x in allt if x!=t])
    dev=(r.deviance-full.deviance)/phi; df=full.df_model-r.df_model
    print(f'{k:20s} dF={df:3.0f}  chi2={dev:9.2f}  p={stats.chi2.sf(dev,df):.2e}')
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
f='defective_units + fail ~ mold_temp + humidity_pct + cycle_time_s + machine_age_years + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line) + dsc'
for sc in [None,'X2']:
    m=smf.glm(f,data=c,family=sm.families.Binomial()).fit(scale=sc)
    print(sc); print(pd.DataFrame({'coef':m.params,'se':m.bse,'p':m.pvalues}).round(4).to_string())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
terms={'mold_temp':'mold_temp','humidity_pct':'humidity_pct','cycle_time_s':'cycle_time_s','machine_age_years':'machine_age_years','ambient_temp_c':'ambient_temp_c','shift':'C(shift_n)','supplier':'C(supplier_code_n)','dsc':'dsc','line':'C(line)','operator':'C(operator_id)'}
def fit(ts):
    return smf.glm('defective_units + fail ~ '+' + '.join(ts),data=c,family=sm.families.Binomial()).fit()
allt=[v for k,v in terms.items() if k!='operator']
full=fit(allt); phi=full.pearson_chi2/full.df_resid
print('phi (pearson/df)', round(phi,3), 'deviance/df', round(full.deviance/full.df_resid,3))
for k in terms:
    if k in ('line','operator'): continue
    r=fit([v for v in allt if v!=terms[k]])
    dev=(r.deviance-full.deviance)/phi; df=full.df_model-r.df_model
    print(f'{k:20s} dF={df:2.0f}  F-ish chi2={dev:8.2f}  p={stats.chi2.sf(dev,df):.3g}')
# operator within line, given rest
r=fit(allt+[terms['operator']])
dev=(full.deviance-r.deviance)/phi; print('operator add-on: ', round(dev,2), stats.chi2.sf(dev, r.df_model-full.df_model))
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
f='defective_units + fail ~ mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line) + dsc'
m=smf.glm(f,data=c,family=sm.families.Binomial()).fit()
c['exp']=m.predict(c)*c.units_produced
c['obs']=c.defective_units
c['month']=c.date.dt.to_period('M')
g=c.groupby(['line','month'])[['obs','exp']].sum()
g['ratio']=(g.obs/g.exp).round(2)
print(g.ratio.unstack(0).to_string())
print(c.groupby('line')[['machine_age_years']].mean().round(2))
print(c.groupby('line').apply(lambda d: pd.Series({'dsc_mean':d.dsc.mean(),'n':len(d)})))
print(pd.Series(m.resid_pearson).describe())
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
f='defective_units + fail ~ mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line) + dsc'
m=smf.glm(f,data=c,family=sm.families.Binomial()).fit()
c['r']=m.resid_pearson
for line in ['L1','L2','L3','L4']:
    d=c[c.line==line].sort_values('date')
    best=None
    for dt in pd.date_range('2025-02-01','2025-09-01',freq='D'):
        a=d[d.date<dt].r; bb=d[d.date>=dt].r
        if len(a)<40 or len(bb)<40: continue
        t=(bb.mean()-a.mean())/np.sqrt(a.var()/len(a)+bb.var()/len(bb))
        if best is None or abs(t)>abs(best[1]): best=(dt.date(),t,a.mean().round(2),bb.mean().round(2))
    print(line,best)
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
c['pre']=((c.line=='L1')&(c.date<'2025-04-14')).astype(int)
c['dscb']=pd.cut(c.dsc,[-1,3,7,10,14,21,28,40,70]).astype(str)
base='mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line)'
for lab,f in [('linear dsc','dsc'),('binned dsc','C(dscb)')]:
    m=smf.glm('defective_units + fail ~ '+base+' + '+f,data=c,family=sm.families.Binomial()).fit()
    c['r']=m.resid_pearson
    print(lab, 'dev/df',round(m.deviance/m.df_resid,2))
    for line in ['L1','L2','L3','L4']:
        d=c[c.line==line].sort_values('date'); best=None
        for dt in pd.date_range('2025-02-01','2025-09-01',freq='D'):
            a=d[d.date<dt].r; bb=d[d.date>=dt].r
            if len(a)<40 or len(bb)<40: continue
            t=(bb.mean()-a.mean())/np.sqrt(a.var()/len(a)+bb.var()/len(bb))
            if best is None or abs(t)>abs(best[1]): best=(str(dt.date()),round(t,2))
        print('  ',line,best)
# L1 pre offset: add pre dummy
m2=smf.glm('defective_units + fail ~ '+base+' + dsc + pre',data=c,family=sm.families.Binomial()).fit()
print('pre coef',round(m2.params['pre'],4),'se',round(m2.bse['pre'],4),'mold coef',round(m2.params['mold_temp'],5))
print('implied offset C', round(m2.params['pre']/m2.params['mold_temp'],2), 'z',round(m2.tvalues['pre'],2))
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np
c=pd.read_pickle('$S/clean2.pkl').copy()
brk={'L2':'2025-06-15','L3':'2025-07-21'}
for L,dt in brk.items():
    d=c[c.line==L].copy(); d['post']=d.date>=dt
    print('=====',L,dt)
    print(d.groupby('post')[['mold_temp','humidity_pct','cycle_time_s','ambient_temp_c','machine_age_years','units_produced','dsc','qc_inspection_min','defect_rate']].mean().round(3).T.to_string())
    print(pd.crosstab(d.post,d.supplier_code_n,normalize='index').round(3))
    print(pd.crosstab(d.post,d.shift_n,normalize='index').round(3))
" 

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf
c=pd.read_pickle('$S/clean2.pkl').copy()
for L,dt in [('L2','2025-06-15'),('L3','2025-07-21')]:
    d=c[c.line==L].copy(); d['post']=(d.date>=dt).astype(int)
    m=smf.ols('qc_inspection_min ~ defective_units*post + units_produced',data=d).fit()
    print(L, m.params.round(4).to_dict()); print('  p post', round(m.pvalues['post'],4))
    m0=smf.ols('qc_inspection_min ~ defective_units + units_produced',data=d[d.post==0]).fit()
    m1=smf.ols('qc_inspection_min ~ defective_units + units_produced',data=d[d.post==1]).fit()
    print('  pre fit', m0.params.round(4).to_dict(), 'mean qc', round(d[d.post==0].qc_inspection_min.mean(),2))
    print('  post fit', m1.params.round(4).to_dict(), 'mean qc', round(d[d.post==1].qc_inspection_min.mean(),2))
# batch-by-batch qc pattern around the L3 break
d=c[(c.line=='L3')].sort_values('date')
print(d[(d.date>='2025-07-15')&(d.date<='2025-07-28')][['date','defective_units','qc_inspection_min','units_produced']].to_string())
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
base='mold_temp + humidity_pct + cycle_time_s + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line) + dsc'
m=smf.glm('defective_units + fail ~ '+base,data=c,family=sm.families.Binomial()).fit()
c['r']=m.resid_pearson
l2=c[(c.line=='L2')].sort_values('date')
print(l2[(l2.date>='2025-06-09')&(l2.date<='2025-06-22')].groupby('date').agg(n=('r','size'),r=('r','mean'),dsc=('dsc','mean')).round(2).to_string())
# is the L2 jump explained at equal cleaning age?
l2=l2.assign(post=l2.date>='2025-06-15')
print('L2 mean resid by cleaning age, pre vs post'); print(l2.assign(age=pd.cut(l2.dsc,[-1,7,14,70])).groupby(['age','post']).r.agg(['mean','size']).round(2))
# L2 post dummy in model
m2=smf.glm('defective_units + fail ~ '+base+' + post',data=l2.assign(post=l2.post.astype(int)).rename(columns={}),family=sm.families.Binomial()).fit() if False else None
c['L2post']=((c.line=='L2')&(c.date>='2025-06-15')).astype(int)
m2=smf.glm('defective_units + fail ~ '+base+' + L2post',data=c,family=sm.families.Binomial()).fit()
print('L2post coef',round(m2.params['L2post'],3),'se',round(m2.bse['L2post'],3),'implied temp offset C',round(m2.params['L2post']/m2.params['mold_temp'],2))
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf
c=pd.read_pickle('$S/clean2.pkl').copy()
c['pre']=((c.line=='L1')&(c.date<'2025-04-14')).astype(int)
d=c.dropna(subset=['mold_temp','humidity_pct'])
for f in ['mold_temp ~ ambient_temp_c + C(line) + pre','mold_temp ~ ambient_temp_c + cycle_time_s + humidity_pct + C(shift_n) + C(line) + pre','mold_temp ~ ambient_temp_c + cycle_time_s + C(line) + C(shift_n) + C(supplier_code_n) + pre + dsc']:
    m=smf.ols(f,data=d).fit()
    print(round(m.params['pre'],2), '+-', round(m.bse['pre'],2), '| R2', round(m.rsquared,3), '|', f)
# only L1 around the swap
e=c[(c.line=='L1')]
m=smf.ols('mold_temp ~ ambient_temp_c + cycle_time_s + C(shift_n) + pre',data=e.dropna(subset=['mold_temp'])).fit()
print('L1 only pre offset', round(m.params['pre'],2), round(m.bse['pre'],2))
print(c.groupby(['line', c.date>='2025-04-14']).ambient_temp_c.mean().round(2))
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
c['pre']=((c.line=='L1')&(c.date<'2025-04-14')).astype(int)
base='humidity_pct + cycle_time_s + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line) + dsc'
for off in [0,6.4,12.8]:
    c['mc']=c.mold_temp+off*c.pre
    m=smf.glm('defective_units + fail ~ mc + '+base+' + pre',data=c,family=sm.families.Binomial()).fit()
    print('offset',off,'pre coef',round(m.params['pre'],3),'z',round(m.tvalues['pre'],2),'mc coef',round(m.params['mc'],4),'dev/df',round(m.deviance/m.df_resid,2))
# shape check: mold ~ ambient slope equal pre vs post in L1 and others
e=c.copy()
m=smf.ols('mold_temp ~ ambient_temp_c*pre + C(line)',data=e).fit()
print(m.params.round(3).to_dict())
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['humidity_pct','mold_temp']).copy()
c['fail']=c.units_produced-c.defective_units
c['pre']=((c.line=='L1')&(c.date<'2025-04-14')).astype(int)
c['L2post']=((c.line=='L2')&(c.date>='2025-06-15')).astype(int)
c['L3post']=((c.line=='L3')&(c.date>='2025-07-21')).astype(int)
base='humidity_pct + cycle_time_s + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line) + dsc + L2post + L3post'
for off in [0,6.4,12.8]:
    c['mc']=c.mold_temp+off*c.pre
    for form in ['mc','mc + I(mc**2)','bs(mc,df=4)']:
        if 'bs' in form:
            import patsy
            m=smf.glm('defective_units + fail ~ '+form.replace('bs(mc,df=4)','bs(mc, df=4)')+' + '+base+' + pre',data=c,family=sm.families.Binomial()).fit() if False else None
            continue
        m=smf.glm('defective_units + fail ~ '+form+' + '+base+' + pre',data=c,family=sm.families.Binomial()).fit()
        print('off',off,'|',form,'| pre',round(m.params['pre'],3),'z',round(m.tvalues['pre'],2),'| dev/df',round(m.deviance/m.df_resid,2))
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -c "
import pandas as pd, numpy as np
c=pd.read_pickle('$S/clean2.pkl')
pre=((c.line=='L1')&(c.date<'2025-04-14'))
for off in [0,6.4,9.6,12.8]:
    mt=c.mold_temp+off*pre
    print(off, round(mt.dropna().median(),3), mt.notna().sum())
print('raw F-as-is median', c.mold_temp_raw.replace(0,np.nan).dropna().median())
print('pre rows with valid temp', (pre & c.mold_temp.notna()).sum())
"

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['mold_temp']).copy()
c['pre']=((c.line=='L1')&(c.date<'2025-04-14')).astype(int)
m=smf.ols('mold_temp ~ ambient_temp_c + cycle_time_s + C(shift_n) + C(supplier_code_n) + C(line) + pre',data=c).fit()
print('pre offset (C)', round(m.params['pre'],2), round(m.bse['pre'],2))
c['r']=m.resid
for line in ['L1','L2','L3','L4']:
    d=c[c.line==line].sort_values('date'); best=None
    for dt in pd.date_range('2025-02-01','2025-09-01',freq='D'):
        a=d[d.date<dt].r; b=d[d.date>=dt].r
        if len(a)<40 or len(b)<40: continue
        t=(b.mean()-a.mean())/np.sqrt(a.var()/len(a)+b.var()/len(b))
        if best is None or abs(t)>abs(best[1]): best=(str(dt.date()),round(t,2),round(a.mean(),2),round(b.mean(),2))
    print('mold resid break',line,best)
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np
c=pd.read_pickle('$S/clean2.pkl').copy()
l3=c[c.line=='L3'].sort_values('date')
l3['raw']=l3.mold_temp_raw
print(l3.groupby(l3.date>='2025-05-19').agg(raw_med=('raw','median'),raw_min=('raw','min'),raw_max=('raw','max'),conv_med=('mold_temp','median'),ambient=('ambient_temp_c','mean'),n=('raw','size')).round(2))
print(l3[(l3.date>='2025-05-10')&(l3.date<='2025-05-25')][['date','raw','mold_temp','ambient_temp_c','shift_n']].head(30).to_string())
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import pandas as pd, numpy as np, statsmodels.formula.api as smf
c=pd.read_pickle('$S/clean2.pkl').dropna(subset=['mold_temp']).copy()
c['pre']=((c.line=='L1')&(c.date<'2025-04-14')).astype(int)
c['L3mold']=((c.line=='L3')&(c.date>='2025-05-19')).astype(int)
for f in ['mold_temp ~ ambient_temp_c + cycle_time_s + C(shift_n) + C(supplier_code_n) + C(line) + pre + L3mold',
          'mold_temp ~ ambient_temp_c*C(line) + cycle_time_s + C(shift_n) + C(supplier_code_n) + pre + L3mold']:
    m=smf.ols(f,data=c).fit(); print(round(m.params['pre'],2), round(m.bse['pre'],2), round(m.rsquared,3))
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from model import *
c=load(); d=c.dropna(subset=['humidity_pct','mold_c'])
full=fit(c); phi=full.pearson_chi2/full.df_resid
print('dev/df',round(full.deviance/full.df_resid,2),'pearson/df',round(phi,2))
print(full.summary2().tables[1].round(4).to_string())
tests={'mold_c':'mold_c','humidity_pct':'humidity_pct','cycle_time_s':'cycle_time_s','machine_age_years':'machine_age_years','ambient_temp_c':'ambient_temp_c','shift':'C(shift_n)','supplier':'C(supplier_code_n)','dsc':'dsc'}
base=MODEL_TERMS+' + machine_age_years'
fa=fit(c,base)
for k,t in tests.items():
    if k=='machine_age_years': r=fit(c,MODEL_TERMS)
    else:
        r=fit(c,' + '.join([x for x in base.split(' + ') if x!=t and not (x.startswith(t) if t.startswith('C(') else False)]))
    dev=(r.deviance-fa.deviance)/phi if k!='machine_age_years' else (r.deviance-full.deviance)/phi
    df=(fa.df_model-r.df_model) if k!='machine_age_years' else (full.df_model-r.df_model)
    print(f'{k:20s} dF={df:.0f} chi2={dev:9.2f} p={stats.chi2.sf(dev,df):.3g}')
# operator within line
fo=fit(c,MODEL_TERMS.replace('C(line)','C(operator_id)'))
dev=(fo.deviance-full.deviance)/phi; df=full.df_model-fo.df_model
print('operator (nested in line) dF', df, 'p', stats.chi2.sf(dev,df) if False else None)
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
import model
from model import *
c=load()
terms=MODEL_TERMS.replace('+ dsc','+ dsc')
rows=[]
for off in np.arange(0,16.1,1.0):
    c['mc']=c.mold_temp+off*c.pre
    d=c.dropna(subset=['humidity_pct','mold_temp'])
    m=smf.glm('defective_units + fail ~ mc + humidity_pct + cycle_time_s + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line) + dsc + L2post + L3post',data=d,family=sm.families.Binomial()).fit()
    m2=smf.glm('defective_units + fail ~ mc + humidity_pct + cycle_time_s + C(shift_n) + C(supplier_code_n) + C(line) + dsc + L2post + L3post',data=d,family=sm.families.Binomial()).fit()
    rows.append((off, round(m.deviance,1), round(m.params['ambient_temp_c'],4), round(m.tvalues['ambient_temp_c'],2), round(m.params['mc'],4), round(m2.deviance-m.deviance,2)))
print(pd.DataFrame(rows,columns=['off','dev','amb_coef','amb_z','mold_coef','dev_gain_from_ambient']).to_string())
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from model import *
c=load()
d0=c.dropna(subset=['humidity_pct','mold_temp']).copy()
best=None
res=[]
for off in np.arange(7.0,9.51,0.25):
    d=d0.copy(); d['mc']=d.mold_temp+off*d.pre
    m=smf.glm('defective_units + fail ~ mc + humidity_pct + cycle_time_s + ambient_temp_c + C(shift_n) + C(supplier_code_n) + C(line) + dsc + L2post + L3post',data=d,family=sm.families.Binomial()).fit()
    res.append((off,round(m.deviance,2)))
print(res)
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && sed -i 's/^OFFSET = 7.7 .*/OFFSET = 8.4  # L1 mold sensor bias before 2025-04-14 (C), profile-likelihood estimate/' $S/model.py && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from model import *
c=load()
base=MODEL_TERMS
full=fit(c,base); phi=full.pearson_chi2/full.df_resid
print('dev/df',round(full.deviance/full.df_resid,2),'phi',round(phi,2))
def test(name, terms_reduced, terms_full=base):
    f=fit(c,terms_full); r=fit(c,terms_reduced)
    dev=(r.deviance-f.deviance)/phi; df=f.df_model-r.df_model
    print(f'{name:20s} dF={df:.0f} chi2={dev:8.2f} p={stats.chi2.sf(dev,df):.4g}')
def drop(term): return ' + '.join([t for t in base.split(' + ') if t!=term])
test('mold_c', drop('mold_c'))
test('humidity_pct', drop('humidity_pct'))
test('cycle_time_s', drop('cycle_time_s'))
test('ambient_temp_c', drop('ambient_temp_c'))
test('shift', drop('C(shift_n)'))
test('dsc', drop('dsc'))
test('supplier', drop('C(supplier_code_n)'))
# machine age added to base
test('machine_age (added)', base, base+' + machine_age_years')
# operator nested within line: replace line dummies by operator dummies
op=base.replace('C(line)','C(operator_id)')
test('operator (in place of line)', base.replace('C(line)','C(line)') , op) if False else None
fo=fit(c,op); r=fit(c,base)
print('operator-within-line vs line-only: dF',fo.df_model-r.df_model,'chi2',round((r.deviance-fo.deviance)/phi,2),'p',round(stats.chi2.sf((r.deviance-fo.deviance)/phi,fo.df_model-r.df_model),4))
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from model import *
c=load().dropna(subset=['humidity_pct','mold_c'])
base=MODEL_TERMS
f0=fit(c,base); phi=f0.pearson_chi2/f0.df_resid
def cmp(name, t):
    f=fit(c,t); dev=(f0.deviance-f.deviance)/phi if False else (f.deviance-f0.deviance)  # gain
    print(name, 'deviance gain', round(f0.deviance-f.deviance,2), 'dF', f.df_model-f0.df_model, 'chi2/phi', round((f0.deviance-f.deviance)/phi,2), 'p', round(stats.chi2.sf((f0.deviance-f.deviance)/phi, f.df_model-f0.df_model),4))
cmp('humidity quad', base+' + I(humidity_pct**2)')
cmp('humidity x supplier', base+' + humidity_pct:C(supplier_code_n)')
cmp('cycle x supplier', base+' + cycle_time_s:C(supplier_code_n)')
cmp('mold x supplier', base+' + mold_c:C(supplier_code_n)')
cmp('humidity x shift', base+' + humidity_pct:C(shift_n)')
cmp('mold x line', base+' + mold_c:C(line)')
cmp('humidity x mold', base+' + humidity_pct:mold_c')
f1=fit(c,base+' + I(humidity_pct**2)')
print(f1.params[['humidity_pct','I(humidity_pct ** 2)']].round(5).to_dict(), f1.pvalues[['I(humidity_pct ** 2)']].round(4).to_dict())
fi=fit(c,base+' + humidity_pct:C(supplier_code_n)')
print(fi.params.filter(like='humidity').round(5).to_dict())
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from model import *
c=load().dropna(subset=['humidity_pct','mold_c'])
c['hb']=pd.cut(c.humidity_pct,[10,15,20,25,30,35,40,45,50,55,60,65,75])
t=c.groupby(['hb','supplier_code_n'],observed=True).apply(lambda d: pd.Series({'rate':d.defective_units.sum()/d.units_produced.sum(),'n':len(d)})).unstack()
print(t.round(4).to_string())
print(c.groupby('hb',observed=True).apply(lambda d: d.defective_units.sum()/d.units_produced.sum()).round(4).to_string())
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from model import *
c=load().dropna(subset=['humidity_pct','mold_c'])
cont=['mold_c','humidity_pct','cycle_time_s','ambient_temp_c','machine_age_years','dsc']
rest='C(shift_n) + C(supplier_code_n) + C(line) + L2post + L3post'
def spl(v,df=5): return f'bs({v}, df={df})'
full_t=' + '.join(spl(v) for v in cont)+' + '+rest
f=smf.glm('defective_units + fail ~ '+full_t,data=c,family=sm.families.Binomial()).fit()
phi=f.pearson_chi2/f.df_resid
print('spline model dev/df',round(f.deviance/f.df_resid,2),'phi',round(phi,2))
for v in cont:
    rt=' + '.join([spl(x) if x!=v else f'{x}' for x in cont])+' + '+rest
    r=smf.glm('defective_units + fail ~ '+rt,data=c,family=sm.families.Binomial()).fit()
    dev=(r.deviance-f.deviance)/phi; df=f.df_model-r.df_model
    print(f'{v:18s} (spline) dF={df:.0f} chi2={dev:8.2f} p={stats.chi2.sf(dev,df):.4g}')
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from model import *
c=load().dropna(subset=['humidity_pct','mold_c'])
cont=['mold_c','humidity_pct','cycle_time_s','ambient_temp_c','machine_age_years','dsc']
rest=['C(shift_n)','C(supplier_code_n)','C(line)','L2post','L3post']
def spl(v,df=5): return f'bs({v}, df={df})'
def build(drop_terms, extra=[]):
    parts=[]
    for v in cont:
        if v in drop_terms: continue
        parts.append(spl(v))
    for r in rest:
        if r in drop_terms: continue
        parts.append(r)
    return ' + '.join(parts+extra)
full=smf.glm('defective_units + fail ~ '+build([]),data=c,family=sm.families.Binomial()).fit()
phi=full.pearson_chi2/full.df_resid
print('phi',round(phi,2))
for v in cont+['C(shift_n)','C(supplier_code_n)','C(line)']:
    key=v if v in cont else v
    r=smf.glm('defective_units + fail ~ '+build([key]),data=c,family=sm.families.Binomial()).fit()
    dev=(r.deviance-full.deviance)/phi; df=full.df_model-r.df_model
    print(f'drop {key:22s} dF={df:.0f} chi2={dev:9.2f} p={stats.chi2.sf(dev,df):.3g}')
# operator within line
ops=build(['C(line)'],extra=['C(operator_id)'])
o=smf.glm('defective_units + fail ~ '+ops,data=c,family=sm.families.Binomial()).fit()
dev=(o.deviance-full.deviance)/phi; df=o.df_model-full.df_model
print('operator add (nested, line removed) dF',df,'chi2',round(-dev,2) if False else round(dev,2),'p', round(stats.chi2.sf(abs(dev),abs(df)),4))
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from model import *
c=load().dropna(subset=['humidity_pct','mold_c'])
cont=['mold_c','humidity_pct','cycle_time_s','ambient_temp_c','dsc']
core=' + '.join([f'bs({v}, df=5)' for v in cont])+' + C(shift_n) + C(supplier_code_n) + L2post + L3post'
fl=smf.glm('defective_units + fail ~ '+core+' + C(line)',data=c,family=sm.families.Binomial()).fit()
fo=smf.glm('defective_units + fail ~ '+core+' + C(operator_id)',data=c,family=sm.families.Binomial()).fit()
phi=fl.pearson_chi2/fl.df_resid
dev=(fl.deviance-fo.deviance)/phi; df=fo.df_model-fl.df_model
print('operator vs line, dF',df,'chi2',round(dev,2),'p',round(stats.chi2.sf(dev,df),4))
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > $S/final.py <<'EOF'
import sys
sys.path.insert(0, '/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
from model import *

CORE = ('bs(mold_c, df=5) + bs(humidity_pct, df=6) + bs(cycle_time_s, df=5) + bs(ambient_temp_c, df=4) '
        '+ bs(dsc, df=6) + C(shift_n) + C(supplier_code_n) + C(line) + L2post + L3post')


def final_fit(c, extra=''):
    return smf.glm('defective_units + fail ~ ' + CORE + extra, data=c, family=sm.families.Binomial()).fit()


def get_data():
    return load().dropna(subset=['humidity_pct', 'mold_c']).copy()
EOF
python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from final import *
c=get_data()
f0=final_fit(c); phi=f0.pearson_chi2/f0.df_resid
f1=final_fit(c,' + humidity_pct:C(supplier_code_n)')
f2=final_fit(c,' + bs(humidity_pct, df=6):C(supplier_code_n)') if False else None
dev=(f0.deviance-f1.deviance)/phi; df=f1.df_model-f0.df_model
print('humidity x supplier (linear) chi2',round(dev,2),'df',df,'p',round(stats.chi2.sf(dev,df),4), 'phi', round(phi,2))
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from final import *
c=get_data()
core2=CORE.replace('bs(humidity_pct, df=6) + ','')
f0=smf.glm('defective_units + fail ~ '+core2+' + bs(humidity_pct, df=6)',data=c,family=sm.families.Binomial()).fit()
f1=smf.glm('defective_units + fail ~ '+core2+' + bs(humidity_pct, df=6) * C(supplier_code_n)',data=c,family=sm.families.Binomial()).fit()
phi=f1.pearson_chi2/f1.df_resid
dev=(f0.deviance-f1.deviance)/phi; df=f1.df_model-f0.df_model
print('supplier-specific humidity curves: chi2',round(dev,2),'df',df,'p',round(stats.chi2.sf(dev,df),4),'phi',round(phi,2))
print('f1 dev/df', round(f1.deviance/f1.df_resid,3))
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat > $S/cf.py <<'EOF'
import sys
sys.path.insert(0, '/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad')
from model import *

CORE2 = ('bs(mold_c, df=5) + bs(cycle_time_s, df=5) + bs(ambient_temp_c, df=4) + bs(dsc, df=6) '
         '+ C(shift_n) + C(supplier_code_n) + C(line) + L2post + L3post')
FORM = 'defective_units + fail ~ ' + CORE2 + ' + bs(humidity_pct, df=6) * C(supplier_code_n)'


def fit_model(d):
    return smf.glm(FORM, data=d, family=sm.families.Binomial()).fit()


def prep():
    c = load().copy()
    # impute missing humidity / mold with line x supplier medians (counterfactual rows only)
    c['humidity_imp'] = c.humidity_pct.fillna(c.groupby(['line', 'supplier_code_n']).humidity_pct.transform('median'))
    c['mold_imp'] = c.mold_c.fillna(c.groupby('line').mold_c.transform('median'))
    return c


if __name__ == '__main__':
    c = prep()
    cc = c.dropna(subset=['humidity_pct', 'mold_c']).copy()
    m = fit_model(cc)
    print('dev/df', round(m.deviance / m.df_resid, 3))
    cc['humidity_pct_m'] = cc.humidity_pct
    # ---- C2: Alpha humidity optimum
    alpha = c[c.supplier_code_n == 'SP-01'].copy()
    grid = np.round(np.arange(12.1, 72.31, 0.1), 2)
    rows = []
    for h in grid:
        a = alpha.copy()
        a['humidity_pct'] = h
        a['mold_c'] = a.mold_imp
        p = m.predict(a)
        exp_rate_w = (p * a.units_produced).sum() / a.units_produced.sum()
        exp_rate_u = p.mean()
        rows.append((h, exp_rate_w, exp_rate_u))
    g = pd.DataFrame(rows, columns=['h', 'w', 'u'])
    print('C2 alpha optimum (unit-weighted):', g.loc[g.w.idxmin(), 'h'], round(g.w.min(), 5))
    print('C2 alpha optimum (batch-mean):   ', g.loc[g.u.idxmin(), 'h'], round(g.u.min(), 5))
    print(g.iloc[::50].round(5).to_string())
EOF
python3 -W ignore $S/cf.py 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from cf import *
c=prep(); cc=c.dropna(subset=['humidity_pct','mold_c']).copy()
alpha=c[c.supplier_code_n=='SP-01'].copy()
grid=np.round(np.arange(12.1,72.31,0.1),2)
def opt(form):
    m=smf.glm(form,data=cc,family=sm.families.Binomial()).fit()
    a=alpha.copy(); best=None; curve=[]
    for h in grid:
        a['humidity_pct']=h; a['mold_c']=a.mold_imp
        p=m.predict(a); v=(p*a.units_produced).sum()/a.units_produced.sum(); curve.append(v)
    i=int(np.argmin(curve)); return grid[i], round(curve[i],5)
for df in [4,5,6,8,10]:
    f='defective_units + fail ~ '+CORE2+f' + bs(humidity_pct, df={df}) * C(supplier_code_n)'
    print('spline df',df, opt(f))
f='defective_units + fail ~ '+CORE2+' + humidity_pct*C(supplier_code_n) + I(humidity_pct**2)*C(supplier_code_n)'
print('quadratic per supplier', opt(f))
m=smf.glm('defective_units + fail ~ '+CORE2+' + humidity_pct*C(supplier_code_n) + I(humidity_pct**2)*C(supplier_code_n)',data=cc,family=sm.families.Binomial()).fit()
b=m.params; print({k:round(v,5) for k,v in b.items() if 'humidity' in k})
" 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cat >> $S/cf.py <<'EOF'


QUAD = CORE2 + ' + humidity_pct*C(supplier_code_n) + I(humidity_pct**2)*C(supplier_code_n)'
SPL = CORE2 + ' + bs(humidity_pct, df=6) * C(supplier_code_n)'
RECIPE = {'SP-01': 30, 'SP-02': 30, 'SP-03': 36}  # standard cycle time per resin grade (suppliers.csv)


def expected_defects(model, d):
    return model.predict(d) * d.units_produced


if __name__ == '__main__' and 'run_cf' in sys.argv:
    c = prep()
    cc = c.dropna(subset=['humidity_pct', 'mold_c']).copy()
    mq = smf.glm('defective_units + fail ~ ' + QUAD, data=cc, family=sm.families.Binomial()).fit()
    ms = smf.glm('defective_units + fail ~ ' + SPL, data=cc, family=sm.families.Binomial()).fit()
    print('deviance quad', round(mq.deviance, 1), 'df', mq.df_resid, '| spline', round(ms.deviance, 1), 'df', ms.df_resid)
    # ---- C1: all resin from one supplier, standard recipe cycle time
    for label, d in [('complete', cc), ('imputed', c.assign(humidity_pct=c.humidity_imp))]:
        out = {}
        for sup in ['SP-01', 'SP-02', 'SP-03']:
            a = d.copy()
            a['supplier_code_n'] = sup
            a['cycle_time_s'] = RECIPE[sup]
            e = expected_defects(ms, a)
            out[sup] = round(e.sum() / a.units_produced.sum(), 5)
        print('C1', label, out)
    # ---- C3: every mold cleaned at least every 14 days
    mc = pd.read_csv(f'{SRC}/maintenance.csv', parse_dates=['date'])
    mc = mc[mc.event == 'mold_cleaning']
    def dsc_new(r):
        logged = mc[(mc.line == r.line) & (mc.date <= r.date)].date.max()
        since = (r.date - logged).days
        return since % 14 if since >= 14 else since
    c['dsc_new'] = c.apply(dsc_new, axis=1)
    cc = c.dropna(subset=['humidity_pct', 'mold_c']).copy()
    base = ms.predict(cc)
    cf = cc.copy(); cf['dsc'] = cf.dsc_new
    new = ms.predict(cf)
    ratio = (new / base)
    rec_new = cc.defective_units * ratio
    print('C3 recorded rate (complete rows)', round(cc.defective_units.sum() / cc.units_produced.sum(), 5))
    print('C3 counterfactual (recorded counts scaled):', round(rec_new.sum() / cc.units_produced.sum(), 5))
    # all rows, missing covariates left at recorded counts
    allr = c.copy()
    allr['ratio'] = 1.0
    allr.loc[cc.index, 'ratio'] = ratio
    print('C3 all rows (missing covariates unchanged):', round((allr.defective_units * allr.ratio).sum() / allr.units_produced.sum(), 5))
    print('dsc_new max', c.dsc_new.max(), 'mean change', round((c.dsc_new - c.dsc).mean(), 2))
EOF
python3 -W ignore $S/cf.py run_cf 2>&1 | grep -v -i wls

S=/tmp/claude-0/-tmp-edabench-claude-lq28c-fe/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && python3 -W ignore -c "
import sys; sys.path.insert(0,'$S')
from cf import *
c=prep()
mc=pd.read_csv(f'{SRC}/maintenance.csv', parse_dates=['date']); mc=mc[mc.event=='mold_cleaning']
def dsc_new(r):
    logged=mc[(mc.line==r.line)&(mc.date<=r.date)].date.max(); since=(r.date-logged).days
    return since%14 if since>=14 else since
c['dsc_new']=c.apply(dsc_new,axis=1)
cc=c.dropna(subset=['humidity_pct','mold_c']).copy()
ms=smf.glm('defective_units + fail ~ '+SPL,data=cc,family=sm.families.Binomial()).fit()
a=c.assign(humidity_pct=c.humidity_imp, mold_c=c.mold_imp)
base=ms.predict(a); f=a.copy(); f['dsc']=f.dsc_new; new=ms.predict(f)
ratio=new/base
print('C3 all rows, imputed covariates:', round((a.defective_units*ratio).sum()/a.units_produced.sum(),5))
print('C3 baseline rate by scaling check:', round((a.defective_units*(base/base)).sum()/a.units_produced.sum(),5))
# fitted-expected baseline vs actual
print('model baseline expected rate', round((base*a.units_produced).sum()/a.units_produced.sum(),5))
print('C3 model-only counterfactual rate', round((new*a.units_produced).sum()/a.units_produced.sum(),5))
# A4 with the calibrated offset
pre=c.line.eq('L1')&(c.date<'2025-04-14')
mt=c.mold_temp_raw.replace(0,np.nan)
mtF=np.where(c.line.eq('L3')&(mt>300),(mt-32)*5/9,mt)
mtC=pd.Series(mtF,index=c.index)+np.where(pre,OFFSET,0)
print('A4 median with offset',OFFSET, round(mtC.dropna().median(),3), 'n', mtC.notna().sum())
print('A4 median without sensor correction', round(pd.Series(mtF,index=c.index).dropna().median(),3))
" 2>&1 | grep -v -i wls
