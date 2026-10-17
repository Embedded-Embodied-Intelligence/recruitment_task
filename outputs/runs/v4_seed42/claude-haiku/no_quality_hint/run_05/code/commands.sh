ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

python3 -c "
import pandas as pd
pd.set_option('display.width',250); pd.set_option('display.max_columns',30)
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(b.shape); print(b.dtypes)
for c in b.columns:
    vc=b[c].value_counts()
    print('---',c,'nunique',b[c].nunique(),'blank',(b[c].str.strip()=='').sum())
    if b[c].nunique()<40: print(vc.to_string())
    else: print(b[c].sample(15,random_state=1).tolist())
"
echo ==; cat suppliers.csv; echo ==; cat maintenance.csv | awk -F, '{print $3}' | sort | uniq -c; grep -v mold_cleaning maintenance.csv | head -40

python3 -c "
import pandas as pd, re
pd.set_option('display.width',250); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id')
print('dup ids',d.batch_id.nunique(),'rows',len(d))
print('exact dup rows', b.duplicated().sum())
print(d.head(20).to_string())
# which columns differ among duplicate pairs
diffcols={}
for bid,g in d.groupby('batch_id'):
    for c in b.columns:
        if g[c].nunique()>1: diffcols[c]=diffcols.get(c,0)+1
print('cols differing within dup groups:',diffcols)
"


python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
print(len(b), b.batch_id.nunique())
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num:
    x=pd.to_numeric(b[c],errors='coerce')
    print(c,'nonnum',(x.isna()).sum(),'min',x.min(),'max',x.max(), 'q',x.quantile([.01,.5,.99]).round(1).tolist())
h=pd.to_numeric(b.humidity_pct,errors='coerce')
print('humidity <0 or >100 or nan:', (h<0).sum(), (h>100).sum(), h.isna().sum())
print(b.loc[h<0,['batch_id','humidity_pct']].head(), (h==-1).sum())
print(sorted(h.dropna().unique())[:10], sorted(h.dropna().unique())[-10:])
# date formats
def fmt(s):
    if '-' in s: return 'iso'
    a,bb,_=s.split('/'); a=int(a); bb=int(bb)
    if a>12: return 'DMY'
    if bb>12: return 'MDY'
    return 'ambig'
b['fmt']=b.production_date.map(fmt)
print(b.fmt.value_counts())
"


python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',300)
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates()
b['mt']=pd.to_numeric(b.mold_temp)
print('mold zeros',(b.mt==0).sum())
print(b.loc[b.mt==0,'line'].value_counts())
print(b.loc[b.mt==0,'mold_temp'].value_counts())
b['F']=b.mt>300
print(pd.crosstab(b.line,b.F))
print(b.loc[b.mt>0].groupby(['line','F']).mt.describe())
"


python3 -c "
import pandas as pd, numpy as np
pd.set_option('display.width',250); pd.set_option('display.max_rows',300)
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
iso=b[b.production_date.str.contains('-')].copy()
iso['d']=pd.to_datetime(iso.production_date)
print('iso min/max',iso.d.min(),iso.d.max())
print('iso monotone in file order?', iso.d.is_monotonic_increasing, (iso.d.diff().dt.days<0).sum())
print(iso[['production_date','line']].head(30).T.to_string())
print(b.groupby('line').size())
" 


mkdir -p $TMPDIR/work && cat > $TMPDIR/work/load.py <<'EOF'
import pandas as pd, numpy as np
D='/tmp/edabench_claude_0kuhyayl/'
pd.set_option('display.width',250); pd.set_option('display.max_columns',40); pd.set_option('display.max_rows',300)

def parse_dates(s):
    out=[]
    for x in s:
        if '-' in x: out.append(pd.Timestamp(x)); continue
        a,b_,y=map(int,x.split('/'))
        cands=[]
        if a<=12: cands.append(pd.Timestamp(year=y,month=b_,day=a) if b_<=12 else None)
        if b_<=12: cands.append(pd.Timestamp(year=y,month=a,day=b_) if a<=12 else None)
        cands=[c for c in cands if c is not None]
        out.append(cands)
    return out

def load_batches():
    raw=pd.read_csv(D+'batches.csv',dtype=str,keep_default_na=False)
    b=raw.drop_duplicates().reset_index(drop=True)
    parsed=parse_dates(b.production_date)
    fixed=[None]*len(b)
    for i,p in enumerate(parsed):
        if isinstance(p,pd.Timestamp): fixed[i]=p
        elif len(set(p))==1: fixed[i]=p[0]
    # ambiguous: choose candidate in [prev resolved, next resolved] in row order
    known=[(i,f) for i,f in enumerate(fixed) if f is not None]
    ki=np.array([k for k,_ in known]); kd=[f for _,f in known]
    amb=0; conflicts=0
    for i,p in enumerate(parsed):
        if fixed[i] is not None: continue
        amb+=1
        j=np.searchsorted(ki,i)
        lo=kd[j-1] if j>0 else pd.Timestamp('2025-01-01')
        hi=kd[j] if j<len(kd) else pd.Timestamp('2025-12-31')
        inside=[c for c in p if lo<=c<=hi]
        if len(inside)==1: fixed[i]=inside[0]
        else:
            conflicts+=1; fixed[i]=min(p,key=lambda c:min(abs((c-lo).days),abs((c-hi).days)))
    b['date']=pd.to_datetime(fixed)
    return b, amb, conflicts
EOF
cd $TMPDIR/work && python3 -c "
from load import *
b,amb,conf=load_batches()
print('ambiguous',amb,'conflicts',conf, b.date.min(), b.date.max())
b=b.sort_values('date',kind='stable')
print('order check: rows out of order vs file order', (b.index.to_series().diff()<0).sum())
print(b.date.dt.dayofweek.value_counts().sort_index())
"

cd $TMPDIR/work && python3 - <<'EOF'
import re
src=open('load.py').read()
new='''def parse_dates(s):
    out=[]
    for x in s:
        if '-' in x: out.append(pd.Timestamp(x)); continue
        a,b_,y=map(int,x.split('/'))
        cands=[]
        for m,d in ((b_,a),(a,b_)):   # MM/DD and DD/MM readings
            try: cands.append(pd.Timestamp(year=y,month=m,day=d))
            except ValueError: pass
        out.append(list(dict.fromkeys(cands)))
    return out
'''
start=src.index('def parse_dates'); end=src.index('def load_batches')
open('load.py','w').write(src[:start]+new+'\n'+src[end:])
EOF
python3 -c "
from load import *
b,amb,conf=load_batches()
print('ambiguous',amb,'conflicts',conf, b.date.min(), b.date.max())
print('row-order breaks in resolved dates:', (b.date.diff().dt.days<0).sum())
print(b.date.dt.dayofweek.value_counts().sort_index().tolist())
"

cd $TMPDIR/work && python3 -c "
from load import *
raw=pd.read_csv(D+'batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
iso=raw.production_date.str.contains('-')
d=pd.to_datetime(raw.production_date.where(iso))
s=d.dropna()
br=s[s.diff().dt.days<0]
print('ISO-only breaks', len(br))
print(pd.DataFrame({'idx':br.index,'date':br.values,'prev':s.shift(1)[br.index].values, 'line':raw.line[br.index].values}).head(20).to_string())
# how far out of order by row: running max
rm=s.cummax()
print('max lag days', (rm-s).dt.days.max(), ((rm-s).dt.days>0).sum())
print(s.sort_values().index.to_series().diff().describe())
" 2>&1 | head -60

cd $TMPDIR/work && python3 -c "
from load import *
raw=pd.read_csv(D+'batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
iso=raw.production_date.str.contains('-')
d=pd.to_datetime(raw.production_date.where(iso))
for ln,g in raw.groupby('line'):
    s=d[g.index].dropna()
    print(ln,'ISO breaks within line', (s.diff().dt.days<0).sum(), 'n',len(s))
" 2>&1 | tail -8

cd $TMPDIR/work && cat > resolve.py <<'EOF'
from load import *
def load_batches2():
    raw=pd.read_csv(D+'batches.csv',dtype=str,keep_default_na=False)
    b=raw.drop_duplicates().reset_index(drop=True)
    parsed=parse_dates(b.production_date)
    fixed=[None]*len(b)
    for i,p in enumerate(parsed):
        if isinstance(p,pd.Timestamp): fixed[i]=p
        elif len(p)==1: fixed[i]=p[0]
    conf=0; amb=0
    for ln,g in b.groupby('line'):
        idx=list(g.index)
        known=[(k,fixed[k]) for k in idx if fixed[k] is not None]
        for pos,k in enumerate(idx):
            if fixed[k] is not None or len(parsed[k])<2: continue
            amb+=1
            prev=[f for kk,f in known if idx.index(kk)<pos]
            nxt=[f for kk,f in known if idx.index(kk)>pos]
            lo=max(prev) if prev else pd.Timestamp('2025-01-06')
            hi=min(nxt) if nxt else pd.Timestamp('2025-09-30')
            ok=[c for c in parsed[k] if lo<=c<=hi]
            if len(ok)==1: fixed[k]=ok[0]; known.append((k,ok[0]))
            else:
                conf+=1
                pick=min(parsed[k],key=lambda c:(c-lo).days if c>=lo else 9999)
                fixed[k]=pick
                known.append((k,pick))
    b['date']=pd.to_datetime(fixed)
    return b,amb,conf
EOF
python3 -c "
from resolve import *
b,amb,conf=load_batches2()
print('amb',amb,'conf',conf,'range',b.date.min().date(),b.date.max().date())
for ln,g in b.groupby('line'): print(ln,'breaks',(g.date.diff().dt.days<0).sum(), g.date.min().date(), g.date.max().date(), len(g))
"

cd $TMPDIR/work && python3 -c "
from load import *
raw=pd.read_csv(D+'batches.csv',dtype=str,keep_default_na=False).drop_duplicates().reset_index(drop=True)
l1=raw[raw.line=='L1'][['production_date','shift','mold_temp']]
print(l1.head(60).to_string())
" | head -70

cd $TMPDIR/work && cat > resolve.py <<'EOF'
from load import *
def load_batches3(k=15):
    raw=pd.read_csv(D+'batches.csv',dtype=str,keep_default_na=False)
    b=raw.drop_duplicates().reset_index(drop=True)
    parsed=parse_dates(b.production_date)
    # reliable dates: only one valid reading
    sure=pd.Series([p[0] if isinstance(p,list) and len(p)==1 else (p if isinstance(p,pd.Timestamp) else pd.NaT) for p in parsed])
    fixed=[None]*len(b); conf=0; amb=0
    for ln,g in b.groupby('line'):
        idx=list(g.index)
        for pos,r in enumerate(idx):
            p=parsed[r]
            if isinstance(p,pd.Timestamp): fixed[r]=p; continue
            if len(p)==1: fixed[r]=p[0]; continue
            amb+=1
            nb=sure.loc[idx[max(0,pos-k):pos+k+1]].dropna()
            nb=nb[nb.index!=r]
            ref=nb.sort_values().iloc[len(nb)//2] if len(nb) else pd.Timestamp('2025-06-01')
            fixed[r]=min(p,key=lambda c:abs((c-ref).days))
            if abs((fixed[r]-ref).days)>20: conf+=1
    b['date']=pd.to_datetime(fixed)
    return b,amb,conf
EOF
python3 -c "
from resolve import *
b,amb,conf=load_batches3()
print('amb',amb,'far-from-neighbours',conf,'range',b.date.min().date(),b.date.max().date())
for ln,g in b.groupby('line'): print(ln,'breaks',(g.date.diff().dt.days<0).sum(), g.date.min().date(), g.date.max().date(), len(g), g.date.dt.month.value_counts().sort_index().to_dict())
"

cd $TMPDIR/work && python3 -c "
from resolve import *
b,_,_=load_batches3()
b['mt']=pd.to_numeric(b.mold_temp)
l3=b[b.line=='L3'].sort_values('date')
l3['F']=l3.mt>300
print(l3.groupby(l3.date.dt.to_period('M')).F.agg(['sum','count']))
print(l3[(~l3.F)&(l3.mt>0)][['batch_id','production_date','date','mt','shift']].to_string())
print(l3[l3.mt==0][['date','mt']].to_string())
" 

cd $TMPDIR/work && python3 -c "
from resolve import *
b,_,_=load_batches3()
b['mt']=pd.to_numeric(b.mold_temp)
b.loc[b.line=='L3','mt']=(b.loc[b.line=='L3','mt']-32)*5/9
v=b[b.mt>0].copy()
print(v.groupby(['line',v.date.dt.to_period('M')]).mt.mean().unstack(0).round(2))
l1=v[v.line=='L1'].sort_values('date')
print('L1 before/after 2025-04-14:', l1[l1.date<'2025-04-14'].mt.agg(['mean','median','count']).round(2).tolist(), l1[l1.date>='2025-04-14'].mt.agg(['mean','median','count']).round(2).tolist())
print('median mold temp C all valid:', round(v.mt.median(),4), len(v))
" 

cd $TMPDIR/work && python3 -c "
from resolve import *
b,_,_=load_batches3()
b['mt']=pd.to_numeric(b.mold_temp)
b.loc[b.line=='L3','mt']=(b.loc[b.line=='L3','mt']-32)*5/9
v=b[(b.mt>0)&(b.line=='L1')].sort_values('date')
w=v[(v.date>='2025-03-24')&(v.date<='2025-05-31')]
print(w.groupby(w.date.dt.to_period('W')).mt.agg(['mean','median','count']).round(2))
print(v.groupby(v.date.dt.to_period('W')).mt.median().round(1).to_string())
" | head -90

cd $TMPDIR/work && python3 -c "import statsmodels, sklearn; print('ok', statsmodels.__version__)" 2>&1 | tail -1; cat > clean.py <<'EOF'
from resolve import *
def clean():
    b,_,_=load_batches3()
    s=pd.read_csv(D+'suppliers.csv',dtype=str)
    b['supplier_code']=b.supplier_code.str.strip().str.upper()
    b=b.merge(s[['supplier_code','supplier_name','resin_grade','pre_dried','recipe_cycle_time_s']],on='supplier_code',how='left')
    sh=b['shift'].str.strip().str.lower()
    b['shift']=np.where(sh.isin(['d','day']),'Day',np.where(sh.isin(['n','night']),'Night',None))
    for c in ['machine_age_years','ambient_temp_c','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur','humidity_pct','mold_temp']:
        b[c]=pd.to_numeric(b[c])
    b.loc[b.humidity_pct<0,'humidity_pct']=np.nan
    b.loc[b.line=='L3','mold_temp']=(b.loc[b.line=='L3','mold_temp']-32)*5/9
    b.loc[b.mold_temp<=0,'mold_temp']=np.nan   # 0.0 = missing reading (also 0 in F for L3 -> already converted; handle below)
    b['rate']=b.defective_units/b.units_produced
    return b
EOF
python3 -c "
from clean import *
b=clean()
print(b.shift.isna().sum(), b.supplier_name.isna().sum(), b.supplier_code.value_counts().to_dict())
print('A1',len(b),'A2',b.humidity_pct.isna().sum(),'A3',round(b.defective_units.sum()/b.units_produced.sum(),6),'A4 median mold',round(b.mold_temp.median(),4), b.mold_temp.notna().sum())
"

cd $TMPDIR/work && cat > clean.py <<'EOF'
from resolve import *
def clean():
    b,_,_=load_batches3()
    s=pd.read_csv(D+'suppliers.csv',dtype=str)
    b['supplier_code']=b.supplier_code.str.strip().str.upper()
    b=b.merge(s[['supplier_code','supplier_name','resin_grade','pre_dried','recipe_cycle_time_s']],on='supplier_code',how='left')
    sh=b['shift'].str.strip().str.lower()
    b['shift']=np.where(sh.isin(['d','day']),'Day',np.where(sh.isin(['n','night']),'Night',None))
    for c in ['machine_age_years','ambient_temp_c','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur','humidity_pct','mold_temp','operator_id']:
        if c!='operator_id': b[c]=pd.to_numeric(b[c])
    b.loc[b.humidity_pct<0,'humidity_pct']=np.nan
    b.loc[b.mold_temp<=0,'mold_temp']=np.nan   # 0.0 = missing reading
    isl3=b.line=='L3'
    b.loc[isl3,'mold_temp']=(b.loc[isl3,'mold_temp']-32)*5/9   # L3 logs Fahrenheit
    b['rate']=b.defective_units/b.units_produced
    return b
EOF
python3 -c "
from clean import *
b=clean()
print('shift NaN',b['shift'].isna().sum(), 'supplier NaN',b.supplier_name.isna().sum(), b.supplier_code.value_counts().to_dict())
print('A1',len(b),'A2',b.humidity_pct.isna().sum(),'A3',round(b.defective_units.sum()/b.units_produced.sum(),6),'A4 median mold',round(b.mold_temp.median(),4), b.mold_temp.notna().sum())
"

cd $TMPDIR/work && python3 -c "
from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
b=clean()
b=b.dropna(subset=['humidity_pct','mold_temp']).copy()
b['cyc_dev']=b.cycle_time_s-b.recipe_cycle_time_s
b['d']=b.defective_units; b['ok']=b.units_produced-b.defective_units
for c in ['shift','operator_id','line','supplier_name']:
    g=b.groupby(c).apply(lambda x: pd.Series({'rate':x.d.sum()/x.units_produced.sum(),'n':len(x)}))
    print(g.round(4).to_string()); print()
m=smf.glm('d + ok ~ 1',data=b,family=sm.families.Binomial()).fit()
" 2>&1 | head -120

cd $TMPDIR/work && sed -i "s/    b\['rate'\]=b.defective_units/    b['recipe_cycle_time_s']=pd.to_numeric(b.recipe_cycle_time_s)\n    b['rate']=b.defective_units/" clean.py && python3 -c "
from clean import *
b=clean()
b['d']=b.defective_units
for c in ['shift','operator_id','line','supplier_name','pre_dried']:
    g=b.groupby(c).apply(lambda x: pd.Series({'rate':x.d.sum()/x.units_produced.sum(),'n':len(x)}))
    print(g.round(4).to_string()); print()
print(b[['rate','machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','qc_inspection_min']].corrwith(b.rate, method='spearman').round(3))
" 2>&1 | grep -v Warning

cd $TMPDIR/work && python3 -c "
from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
b=clean()
print(pd.crosstab(b.operator_id,b.line).to_string())
print(pd.crosstab(b.supplier_name,b.line))
b['d']=b.defective_units; b['ok']=b.units_produced-b.defective_units
bb=b.dropna(subset=['humidity_pct','mold_temp']).copy()
f='d + ok ~ machine_age_years + ambient_temp_c + mold_temp + humidity_pct + cycle_time_s + C(operator_id) + C(shift) + C(line) + C(supplier_name)'
m=smf.glm(f,data=bb,family=sm.families.Binomial()).fit(scale='X2')
print(m.summary2().tables[1].round(4).to_string())
print('dispersion', round(m.scale,3))
" 2>&1 | grep -v Warning

cd $TMPDIR/work && python3 -c "
from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
b=clean()
b['d']=b.defective_units; b['ok']=b.units_produced-b.defective_units
bb=b.dropna(subset=['humidity_pct','mold_temp']).copy()
f='d + ok ~ machine_age_years + ambient_temp_c + mold_temp + humidity_pct + cycle_time_s + C(operator_id) + C(shift) + C(line) + C(supplier_name)'
m=smf.glm(f,data=bb,family=sm.families.Binomial()).fit()
print('pearson chi2/df', round(m.pearson_chi2/m.df_resid,3), 'deviance/df', round(m.deviance/m.df_resid,3))
print(m.summary2().tables[1].loc[['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','C(shift)[T.Night]','C(supplier_name)[T.Beta]','C(supplier_name)[T.Gamma]']].round(5).to_string())
print(bb[['d','ok']].describe().round(1))
" 2>&1 | grep -v Warn

cd $TMPDIR/work && cat > base.py <<'EOF'
from clean import *
import statsmodels.api as sm, statsmodels.formula.api as smf
def prep():
    b=clean()
    b['d']=b.defective_units; b['ok']=b.units_produced-b.defective_units
    return b
def fit(f,data):
    return smf.glm(f,data=data,family=sm.families.Binomial()).fit()
EOF
python3 -c "
from base import *
b=prep().dropna(subset=['humidity_pct','mold_temp'])
f='d + ok ~ machine_age_years + ambient_temp_c + mold_temp + humidity_pct + cycle_time_s + C(operator_id) + C(shift) + C(line) + C(supplier_name)'
m=fit(f,b)
b['pr']=m.resid_pearson
b['mon']=b.date.dt.to_period('M')
t=b.groupby(['line','mon']).pr.mean().unstack(0).round(2)
print(t.to_string())
b['wk']=b.date.dt.to_period('W')
" 2>&1 | grep -v Warn

cd $TMPDIR/work && python3 -c "
from base import *
b=prep().dropna(subset=['humidity_pct','mold_temp'])
post=(b.line=='L1')&(b.date>='2025-04-14')
f='d + ok ~ machine_age_years + ambient_temp_c + mold_adj + humidity_pct + cycle_time_s + C(operator_id) + C(shift) + C(line) + C(supplier_name)'
res={}
for delta in [0,2,4,5,6,7,8,9,10,12]:
    b['mold_adj']=b.mold_temp-np.where(post,delta,0)
    m=fit(f,b); res[delta]=round(m.llf,2)
    print(delta, round(m.llf,2), 'pearson/df', round(m.pearson_chi2/m.df_resid,3))
" 2>&1 | grep -v Warn

cd $TMPDIR/work && python3 -c "
from base import *
b=prep().dropna(subset=['humidity_pct','mold_temp'])
post=(b.line=='L1')&(b.date>='2025-04-14')
f='d + ok ~ machine_age_years + ambient_temp_c + mold_adj + humidity_pct + cycle_time_s + C(operator_id) + C(shift) + C(line) + C(supplier_name)'
for delta in [10,11,12,13,14,15,16]:
    b['mold_adj']=b.mold_temp-np.where(post,delta,0)
    m=fit(f,b)
    print(delta, round(m.llf,2), 'b_mold',round(m.params['mold_adj'],4), 'C(line)L1 n/a')
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from base import *
b=prep()
post=(b.line=='L1')&(b.date>='2025-04-14')
b['mold_temp']=b.mold_temp-np.where(post,11,0)
b.to_pickle('clean_b.pkl')
bb=b.dropna(subset=['humidity_pct','mold_temp']).copy()
f='d + ok ~ machine_age_years + ambient_temp_c + mold_temp + humidity_pct + cycle_time_s + C(operator_id) + C(shift) + C(line) + C(supplier_name)'
m0=fit(f,bb); print('base llf',round(m0.llf,2),'disp',round(m0.pearson_chi2/m0.df_resid,3))
out=[]
days=pd.date_range('2025-02-01','2025-09-15',freq='D')
for ln in ['L1','L2','L3','L4']:
    best=None
    for dt in days:
        bb['step']=((bb.line==ln)&(bb.date>=dt)).astype(int)
        m=fit(f+' + step',bb)
        g=m.llf-m0.llf
        if best is None or g>best[1]: best=(dt.date(),g,round(m.params['step'],3))
    out.append((ln,)+best)
    print(ln,best,flush=True)
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from base import *
b=pd.read_pickle('clean_b.pkl')
b['wk']=b.date.dt.to_period('W')
g=b.groupby(['line','wk']).agg(d=('defective_units','sum'),u=('units_produced','sum'),n=('batch_id','count'),ubar=('units_produced','mean'))
g['rate']=g.d/g.u
print(g.rate.unstack(0).round(4).loc['2025-05-01':'2025-09-30'].to_string())
print(g.ubar.unstack(0).round(0).loc['2025-05-01':'2025-09-30'].to_string())
" 2>&1 | grep -v -i warn

cd $TMPDIR/work && python3 -c "
from base import *
b=pd.read_pickle('clean_b.pkl')
b['per']=np.where(b.date>=pd.Timestamp('2025-06-15'),'post','pre')
for ln in ['L2']:
    s=b[b.line==ln]
    print(ln); print(pd.crosstab(s.date.dt.to_period('M'),s.supplier_name,normalize='index').round(2).to_string())
    print(s.groupby(s.date.dt.to_period('M'))[['mold_temp','humidity_pct','cycle_time_s','ambient_temp_c','machine_age_years','qc_inspection_min']].mean().round(2).to_string())
    print(pd.crosstab(s.date.dt.to_period('M'),s['shift'],normalize='index').round(2).to_string())
b['per']=np.where(b.date>=pd.Timestamp('2025-07-21'),'post','pre')
s=b[b.line=='L3']
print('L3'); print(pd.crosstab(s.date.dt.to_period('M'),s.supplier_name,normalize='index').round(2).to_string())
print(s.groupby(s.date.dt.to_period('M'))[['mold_temp','humidity_pct','cycle_time_s','ambient_temp_c','machine_age_years','qc_inspection_min']].mean().round(2).to_string())
" 2>&1 | grep -v -i warn

cd $TMPDIR/work && python3 -c "
from base import *
b=pd.read_pickle('clean_b.pkl')
for ln,dt0,dt1 in [('L3','2025-07-01','2025-08-20'),('L2','2025-06-01','2025-07-05')]:
    s=b[(b.line==ln)&(b.date>=dt0)&(b.date<=dt1)].sort_values('date')
    w=s.groupby('date').agg(qc=('qc_inspection_min','mean'),rate=('rate','mean'),n=('batch_id','count'))
    print(ln); print(w.round(3).to_string())
" 2>&1 | grep -v -i warn | head -150

cd $TMPDIR/work && python3 -c "
from base import *
b=pd.read_pickle('clean_b.pkl')
bb=b.dropna(subset=['humidity_pct','mold_temp']).copy()
f='d + ok ~ machine_age_years + ambient_temp_c + mold_temp + humidity_pct + cycle_time_s + C(operator_id) + C(shift) + C(line) + C(supplier_name)'
m0=fit(f,bb)
res=[]
for dt in pd.date_range('2025-06-01','2025-06-30'):
    bb['step']=((bb.line=='L2')&(bb.date>=dt)).astype(int)
    m=fit(f+' + step',bb); res.append((dt.date(),round(m.llf-m0.llf,1),round(m.params['step'],3)))
for r in res: print(r)
" 2>&1 | grep -v -i warn | grep -v wls
python3 -c "
from base import *
b=pd.read_pickle('/tmp/edabench_claude_0kuhyayl/../../tmp/edabench_claude_0kuhyayl/x.pkl') if False else None
" 2>/dev/null; cd $TMPDIR/work && python3 -c "
from base import *
b=pd.read_pickle('clean_b.pkl')
import statsmodels.formula.api as smf
x=b.dropna(subset=['qc_inspection_min'])
r=smf.ols('qc_inspection_min ~ defective_units + units_produced + C(line)',data=x).fit()
print('qc ~ defects R2', round(r.rsquared,3)); print(r.params.round(4).to_string())
y=b.dropna(subset=['rework_cost_eur'])
y=y.assign(rpd=y.rework_cost_eur/y.defective_units)
print('rework per defective', y.rpd.describe().round(3).to_string())
r2=smf.ols('rework_cost_eur ~ defective_units',data=y).fit(); print('rework R2',round(r2.rsquared,4), r2.params.round(3).to_dict())
" 2>&1 | grep -v -i warn

cd $TMPDIR/work && cat > model.py <<'EOF'
from base import *
from scipy import stats
b=pd.read_pickle('/tmp/claude-0/-home-claude/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/work/clean_b.pkl') if False else pd.read_pickle('clean_b.pkl')
b['step_L2']=((b.line=='L2')&(b.date>='2025-06-15')).astype(int)
b['step_L3']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
bb=b.dropna(subset=['humidity_pct','mold_temp']).copy()
BASE='machine_age_years + ambient_temp_c + mold_temp + humidity_pct + cycle_time_s + C(operator_id) + C(shift) + C(line) + C(supplier_name) + step_L2 + step_L3'
def lr(full,reduced,data,disp):
    mf=fit(full,data); mr=fit(reduced,data)
    stat=2*(mf.llf-mr.llf)/disp
    dfd=mf.df_model-mr.df_model
    return stat,dfd,stats.chi2.sf(stat,dfd)
EOF
python3 -c "
from model import *
m=fit('d + ok ~ '+BASE,bb)
disp=m.pearson_chi2/m.df_resid
print('disp after steps', round(disp,3), 'llf',round(m.llf,1))
print(m.summary2().tables[1].loc[['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','C(shift)[T.Night]','C(supplier_name)[T.Beta]','C(supplier_name)[T.Gamma]','step_L2','step_L3']].round(4).to_string())
Y='d + ok ~ '
terms=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','C(operator_id)','C(shift)']
for t in terms:
    red=BASE.replace(t+' + ','').replace(' + '+t,'') if t in BASE else BASE
    red=red.replace(t,'1') if False else red
    s,dfd,p=lr(Y+BASE,Y+red,bb,disp)
    print(f'{t:22s} LR={s:9.2f} df={dfd} p={p:.2e}')
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from model import *
Y='d + ok ~ '
m0=fit(Y+BASE,bb); disp=m0.pearson_chi2/m0.df_resid
tests={
 'humid x supplier': BASE+' + humidity_pct:C(supplier_name)',
 'humid^2': BASE+' + I(humidity_pct**2)',
 'humid^2 x supplier': BASE+' + I(humidity_pct**2) + I(humidity_pct**2):C(supplier_name)',
 'cycle x supplier': BASE+' + cycle_time_s:C(supplier_name)',
 'mold^2': BASE+' + I(mold_temp**2)',
 'mold x supplier': BASE+' + mold_temp:C(supplier_name)',
 'mold x shift': BASE+' + mold_temp:C(shift)',
 'humid x shift': BASE+' + humidity_pct:C(shift)',
 'cycle^2': BASE+' + I(cycle_time_s**2)',
 'ambient^2': BASE+' + I(ambient_temp_c**2)',
 'machine_age^2': BASE+' + I(machine_age_years**2)',
 'humid x mold': BASE+' + humidity_pct:mold_temp',
}
for k,v in tests.items():
    s,dfd,p=lr(Y+v,Y+BASE,bb,disp); print(f'{k:22s} LR={s:8.2f} df={dfd} p={p:.2e}')
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from model import *
Y='d + ok ~ '
F=Y+'machine_age_years + ambient_temp_c + mold_temp + cycle_time_s + C(operator_id) + C(shift) + C(line) + step_L2 + step_L3 + C(supplier_name)'
# adjust for everything except humidity using a flexible humidity term (bins) per supplier
bb['hbin']=pd.cut(bb.humidity_pct,bins=np.arange(10,76,5))
f=Y+'machine_age_years + ambient_temp_c + mold_temp + cycle_time_s + C(operator_id) + C(shift) + C(line) + step_L2 + step_L3 + C(supplier_name) + C(hbin)'
m=fit(f,bb)
rows=[]
for sname in ['Alpha','Beta','Gamma']:
    pass
ref=bb.hbin.cat.categories
print('bin effects (logit rel. to 10-15), from pooled model:')
print(pd.Series(np.r_[0,[m.params[f'C(hbin)[T.{c}]'] for c in ref[1:]]],index=[str(c) for c in ref]).round(3).to_string())
for sname in ['Alpha','Beta','Gamma']:
    s=bb[bb.supplier_name==sname]
    g=s.groupby('hbin',observed=True).agg(d=('d','sum'),u=('units_produced','sum'),n=('d','size'))
    g['raw_rate']=(g.d/g.u).round(4)
    print(sname); print(g[['n','raw_rate']].to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from model import *
Y='d + ok ~ '
red=BASE.replace(' + humidity_pct','')
m=fit(Y+red,bb)
bb['exp_d']=m.predict(bb)*bb.units_produced  # predicted rate * units
bb['hb']=pd.cut(bb.humidity_pct,bins=[10,20,25,30,35,40,45,50,55,60,75]).astype(str)
g=bb.groupby(['supplier_name','hb']).agg(obs=('d','sum'),exp=('exp_d','sum'),u=('units_produced','sum'),n=('d','size'))
g['O/E']=(g.obs/g.exp).round(3); g['raw']=(g.obs/g.u).round(4)
print(g.to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && cat > final.py <<'EOF'
from model import *
Y='d + ok ~ '
FULL=('machine_age_years + ambient_temp_c + mold_temp + cycle_time_s + C(operator_id) + C(shift) + C(line) + step_L2 + step_L3'
      ' + C(supplier_name) + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name)')
mf=fit(Y+FULL,bb)
disp=mf.pearson_chi2/mf.df_resid
EOF
python3 -c "
from final import *
print('disp',round(disp,3),'llf',round(mf.llf,1))
print(mf.summary2().tables[1].loc[[i for i in mf.params.index if 'humidity' in i or 'supplier' in i or 'mold' in i or 'cycle' in i]].round(5).to_string())
# Alpha optimum via quadratic vertex and via averaged prediction
s=bb[bb.supplier_name=='Alpha'].copy()
grid=np.arange(12.1,72.31,0.1)
avg=[]
for h in grid:
    t=s.copy(); t['humidity_pct']=h
    p=mf.predict(t)
    avg.append((p*t.units_produced).sum()/t.units_produced.sum())
avg=np.array(avg); i=avg.argmin()
print('Alpha optimum (pooled-rate minimum):', round(grid[i],2), 'rate', round(avg[i],5))
print('C2 humidity at min,', [round(x,1) for x in grid[[0,i,-1]]], 'rate at 12.1 and 72.3:', round(avg[0],5), round(avg[-1],5))
for h in [15,20,25,30,35,40,45,50]:
    print(h, round(avg[int(round((h-12.1)/0.1))],5))
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from final import *
recipe={'Alpha':30,'Beta':30,'Gamma':36}
print('recipes from suppliers.csv:', pd.read_csv(D+'suppliers.csv').set_index('supplier_name').recipe_cycle_time_s.to_dict())
pred_asis=mf.predict(bb)*bb.units_produced
print('as-is observed', round(bb.d.sum()/bb.units_produced.sum(),5),'predicted', round(pred_asis.sum()/bb.units_produced.sum(),5))
out={}
for X in ['Alpha','Beta','Gamma']:
    t=bb.copy(); t['supplier_name']=X; t['cycle_time_s']=recipe[X]
    p=mf.predict(t)
    out[X]=(p*t.units_produced).sum()/t.units_produced.sum()
    print(X, round(out[X],6))
print('lowest:', min(out,key=out.get))
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from base import *
m=pd.read_csv(D+'maintenance.csv',dtype=str)
print(m.event.value_counts().to_dict()); print(m.note.dropna().unique()[:10])
mc=m[m.event=='mold_cleaning'].copy(); mc['date']=pd.to_datetime(mc.date)
print(mc.groupby('line').date.agg(['min','max','count']).to_string())
for ln,g in mc.groupby('line'):
    d=g.date.sort_values().diff().dt.days
    print(ln,'gaps', d.describe().round(1).to_dict(), 'gaps>14:', (d>14).sum(), list(d[d>14].astype(int)))
print(m[m.event!='mold_cleaning'].to_string())
print('dup cleanings same line/date:', mc.duplicated(['line','date']).sum())
print(mc.date.dt.dayofweek.value_counts().sort_index().to_dict())
" 2>&1 | grep -v -i warn

cd $TMPDIR/work && cat > clean_sched.py <<'EOF'
from final import *
mt=pd.read_csv(D+'maintenance.csv',dtype=str)
mc=mt[mt.event=='mold_cleaning'].copy(); mc['date']=pd.to_datetime(mc.date)
def days_since(df, sched):
    out=np.full(len(df),np.nan)
    for ln,g in df.groupby('line'):
        cs=np.sort(sched[sched.line==ln].date.values)
        idx=np.searchsorted(cs,g.date.values,side='right')-1
        out[df.index.get_indexer(g.index)]=np.where(idx>=0,(g.date.values-cs[np.maximum(idx,0)]).astype('timedelta64[D]').astype(float),np.nan)
    return out
def counterfactual_sched(sched,interval=14):
    rows=[]
    for ln,g in sched.groupby('line'):
        cs=sorted(g.date)
        extra=[]
        last=cs[0]
        allc=set(cs)
        t=min(cs)
        end=pd.Timestamp('2025-09-30')
        # walk through time; whenever 14 days since last cleaning, add a cleaning on that day
        cur=pd.Timestamp('2024-12-29') if False else last
        days=pd.date_range(min(cs),end)
        last=None
        for dday in days:
            if dday in allc: last=dday; continue
            if last is not None and (dday-last).days>=interval:
                extra.append(dday); last=dday
        rows+= [(ln,x) for x in sorted(allc.union(extra))]
    return pd.DataFrame(rows,columns=['line','date'])
EOF
python3 -c "
from clean_sched import *
b0=bb.copy()
b0['ds']=days_since(bb,mc)
print('missing ds', b0.ds.isna().sum(), b0.ds.describe().round(1).to_dict())
b0['dsbin']=pd.cut(b0.ds,[-1,3,6,9,12,14,17,21,28,40])
g=b0.groupby('dsbin',observed=True).agg(d=('d','sum'),u=('units_produced','sum'),n=('d','size'))
g['raw']=(g.d/g.u).round(4); print(g.to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from clean_sched import *
bb['ds']=days_since(bb,mc)
bb['ds_cap']=np.minimum(bb.ds,14)
bb['ds_over']=np.maximum(bb.ds-14,0)
base=mf
for name,term in [('linear','ds'),('capped at14 + excess','ds_cap + ds_over'),('bins','C(pd.cut(ds,[-1,6,13,20,40]))')]:
    m=fit(Y+FULL+' + '+term,bb)
    print(name,'llf',round(m.llf,1),'dAIC vs base',round(2*(m.llf-base.llf)*-1+2*(len(m.params)-len(base.params)),1))
    print(m.params[[p for p in m.params.index if 'ds' in p or 'pd.cut' in p]].round(4).to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from clean_sched import *
bb['ds']=days_since(bb,mc)
cf=counterfactual_sched(mc,14)
print('actual cleanings',len(mc),'counterfactual',len(cf),'added',len(cf)-len(mc))
print(cf.groupby('line').size().to_dict())
bb['ds_cf']=days_since(bb,cf)
print('ds_cf max', bb.ds_cf.max(), 'mean actual', round(bb.ds.mean(),2), 'mean cf', round(bb.ds_cf.mean(),2))
m=fit(Y+FULL+' + ds',bb)
bb['p0']=m.predict(bb)
t=bb.copy(); t['ds']=t.ds_cf
bb['p1']=m.predict(t)
A=lambda p: (p*bb.units_produced).sum()/bb.units_produced.sum()
print('observed', round(bb.d.sum()/bb.units_produced.sum(),6))
print('model baseline', round(A(bb.p0),6), 'counterfactual', round(A(bb.p1),6))
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from clean_sched import *
# A4: median actual mold temp (C), L1 post-swap corrected by estimated sensor offset
a=pd.read_pickle('clean_b.pkl')
raw=a.mold_temp.copy()
print('A4 median (offset applied in clean_b):', round(a.mold_temp.median(),4), a.mold_temp.notna().sum())
for off in [10,11,12]:
    p=a.copy(); post=(p.line=='L1')&(p.date>='2025-04-14')
    v=p.assign(m=p.mold_temp)
    # clean_b already has offset 11; rebuild from raw
    base=clean()
    base['m']=base.mold_temp+np.where((base.line=='L1')&(base.date>='2025-04-14'),11-off,0)
    print('offset',off,'median',round(base.m.median(),4))
base=clean()
print('A4 no sensor correction median', round(base.mold_temp.median(),4))
" 2>&1 | grep -v -i warn

cd $TMPDIR/work && python3 -c "
from clean_sched import *
base=clean()
post=(base.line=='L1')&(base.date>='2025-04-14')
for off in [0,10,11,12]:
    m=base.mold_temp-np.where(post,off,0)
    print('offset',off,'median',round(m.median(),4),'n',m.notna().sum())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from clean_sched import *
full=prep()  # all 3000 batches, L3 converted, L1 uncorrected
post=(full.line=='L1')&(full.date>='2025-04-14')
full['mold_temp']=full.mold_temp-np.where(post,11,0)
full['step_L2']=((full.line=='L2')&(full.date>='2025-06-15')).astype(int)
full['step_L3']=((full.line=='L3')&(full.date>='2025-07-21')).astype(int)
full['ds']=days_since(full,mc); full['ds_cf']=days_since(full,counterfactual_sched(mc,14))
# impute missing humidity by supplier median; missing mold by line-month median
full['humidity_pct']=full.humidity_pct.fillna(full.groupby('supplier_name').humidity_pct.transform('median'))
mm=full.groupby(['line',full.date.dt.month]).mold_temp.transform('median')
full['mold_temp']=full.mold_temp.fillna(mm)
print('nan left', full[['humidity_pct','mold_temp']].isna().sum().to_dict())
fit_df=full.dropna(subset=['mold_temp'])
m=fit(Y+FULL+' + ds',fit_df)
A=lambda p,df:(p*df.units_produced).sum()/df.units_produced.sum()
t=full.copy(); t['ds']=t.ds_cf
print('C3 imputed-all: baseline', round(A(m.predict(full),full),6), 'counterfactual', round(A(m.predict(t),t),6), 'observed', round(full.d.sum()/full.units_produced.sum(),6))
rec={'Alpha':30,'Beta':30,'Gamma':36}
for X in rec:
    t=full.copy(); t['supplier_name']=X; t['cycle_time_s']=rec[X]; t['ds']=full.ds
    print('C1 imputed', X, round(A(m.predict(t),t),6))
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from clean_sched import *
full=prep()
post=(full.line=='L1')&(full.date>='2025-04-14')
full['mold_temp']=full.mold_temp-np.where(post,11,0)
full['step_L2']=((full.line=='L2')&(full.date>='2025-06-15')).astype(int)
full['step_L3']=((full.line=='L3')&(full.date>='2025-07-21')).astype(int)
full['ds']=days_since(full,mc)
full['humidity_pct']=full.humidity_pct.fillna(full.groupby('supplier_name').humidity_pct.transform('median'))
full['mold_temp']=full.mold_temp.fillna(full.groupby(['line',full.date.dt.month]).mold_temp.transform('median'))
F2=Y+FULL+' + ds'
m=fit(F2,full); disp=m.pearson_chi2/m.df_resid
print('disp',round(disp,3))
for t in ['machine_age_years','ambient_temp_c','mold_temp','cycle_time_s','C(operator_id)','C(shift)']:
    red=(F2.replace(' + '+t,'')) if (' + '+t) in F2 else F2.replace(t+' + ','')
    s,dfd,p=lr(F2,red,full,disp); print(f'{t:20s} LR={s:9.2f} df={dfd} p={p:.2e}')
red=F2.replace(' + humidity_pct*C(supplier_name) + I(humidity_pct**2)*C(supplier_name)','')
s,dfd,p=lr(F2,red,full,disp); print(f'{\"humidity (all terms)\":20s} LR={s:9.2f} df={dfd} p={p:.2e}')
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from clean_sched import *
full=prep()
post=(full.line=='L1')&(full.date>='2025-04-14')
full['mold_temp']=full.mold_temp-np.where(post,11,0)
full['step_L2']=((full.line=='L2')&(full.date>='2025-06-15')).astype(int)
full['step_L3']=((full.line=='L3')&(full.date>='2025-07-21')).astype(int)
full['ds']=days_since(full,mc)
full['humidity_pct']=full.humidity_pct.fillna(full.groupby('supplier_name').humidity_pct.transform('median'))
full['mold_temp']=full.mold_temp.fillna(full.groupby(['line',full.date.dt.month]).mold_temp.transform('median'))
F2=Y+FULL+' + ds'
v=full.dropna(subset=['humidity_pct']).copy()
v=v[v.mold_temp.notna()]
for lbl,data in [('imputed-all',full),('valid rows only',bb.assign(ds=days_since(bb,mc)))]:
    m=fit(F2,data); disp=m.pearson_chi2/m.df_resid
    s,dfd,p=lr(F2,F2.replace(' + C(operator_id)',''),data,disp)
    print(lbl,'operator LR',round(s,2),'df',dfd,'p',round(p,4),'amb LR p', round(lr(F2,F2.replace(' + ambient_temp_c',''),data,disp)[2],4))
m=fit(F2,full); disp=m.pearson_chi2/m.df_resid
ops=m.params[[i for i in m.params.index if 'operator' in i]]
print(pd.DataFrame({'coef':ops.round(3),'p':m.pvalues[ops.index].round(4)}).to_string())
" 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && cat > perm.py <<'EOF'
from clean_sched import *
import time
full=prep()
post=(full.line=='L1')&(full.date>='2025-04-14')
full['mold_temp']=full.mold_temp-np.where(post,11,0)
full['step_L2']=((full.line=='L2')&(full.date>='2025-06-15')).astype(int)
full['step_L3']=((full.line=='L3')&(full.date>='2025-07-21')).astype(int)
full['ds']=days_since(full,mc)
full['humidity_pct']=full.humidity_pct.fillna(full.groupby('supplier_name').humidity_pct.transform('median'))
full['mold_temp']=full.mold_temp.fillna(full.groupby(['line',full.date.dt.month]).mold_temp.transform('median'))
F2=Y+FULL+' + ds'
RED=F2.replace(' + C(operator_id)','')
mf=fit(F2,full); disp=mf.pearson_chi2/mf.df_resid
mr=fit(RED,full)
obs=2*(mf.llf-mr.llf)/disp
print('observed LR',round(obs,2),flush=True)
rng=np.random.default_rng(0)
null=[]
t0=time.time()
for k in range(30):
    d=full.copy()
    for ln,g in d.groupby('line'):
        d.loc[g.index,'operator_id']=rng.permutation(g.operator_id.values)
    m1=fit(F2,d); m0=fit(RED,d)
    null.append(2*(m1.llf-m0.llf)/disp)
print('time',round(time.time()-t0),'s')
null=np.array(null)
print('null mean',round(null.mean(),2),'null 95th',round(np.quantile(null,0.95),2),'max',round(null.max(),2),'perm p',round((np.sum(null>=obs)+1)/(len(null)+1),4))
EOF
timeout 900 python3 perm.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && sed -i 's/for k in range(30):/for k in range(300):/' perm.py && timeout 900 python3 perm.py 2>&1 | grep -v -i warn | grep -v wls

cd $TMPDIR/work && python3 -c "
from perm import *
" >/dev/null 2>&1; cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn | grep -v wls
import sys
sys.argv=['x']
exec(open('perm.py').read().split('RED=')[0])
RED=F2.replace(' + C(operator_id)','')
for ln in ['L1','L2','L3','L4']:
    d=full[full.line==ln]
    F_=F2.replace(' + C(line)','').replace(' + step_L2','').replace(' + step_L3','')
    m1=fit(F_,d); m0=fit(F_.replace(' + C(operator_id)',''),d); disp=m1.pearson_chi2/m1.df_resid
    s=2*(m1.llf-m0.llf)/disp
    from scipy import stats
    print(ln,'operator LR',round(s,2),'df',int(m1.df_model-m0.df_model),'p',round(stats.chi2.sf(s,m1.df_model-m0.df_model),4))
EOF

cd $TMPDIR/work && python3 - <<'EOF' 2>&1 | grep -v -i warn | grep -v wls
exec(open('perm.py').read().split('RED=')[0])
m=fit(F2,full)
s=full[full.supplier_name=='Alpha'].copy()
grid=np.round(np.arange(12.1,72.31,0.1),1)
avg=[]
for h in grid:
    t=s.copy(); t['humidity_pct']=h
    avg.append((m.predict(t)*t.units_produced).sum()/t.units_produced.sum())
avg=np.array(avg); i=avg.argmin()
print('C2 Alpha optimum humidity (ds model, imputed):', grid[i], round(avg[i],6))
print('quadratic vertex (logit):', round(-m.params['humidity_pct']/(2*m.params['I(humidity_pct ** 2)']),2))
EOF
