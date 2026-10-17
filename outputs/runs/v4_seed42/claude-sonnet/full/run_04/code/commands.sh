cd /tmp/edabench_claude_y16ewxjw; ls; for f in *.csv; do echo == $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/a.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.describe().T)
for c in ['production_date','line','shift','operator_id','supplier_code']:
    print(b[c].value_counts(dropna=False).head(30))
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(b[c],errors='coerce')
    print(c,x.isna().sum(),x.describe().to_dict()); print(b[c][x.isna()].value_counts(dropna=False).head())
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id');print(d.head(10).to_string())
E
python3 -I $TMPDIR/a.py; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c

cd /tmp/edabench_claude_y16ewxjw; grep -v "mold_cleaning," maintenance.csv; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv',dtype=str).drop_duplicates()
print(len(b),b.batch_id.nunique())
def pd_(s):
    if '/' in s: return pd.to_datetime(s,format='%m/%d/%Y')
    return pd.to_datetime(s)
b['date']=b.production_date.map(pd_)
print(b.date.min(),b.date.max())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    b[c]=pd.to_numeric(b[c])
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sc']=b.supplier_code.str.strip().str.upper()
print(b.mold_temp.round(-1).value_counts().sort_index())
print(b.groupby('line').mold_temp.describe())
print((b.humidity_pct<=0).sum(), b.humidity_pct.isna().sum(), b.humidity_pct.max())
b.to_pickle('b.pkl')
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/c.py <<'E'
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str).drop_duplicates().reset_index(drop=True)
s=b.production_date
sl=s[s.str.contains('/')]
p=sl.str.split('/',expand=True).astype(int)
print((p[0]>12).sum(),(p[1]>12).sum(),len(p))
b['kind']=s.map(lambda x:'iso' if '-' in x else 'sl')
print(b.kind.map({'iso':0,'sl':1}).values[:60])
# does slash format relate to position?
print(b[b.kind=='sl'].index.to_series().describe())
print(b.head(30)[['production_date','line']])
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/b.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv',dtype=str).drop_duplicates().reset_index(drop=True)
def pdt(r):
    s=r.production_date
    if '-' in s: return pd.to_datetime(s)
    a,c,y=map(int,s.split('/'))
    return pd.Timestamp(y,a,c) if r.line=='L1' else pd.Timestamp(y,c,a)
for l,g in b.groupby('line'):
    s=g.production_date; print(l,s.str.contains('-').sum(),s.str.contains('/').sum())
    sl=g[g.production_date.str.contains('/')].production_date.str.split('/',expand=True).astype(int)
    print((sl[0]>12).sum(),(sl[1]>12).sum())
b['date']=b.apply(pdt,axis=1)
print(b.date.min(),b.date.max())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    b[c]=pd.to_numeric(b[c])
b['shift']=b['shift'].str.strip().str.upper().str[0]
b['sc']=b.supplier_code.str.strip().str.upper()
print(b.groupby('line').mold_temp.describe())
print(b.mold_temp.round(-1).value_counts().sort_index())
print((b.humidity_pct<=0).sum(), b.humidity_pct.isna().sum(), b.humidity_pct.max(), (b.humidity_pct<0).sum())
b.to_pickle('b.pkl')
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_y16ewxjw; sed -i 's/^    sl=g\[.*$/    sl=g[g.production_date.str.contains("\/")].production_date.str.split("\/",expand=True).astype(int) if "\/" in "".join(s) else pd.DataFrame([[0,0]])/' $TMPDIR/b.py; python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/d.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b.pkl')
b['dr']=b.defective_units/b.units_produced
print('A1',len(b),'A2',(b.humidity_pct.isna()|(b.humidity_pct<0)).sum(), b.humidity_pct[b.humidity_pct<=0].unique())
print('A3',b.defective_units.sum()/b.units_produced.sum())
b['mt']=np.where(b.line=='L3',(b.mold_temp-32)*5/9,b.mold_temp)
b.loc[b.mold_temp==0,'mt']=np.nan
print('A4',b.mt.median())
print(b.groupby('line').mt.describe())
b['m']=b.date.dt.to_period('M')
print(b[b.line=='L1'].groupby('m').mt.agg(['mean','median',lambda x:(x.isna()).sum()]))
print(b.groupby('line').date.apply(lambda s:s.dt.to_period('M').value_counts().sort_index().to_dict()))
b.to_pickle('b2.pkl')
E
python3 -I $TMPDIR/d.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b2.pkl')
l=b[b.line=='L1'].copy()
l['w']=l.date.dt.to_period('W')
print(l.groupby('w').agg(mt=('mt','mean'),dr=('dr','mean'),n=('dr','size')).loc['2025-02':'2025-06'].to_string())
E
python3 -I $TMPDIR/e.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
g=b.dropna(subset=['mt'])
r=smf.ols('mt~ambient_temp_c+C(line)+post+cycle_time_s+machine_age_years',g).fit();print(r.summary().tables[1])
l=g[g.line=='L1'];
r=smf.ols('mt~ambient_temp_c+post+cycle_time_s',l).fit();print(r.params)
print(g.groupby(['line','post']).mt.median())
E
python3 -I $TMPDIR/f.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b2.pkl')
s=pd.read_csv('suppliers.csv');s['sc']=s.supplier_code
b=b.merge(s[['sc','supplier_name','recipe_cycle_time_s','pre_dried']],on='sc')
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
b['mtc']=b.mt-np.where(b.post==1,7,0)
b['ctd']=b.cycle_time_s-b.recipe_cycle_time_s
b['ok']=b.units_produced-b.defective_units
b['dow']=b.date.dt.dayofweek
b.to_pickle('b3.pkl')
g=b.dropna(subset=['mt','hum']).copy()
print(len(g))
for f in ['dr~mtc','dr~hum','dr~cycle_time_s','dr~ctd','dr~machine_age_years','dr~ambient_temp_c','dr~C(operator_id)','dr~shift','dr~supplier_name','dr~C(line)','dr~qc_inspection_min','dr~rework_cost_eur']:
    r=smf.ols(f,g).fit();print(f,round(r.rsquared,4),round(r.f_pvalue,5))
print(g.groupby(['supplier_name']).agg(dr=('dr','mean'),hum=('hum','mean'),ct=('ctd','mean'),mt=('mtc','mean')))
print(g.groupby(pd.cut(g.hum,[0,10,20,30,40,50,60,80])).dr.mean())
print(g.groupby([ 'supplier_name',pd.cut(g.hum,[0,10,20,30,40,50,60,80])]).dr.mean().unstack())
print(g.groupby(pd.cut(g.mtc,[180,195,200,205,210,215,220,225,230,245])).dr.mean())
print(g.groupby(pd.cut(g.ctd,[-20,-6,-3,-1,1,3,6,20])).dr.agg(['mean','size']))
E
python3 -I $TMPDIR/g.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b3.pkl')
g=b.dropna(subset=['mtc','hum']).copy()
g['hc']=(g.hum-35)
f='ok+defective_units~' 
base='mtc+I(mtc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+shift+C(supplier_name)+C(line)+hum+I(hum**2)'
def fit(f):
    return smf.glm('dr~'+f,g,family=sm.families.Binomial(),freq_weights=g.units_produced).fit(cov_type='HC0')
r=fit(base);print(r.summary().tables[1])
E
python3 -I $TMPDIR/h.py 2>&1 | grep -v "operator"

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/i.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b3.pkl')
print(pd.crosstab(b.operator_id,b.line).head(24))
print(b.groupby('line').machine_age_years.describe())
print(b.groupby('line').machine_age_years.apply(lambda s:s.round(1).value_counts().head(3).to_dict()))
print(b.groupby('shift').agg(a=('ambient_temp_c','mean'),ct=('cycle_time_s','mean'),dr=('dr','mean')))
E
python3 -I $TMPDIR/i.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/j.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b3.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
b['dsc']=b.apply(ds,axis=1)
print(b.dsc.describe(), b.dsc.isna().sum())
print(m.groupby('line').date.apply(lambda s:s.diff().dt.days.describe()))
print(b.groupby(pd.cut(b.dsc,[-1,0,3,6,9,12,14,17,20,25,30,60,200])).dr.agg(['mean','size']))
b.to_pickle('b4.pkl')
E
python3 -I $TMPDIR/j.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/k.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0); b['dsc_']=b.dsc
g=b.dropna(subset=['mtc','hum']).copy()
def fit(f,d=g):
    return smf.glm('dr~'+f,d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit()
base='mtc+I(mtc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+shift+C(supplier_name)*(hum+I(hum**2))+over'
r=fit(base);print(r.params.to_string());print(r.bse.round(4).to_string())
# dispersion
print('pearson disp',r.pearson_chi2/r.df_resid)
# LR for blocks (quasi): use scaled deviance
def lr(drop):
    f=base
    for x in drop: f=f.replace(x,'')
    return f
for name,f in [('no ops','mtc+I(mtc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(line)+shift+C(supplier_name)*(hum+I(hum**2))+over'),
  ('ops+line','mtc+I(mtc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(line)+shift+C(supplier_name)*(hum+I(hum**2))+over')]:
    r2=fit(f);print(name,r2.deviance,r.deviance,r2.df_resid, r.df_resid)
E
python3 -I $TMPDIR/k.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/k.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0)
g=b.dropna(subset=['mtc','hum']).copy()
def fit(f,d=g):
    return smf.glm('I(defective_units)+I(units_produced-defective_units)~'+f if False else 'cbind~'+f,d,family=sm.families.Binomial()).fit() if False else sm.GLM.from_formula('np.c_[defective_units,ok]~'+f,d,family=sm.families.Binomial()).fit(scale='X2')
H='C(supplier_name)*(hum+I(hum**2))'
base=f'mtc+I(mtc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(line)+shift+{H}+over'
r=fit(base);print(r.summary().tables[1]); print(r.scale)
for drop in ['machine_age_years','shift','ambient_temp_c','cycle_time_s','over']:
    r2=fit(base.replace('+'+drop,''));print(drop,'Δdev/scale',(r2.deviance-r.deviance)/r.scale)
r2=fit(base.replace('+C(line)','').replace('+machine_age_years','')+'+C(operator_id)'); print('ops only',(r2.deviance-r.deviance)/r.scale)
r3=fit(base+'+C(operator_id)'); print('ops add',(r.deviance-r3.deviance)/r.scale, 'dfs',r.df_resid-r3.df_resid)
g['res']=g.dr-r.predict(g)
g['m']=g.date.dt.to_period('M')
print(g.groupby(['line','m']).apply(lambda d:(d.defective_units.sum()-(r.predict(d)*d.units_produced).sum())/d.units_produced.sum()).unstack(0).round(4))
E
python3 -I $TMPDIR/k.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/l.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0)
g=b.dropna(subset=['mtc','hum']).copy()
f='dr~mtc+I(mtc**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(line)+shift+C(supplier_name)*(hum+I(hum**2))+over'
r=smf.ols(f,g).fit();print(r.summary().tables[1],r.rsquared,np.sqrt(r.scale))
r2=smf.ols(f+'+C(operator_id)',g).fit();print(r2.compare_f_test(r))
g['res']=r.resid;g['m']=g.date.dt.to_period('M')
print(g.groupby(['m','line']).res.mean().unstack().round(4))
E
python3 -I $TMPDIR/l.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_y16ewxjw; cat >> $TMPDIR/l.py <<'E'
for l in ['L1','L2','L3','L4']:
    d=g[g.line==l].sort_values('date');best=None
    ds=sorted(d.date.unique())
    out=[]
    for t in ds[20:-20]:
        a=d.res[d.date<t];c=d.res[d.date>=t]
        out.append((len(a)*len(c)/len(d)*(a.mean()-c.mean())**2,t,a.mean(),c.mean()))
    o=max(out);print(l,o)
d=g[g.line=='L2'].set_index('date').res.resample('W').mean();print(d['2025-04':'2025-08'].round(3).to_string())
E
python3 -I $TMPDIR/l.py 2>&1 | tail -30

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/m.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0)
b['regL2']=((b.line=='L2')&(b.date>='2025-06-17')).astype(int)
g=b.dropna(subset=['mtc','hum']).copy()
H='C(supplier_name)*(hum+I(hum**2))'
for name,t in [('mtc','mtc'),('mt','mt'),('none','1'),('mtc+amb','mtc+ambient_temp_c'),('mt+amb','mt+ambient_temp_c'),('amb','ambient_temp_c')]:
    f=f'dr~{t}+cycle_time_s+machine_age_years+C(line)+shift+{H}+over+regL2'
    r=smf.ols(f,g).fit();print(name,round(r.rsquared,4),round(r.ssr,4),r.params.get('mtc',r.params.get('mt',np.nan)),r.params.get('ambient_temp_c',np.nan))
E
python3 -I $TMPDIR/m.py 2>&1 | tail

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/n.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0)
b['regL2']=((b.line=='L2')&(b.date>='2025-06-17')).astype(int)
H='C(supplier_name)*(hum+I(hum**2))'
for off in [0,4,6,7,8,9,10,12,14]:
    b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),off,0)
    g=b.dropna(subset=['mtc','hum'])
    r=smf.ols(f'dr~mtc+cycle_time_s+machine_age_years+C(line)+shift+{H}+over+regL2',g).fit();print(off,round(r.ssr,4),r.params['mtc'])
E
python3 -I $TMPDIR/n.py 2>&1 | tail

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/o.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0)
b['regL2']=((b.line=='L2')&(b.date>='2025-06-17')).astype(int)
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
g=b.dropna(subset=['mtc','hum']).copy()
H='C(supplier_name)*(hum+I(hum**2))'
r=smf.ols(f'dr~mtc+cycle_time_s+ctd+machine_age_years+C(line)+shift+{H}+over+regL2',g).fit();print(r.summary().tables[1])
g['res']=r.resid;g['m']=g.date.dt.to_period('M')
print(g.groupby(['m','line']).res.mean().unstack().round(4))
print(g.groupby(['line','sc']).size().unstack())
E
python3 -I $TMPDIR/o.py 2>&1 | tail -60

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0)
b['regL2']=((b.line=='L2')&(b.date>='2025-06-17')).astype(int)
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
g=b.dropna(subset=['mtc','hum']).copy()
H='C(supplier_name)*(hum+I(hum**2))'
for cv in ['cycle_time_s','ctd','cycle_time_s+ctd']:
    r=smf.ols(f'dr~mtc+{cv}+C(line)+shift+{H}+over+regL2',g).fit();print(cv,r.ssr)
r=smf.ols(f'dr~mtc+ctd+C(line)+shift+{H}+over+regL2',g).fit()
g['res']=r.resid
for l in ['L2','L3']:
    d=g[g.line==l].set_index('date');print(l);print(d.res.resample('W').mean()['2025-05':].round(3).to_string())
    print(d.mt.resample('M').mean().round(1).to_string())
E
python3 -I $TMPDIR/p.py 2>&1 | tail -90

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/q.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0)
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
H='C(supplier_name)*(hum+I(hum**2))'
g0=b.dropna(subset=['mtc','hum']).copy()
for l in ['L1','L2','L3','L4']:
    res=[]
    for t in pd.date_range('2025-02-15','2025-09-10'):
        g=g0.copy();g['reg']=((g.line==l)&(g.date>=t)).astype(int)
        r=smf.ols(f'dr~mtc+ctd+C(line)+shift+{H}+over+reg',g).fit();res.append((r.ssr,t,r.params['reg']))
    res.sort();print(l,res[:3])
E
python3 -I $TMPDIR/q.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/r.py <<'E'
import pandas as pd,numpy as np
b=pd.read_pickle('b4.pkl')
for l in ['L2','L3']:
    d=b[b.line==l].copy();d['p']=np.where(d.date<('2025-06-16' if l=='L2' else '2025-07-21'),0,1)
    print(l);print(d.groupby('p').agg(n=('dr','size'),dr=('dr','mean'),mt=('mt','mean'),amb=('ambient_temp_c','mean'),hum=('hum','mean'),ct=('ctd','mean'),dsc=('dsc','mean'),age=('machine_age_years','mean'),night=('shift',lambda s:(s=='N').mean()),units=('units_produced','mean'),qc=('qc_inspection_min','mean'),rw=('rework_cost_eur','mean')))
    print(pd.crosstab(d.p,d.sc,normalize='index').round(2))
d=b[b.line=='L3'];print(d.groupby(d.date.dt.to_period('M')).agg(dr=('dr','mean'),mt=('mt','mean'),amb=('ambient_temp_c','mean'),hum=('hum','mean')))
E
python3 -I $TMPDIR/r.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/s.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
print(b[['dr','defective_units','units_produced','qc_inspection_min','rework_cost_eur','cycle_time_s']].corr().round(3))
b['p3']=((b.line=='L3')&(b.date>='2025-07-21'))
for nm,f in [('qc','qc_inspection_min~defective_units+units_produced+C(line)'),('rw','rework_cost_eur~defective_units+units_produced')]:
    r=smf.ols(f,b).fit();print(nm,r.rsquared);print(r.params.round(3).to_dict())
r=smf.ols('qc_inspection_min~defective_units+units_produced+p3+C(line)',b).fit();print(r.params.round(3).to_dict(),r.rsquared)
r=smf.ols('qc_inspection_min~dr+C(line)',b).fit();print(r.params.round(3).to_dict(),r.rsquared)
l3=b[b.line=='L3'];print(l3.groupby(l3.date.dt.to_period('M')).qc_inspection_min.mean())
print(b.groupby('line').qc_inspection_min.mean())
E
python3 -I $TMPDIR/s.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/t.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['over']=np.maximum(b.dsc-14,0)
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
b['p3']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
H='C(supplier_name)*(hum+I(hum**2))'
g0=b.dropna(subset=['mtc','hum']).copy()
res=[]
for t in pd.date_range('2025-05-20','2025-07-10'):
    g=g0.copy();g['reg']=((g.line=='L2')&(g.date>=t)).astype(int)
    r=smf.ols(f'dr~mtc+ctd+C(line)+shift+{H}+over+reg+p3',g).fit();res.append((round(r.ssr,5),t.date()))
print(sorted(res)[:6])
g=g0.copy();r=smf.ols(f'dr~mtc+ctd+C(line)+shift+{H}+over+p3',g).fit();g['res']=r.resid
d=g[(g.line=='L2')&(g.date>='2025-06-05')&(g.date<='2025-06-28')]
print(d.groupby('date').agg(res=('res','mean'),dr=('dr','mean'),n=('dr','size')).round(3).to_string())
E
python3 -I $TMPDIR/t.py

cd /tmp/edabench_claude_y16ewxjw; cat >> $TMPDIR/t.py <<'E'
res=[]
for t in pd.date_range('2025-06-05','2025-06-25'):
    g=g0.copy();g['reg']=((g.line=='L2')&(g.date>=t)).astype(int)
    r=smf.wls(f'dr~mtc+ctd+C(line)+shift+{H}+over+reg+p3',g,weights=g.units_produced).fit();res.append((round(r.ssr,5),round(r.llf,2),t.date()))
print(sorted(res)[:5])
E
python3 -I $TMPDIR/t.py | tail -1

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/u.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
b['p3']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b['regL2']=((b.line=='L2')&(b.date>='2025-06-17')).astype(int)
g=b.dropna(subset=['mtc','hum']).copy()
g['mb']=pd.cut(g.mtc,[0,195,200,205,208,211,214,217,220,223,226,230,250])
g['cb']=pd.cut(g.cycle_time_s,[0,24,27,29,31,33,35,37,39,50])
g['db']=pd.cut(g.dsc,[-1,0,2,4,6,8,10,12,14,16,18,21,25,40])
g['hb']=pd.cut(g.hum,[0,10,15,20,25,30,35,40,45,50,55,60,80])
f='dr~C(mb)+C(cb)+C(db)+C(sc)*C(hb)+C(line)+shift+p3+regL2'
r=smf.ols(f,g).fit();print(r.rsquared,r.ssr)
for k in ['mb','cb','db']:
    print(r.params[[i for i in r.params.index if f'C({k})' in i]].round(4).to_string())
print(r.params[[i for i in r.params.index if 'hb' in i]].round(3).to_string())
E
python3 -I $TMPDIR/u.py

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/v.py <<'E'
import pandas as pd,numpy as np, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
b['p3']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b['regL2']=((b.line=='L2')&(b.date>='2025-06-17')).astype(int)
b['over']=np.maximum(b.dsc-14,0)
g=b.dropna(subset=['mtc','hum']).copy()
H='C(sc)*(hum+I(hum**2))'
base=f'dr~mtc+cycle_time_s+{H}+C(line)+shift+p3+regL2'
for nm,x in [('lin','dsc'),('hinge','over'),('both','dsc+over'),('quad','dsc+I(dsc**2)'),('none','1'),('hinge10','I(np.maximum(dsc-10,0))'),('hinge7','I(np.maximum(dsc-7,0))')]:
    r=smf.ols(base+'+'+x,g).fit();print(nm,round(r.ssr,4),r.params.filter(regex='dsc|over|maximum').round(5).to_dict())
r=smf.ols(base+'+dsc+machine_age_years+ambient_temp_c+C(operator_id)',g).fit()
print(r.summary().tables[1])
E
python3 -I $TMPDIR/v.py 2>&1 | grep -v "operator_id\|Warn"

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/w.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
b['p3']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b['regL2']=((b.line=='L2')&(b.date>='2025-06-17')).astype(int)
g=b.dropna(subset=['mtc','hum']).copy()
f='dr~mtc+cycle_time_s+C(sc)*(hum+I(hum**2))+C(line)+shift+p3+regL2+dsc'
w=lambda d:d.units_produced
r=smf.wls(f,g,weights=g.units_produced).fit();print(r.params.round(5).to_dict())
r0=smf.ols(f,g).fit()
# glm log link
rl=smf.glm(f,g,family=sm.families.Poisson(),freq_weights=None).fit(); 
print('dsc coef ols',r0.params['dsc'],'wls',r.params['dsc'])
for nm,m in [('ols',r0),('wls',r)]:
    b2=b.copy(); b2['dsc2']=b.dsc%14
    d=m.params['dsc']*(b2.dsc2-b2.dsc)
    new=((b.dr+d)*b.units_produced).sum()/b.units_produced.sum()
    print(nm,'C3',new, 'min14', (((b.dr+m.params['dsc']*(np.minimum(b.dsc,14)-b.dsc))*b.units_produced).sum()/b.units_produced.sum()))
# multiplicative alternative
g['lg']=np.log(g.dr)
rm=smf.wls('lg~mtc+cycle_time_s+C(sc)*(hum+I(hum**2))+C(line)+shift+p3+regL2+dsc',g).fit();print('log dsc',rm.params['dsc'],rm.rsquared, 'ols r2',r0.rsquared)
# C1 
for nm,m in [('ols',r0),('wls',r)]:
    rec={'SP-01':30,'SP-02':30,'SP-03':36}
    full=b.dropna(subset=['mtc','hum'])
    for s in rec:
        d=full.copy();d['sc']=s;d['cycle_time_s']=rec[s]
        p=m.predict(d);print(nm,s,(p*d.units_produced).sum()/d.units_produced.sum())
# C2
for nm,m in [('ols',r0),('wls',r)]:
    d=full.copy();d['sc']='SP-01'
    hs=np.arange(5,73,0.1);out=[]
    for h in hs:
        d['hum']=h;out.append((m.predict(d)*d.units_produced).mean())
    print(nm,'C2',hs[np.argmin(out)])
print(g.groupby('sc').hum.describe())
E
python3 -I $TMPDIR/w.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/x.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
b['p3']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b['regL2']=((b.line=='L2')&(b.date>='2025-06-17')).astype(int)
b['off']=np.log(b.units_produced)
g=b.dropna(subset=['mtc','hum']).copy()
f='defective_units~mtc+cycle_time_s+C(sc)*(hum+I(hum**2))+C(line)+shift+p3+regL2+dsc'
m=smf.glm(f,g,family=sm.families.Poisson(),offset=g.off).fit(scale='X2');print(m.summary().tables[1],m.scale)
m2=smf.glm(f+'+machine_age_years+ambient_temp_c+C(operator_id)',g,family=sm.families.Poisson(),offset=g.off).fit(scale='X2')
print(m2.params.filter(regex='age|ambient').to_dict(),m2.pvalues.filter(regex='age|ambient').to_dict())
ops=[i for i in m2.params.index if 'operator' in i]; print(m2.wald_test(' , '.join(f'{o}=0' for o in ops),scalar=True))
full=b.dropna(subset=['mtc','hum'])
rec={'SP-01':30,'SP-02':30,'SP-03':36}
for s in rec:
    d=full.copy();d['sc']=s;d['cycle_time_s']=rec[s];d['off']=np.log(d.units_produced)
    p=m.predict(d,offset=d.off);print(s,p.sum()/d.units_produced.sum())
d=full.copy();d['sc']='SP-01'
hs=np.arange(5,73,0.1);out=[]
for h in hs:
    d['hum']=h;out.append(m.predict(d,offset=d.off).sum())
print('C2',hs[np.argmin(out)])
# C3
new=b.defective_units*np.exp(m.params['dsc']*((b.dsc%14)-b.dsc))
print('C3',new.sum()/b.units_produced.sum(), 'dsc',m.params['dsc'])
new=b.defective_units*np.exp(m.params['dsc']*(np.minimum(b.dsc,14)-b.dsc));print('C3 cap',new.sum()/b.units_produced.sum())
E
python3 -I $TMPDIR/x.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_y16ewxjw; cat > $TMPDIR/y.py <<'E'
import pandas as pd,numpy as np, statsmodels.api as sm, statsmodels.formula.api as smf
b=pd.read_pickle('b4.pkl')
for off in [6.4,7,7.3,8]:
    print(off,(b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),off,0)).median())
b['mtc']=b.mt-np.where((b.line=='L1')&(b.date>='2025-04-14'),7.3,0)
b['p3']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
g=b.dropna(subset=['mtc','hum']).copy();g['off']=np.log(g.units_produced)
res=[]
for t in pd.date_range('2025-06-08','2025-06-24'):
    g['regL2']=((g.line=='L2')&(g.date>=t)).astype(int)
    m=smf.glm('defective_units~mtc+cycle_time_s+C(sc)*(hum+I(hum**2))+C(line)+shift+p3+regL2+dsc',g,family=sm.families.Poisson(),offset=g.off).fit()
    res.append((round(-m.llf,2),t.date()))
print(sorted(res)[:5])
E
python3 -I $TMPDIR/y.py 2>&1 | grep -v Warn
