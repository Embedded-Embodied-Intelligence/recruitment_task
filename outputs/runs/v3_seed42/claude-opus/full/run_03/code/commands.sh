cd /tmp/edabench_claude_3kgv93q3; ls; head -5 *.csv; wc -l *.csv; python3 -c "
import pandas as pd
for f in ['batches','suppliers','maintenance']:
    d=pd.read_csv(f+'.csv'); print(f, d.dtypes, d.describe(include='all').T.to_string(), sep='\n')
"

cd /tmp/edabench_claude_3kgv93q3; cat maintenance.csv | grep -v ",mold_cleaning,$"; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv')
for c in ['shift','supplier_code','line']: print(d[c].value_counts())
dup=d[d.batch_id.duplicated(keep=False)].sort_values('batch_id'); print(dup.head(10).to_string()); print((dup.groupby('batch_id').nunique()>1).sum())
print(d.mold_temp.describe()); import numpy as np
print(np.histogram(d.mold_temp,bins=[-1,1,100,150,180,200,250,300,380,400,420,460]))
print(d.humidity_pct.isna().sum(), (d.humidity_pct<=0).sum(), (d.humidity_pct>100).sum(), d.humidity_pct.value_counts().head())
print(d.units_produced.sort_values().tail(20).values)
"

cd /tmp/edabench_claude_3kgv93q3; cat > $TMPDIR/clean.py <<'EOF'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv').drop_duplicates()
assert d.batch_id.is_unique
d['production_date']=pd.to_datetime(d.production_date)
d['shift']=d['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
d['supplier_code']=d.supplier_code.str.strip().str.upper()
s=pd.read_csv('suppliers.csv'); d=d.merge(s,on='supplier_code',how='left')
d['hum']=d.humidity_pct.where(d.humidity_pct>0)
mt=d.mold_temp.replace(0,np.nan)
d['fahr']=mt>300
mt=np.where(mt>300,(mt-32)*5/9,mt)
d['mt_raw_c']=mt
d['rate']=d.defective_units/d.units_produced
EOF
cat > $TMPDIR/e1.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
print(len(d), d.hum.isna().sum(), d.defective_units.sum()/d.units_produced.sum())
d['m']=d.production_date.dt.to_period('M')
print(d.pivot_table(index='m',columns='line',values='mt_raw_c',aggfunc='median').round(1))
print(d.pivot_table(index='m',columns='line',values='rate',aggfunc='mean').round(4))
print(d.pivot_table(index='m',columns='line',values='fahr',aggfunc='mean').round(2))
print(d[['rate','qc_inspection_min','rework_cost_eur','units_produced']].corr())
print((d.rework_cost_eur/d.defective_units).describe())
EOF
python3 $TMPDIR/e1.py

cd /tmp/edabench_claude_3kgv93q3; cat > $TMPDIR/e2.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
l=d[d.line!='L1'].groupby('production_date').mt_raw_c.mean()
x=d[d.line=='L1'].groupby('production_date').mt_raw_c.mean()
print((x-l).loc['2025-04-01':'2025-04-25'].round(1))
print((x-l).loc[:'2025-04-13'].mean(),(x-l).loc['2025-04-14':].mean())
print(d[d.fahr & (d.line!='L3')].shape, d[(~d.fahr)&(d.line=='L3')][['mold_temp']].describe())
EOF
python3 $TMPDIR/e2.py

cd /tmp/edabench_claude_3kgv93q3; cat >> $TMPDIR/clean.py <<'EOF'
d['mt']=d.mt_raw_c-np.where((d.line=='L1')&(d.production_date>=pd.Timestamp('2025-04-14')),8.0,0)
m=pd.read_csv('maintenance.csv',parse_dates=['date']); mc=m[m.event=='mold_cleaning']
def dsc(r):
    p=mc[(mc.line==r.line)&(mc.date<=r.production_date)].date
    return (r.production_date-p.max()).days if len(p) else np.nan
d['dsc']=d.apply(dsc,axis=1)
EOF
cat > $TMPDIR/e3.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
print('A4',d.mt.median(), d.mt.notna().sum())
print(d.dsc.describe()); print(mc.groupby('line').date.apply(lambda s:s.diff().dt.days.describe()))
d['dscb']=pd.cut(d.dsc,[-1,0,3,7,10,14,18,22,30,60])
print(d.groupby('dscb').rate.agg(['mean','size']))
d['mtb']=pd.qcut(d.mt,10); print(d.groupby('mtb').rate.mean())
d['hb']=pd.cut(d.hum,8); print(d.pivot_table(index='hb',columns='supplier_name',values='rate'))
d['cb']=pd.qcut(d.cycle_time_s,8); print(d.groupby('cb').rate.mean())
for c in ['shift','operator_id','supplier_name','line']: print(d.groupby(c).rate.agg(['mean','size']))
EOF
python3 $TMPDIR/e3.py

cd /tmp/edabench_claude_3kgv93q3; cat > $TMPDIR/e4.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
import statsmodels.formula.api as smf
print(pd.crosstab(d.operator_id,d.line).T.to_string())
e=d.dropna(subset=['mt','hum']).copy()
e['lr']=np.log(e.rate)
f='lr ~ mt + C(supplier_name)*(hum+I(hum**2)) + cycle_time_s + dsc + I(np.maximum(dsc-14,0)) + machine_age_years + ambient_temp_c + C(shift) + C(operator_id)'
r=smf.ols(f,e).fit(); print(r.summary().tables[1])
e['res']=r.resid
e['w']=e.production_date.dt.to_period('W')
print(e.pivot_table(index='w',columns='line',values='res').round(2).to_string())
EOF
python3 $TMPDIR/e4.py

cd /tmp/edabench_claude_3kgv93q3; cat > $TMPDIR/e5.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
import statsmodels.formula.api as smf
e=d.dropna(subset=['mt','hum']).copy(); e['lr']=np.log(e.rate)
base='lr ~ mt + C(supplier_name)*(hum+I(hum**2)) + cycle_time_s + dsc + machine_age_years + ambient_temp_c + C(shift) + C(line)'
r=smf.ols(base,e).fit(); e['res']=r.resid
print(e[(e.line=='L2')&(e.production_date.between('2025-06-05','2025-06-25'))].groupby('production_date').res.agg(['mean','size']).round(2))
best=[]
for dt in pd.date_range('2025-05-15','2025-07-15'):
    e['reg']=((e.line=='L2')&(e.production_date>=dt)).astype(int)
    best.append((smf.ols(base+'+reg',e).fit().ssr,dt))
print(sorted(best)[:5])
EOF
python3 $TMPDIR/e5.py

cd /tmp/edabench_claude_3kgv93q3; cat > $TMPDIR/e6.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
import statsmodels.formula.api as smf
d['reg']=((d.line=='L2')&(d.production_date>='2025-06-16')).astype(int)
e=d.dropna(subset=['mt','hum']).copy(); e['lr']=np.log(e.rate)
f='lr ~ mt + C(supplier_name)*(hum+I(hum**2)) + cycle_time_s + C(np.minimum(dsc,30)) + machine_age_years + ambient_temp_c + C(shift) + C(line) + reg + C(operator_id)'
r=smf.ols(f,e).fit(); 
print(r.params.filter(like='dsc').round(3).to_string())
print(r.params.drop(r.params.filter(like='dsc').index).round(4).to_string()); print(r.pvalues[['machine_age_years','ambient_temp_c']])
print(r.compare_f_test(smf.ols(f.replace('+ C(operator_id)',''),e).fit()))
print(d.groupby('line')[['machine_age_years','ambient_temp_c']].agg(['mean','std']))
print(np.corrcoef(e.ambient_temp_c,e.mt)[0,1])
EOF
python3 $TMPDIR/e6.py

cd /tmp/edabench_claude_3kgv93q3; cat > $TMPDIR/e7.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['reg']=((d.line=='L2')&(d.production_date>='2025-06-16')).astype(int)
d['lu']=np.log(d.units_produced)
e=d.dropna(subset=['mt','hum']).copy()
f='defective_units ~ mt + C(supplier_name)*(hum+I(hum**2)) + cycle_time_s + dsc + C(shift) + C(line) + reg'
r=smf.glm(f,e,offset=e.lu,family=sm.families.Poisson()).fit(scale='X2')
print(r.params.round(5).to_string(), r.scale)
# check dsc nonlinearity & mt quadratic
r2=smf.glm(f+'+I(dsc**2)+I(mt**2)+I(hum**3)',e,offset=e.lu,family=sm.families.Poisson()).fit(scale='X2'); print(r2.params[-3:],r2.pvalues[-3:])
# C2
h=np.linspace(e.hum.min(),e.hum.max(),2001)
for s in ['Alpha','Beta','Gamma']:
    g=r.params; b1=g['hum']+g.get(f'C(supplier_name)[T.{s}]:hum',0); b2=g['I(hum ** 2)']+g.get(f'C(supplier_name)[T.{s}]:I(hum ** 2)',0)
    print(s,-b1/(2*b2))
print(e.hum.min(),e.hum.max())
# impute missing for prediction
full=d.copy()
for c in ['mt','hum']:
    full[c]=full[c].fillna(full.groupby(['line',full.production_date.dt.month])[c].transform('median'))
base=r.predict(full,offset=full.lu)
ratio=full.defective_units/base
def cf(df, keep_resid=True):
    p=r.predict(df,offset=df.lu)
    return (p*ratio).sum()/df.units_produced.sum() if keep_resid else p.sum()/df.units_produced.sum()
print('actual',d.defective_units.sum()/d.units_produced.sum(), 'model', base.sum()/d.units_produced.sum())
for s in ['Alpha','Beta','Gamma']:
    x=full.copy(); x['supplier_name']=s; print(s,cf(x),cf(x,False))
x=full.copy(); x['dsc']=x.dsc%14; print('C3',cf(x),cf(x,False))
EOF
python3 $TMPDIR/e7.py

cd /tmp/edabench_claude_3kgv93q3; cat > $TMPDIR/e8.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/clean.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
d['reg']=((d.line=='L2')&(d.production_date>='2025-06-16')).astype(int)
d['lu']=np.log(d.units_produced)
e=d.dropna(subset=['mt','hum']).copy()
print(e.groupby('supplier_name')[['hum','mt','cycle_time_s','dsc','reg']].mean())
print(pd.crosstab(e.line,e.supplier_name))
f='defective_units ~ mt + C(supplier_name)*bs(hum,df=5) + cycle_time_s + dsc + C(shift) + C(line) + reg'
r=smf.glm(f,e,offset=e.lu,family=sm.families.Poisson()).fit(scale='X2')
full=d.copy()
for c in ['mt','hum']:
    full[c]=full[c].fillna(full.groupby(['line',full.production_date.dt.month])[c].transform('median'))
base=r.predict(full,offset=full.lu); ratio=full.defective_units/base
for s in ['Alpha','Beta','Gamma']:
    x=full.copy(); x['supplier_name']=s; p=r.predict(x,offset=x.lu); print(s,(p*ratio).sum()/x.units_produced.sum())
h=pd.DataFrame({'hum':np.arange(12.5,72,0.5)}); 
for c,v in dict(mt=210,cycle_time_s=30,dsc=7,shift='Day',line='L1',reg=0,supplier_name='Alpha').items(): h[c]=v
for s in ['Alpha','Beta','Gamma']:
    h['supplier_name']=s; h[s]=r.predict(h)
print(h[['hum','Alpha','Beta','Gamma']].iloc[::6].round(4).to_string()); print(h.loc[h.Alpha.idxmin(),'hum'])
EOF
python3 $TMPDIR/e8.py
