cd /tmp/edabench_claude_5ysl2lkz; ls; head -5 *.csv; wc -l *.csv; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv'); print(b.dtypes); print(b.describe(include='all').T.to_string())
for c in b.columns:
  if b[c].nunique()<30: print(c, b[c].value_counts(dropna=False).to_dict())
"

cd /tmp/edabench_claude_5ysl2lkz; cat maintenance.csv | cut -d, -f3 | sort | uniq -c; python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
d=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id'); print(d.head(6).to_string())
print(b.drop_duplicates().shape, b.drop_duplicates().batch_id.nunique())
print(np.histogram(b.mold_temp,bins=[-1,1,100,150,180,200,250,300,380,400,420,440,460]))
print((b.mold_temp==0).sum())
print(b.humidity_pct.value_counts().head(5)); print((b.humidity_pct<=0).sum(), (b.humidity_pct>100).sum())
print(b.units_produced.describe()); print(b.sort_values('units_produced').tail(5).to_string())
"

cd /tmp/edabench_claude_5ysl2lkz; cat maintenance.csv | grep -v mold_cleaning; mkdir -p $TMPDIR/w; cat > $TMPDIR/w/load.py <<'EOF'
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
b['shift']=b['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
b['supplier_code']=b.supplier_code.str.strip().str.upper()
s=pd.read_csv('suppliers.csv'); b=b.merge(s,on='supplier_code',how='left')
b['date']=pd.to_datetime(b.production_date)
b['mt']=b.mold_temp.where(b.mold_temp>0)
b['F']=b.mt>300
b.loc[b.F,'mt']=(b.loc[b.F,'mt']-32)*5/9
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['rate']=b.defective_units/b.units_produced
EOF
python3 -c "
exec(open('$TMPDIR/w/load.py').read())
print(len(b), b.batch_id.nunique(), b.hum.isna().sum(), b.defective_units.sum()/b.units_produced.sum(), b.mt.median(), b.mt.notna().sum())
print(b.groupby('line').F.mean(), b.groupby(b.date.dt.month).F.mean())
print(b.mt.describe())
print(b.groupby('line').machine_age_years.describe())
print(b[['rate','qc_inspection_min','rework_cost_eur','units_produced','defective_units']].corr())
"

cd /tmp/edabench_claude_5ysl2lkz; python3 -c "
exec(open('$TMPDIR/w/load.py').read())
l1=b[b.line=='L1']; print(l1.groupby(l1.date>='2025-04-14').mt.describe())
print(b.groupby('line').mt.describe())
w=b.groupby([b.date.dt.to_period('W'),'line']).apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).unstack(); print(w.round(3).to_string())
"

cd /tmp/edabench_claude_5ysl2lkz; grep mold_cleaning maintenance.csv | sort -t, -k2,2 -k1,1 | awk -F, '{print $2,$1}' | tr '\n' ';'; echo; python3 -c "
exec(open('$TMPDIR/w/load.py').read())
l1=b[(b.line=='L1')&(b.date>='2025-04-08')&(b.date<='2025-04-20')]; print(l1.groupby('date').mt.mean())
"

cd /tmp/edabench_claude_5ysl2lkz; cat >> $TMPDIR/w/load.py <<'EOF'
m=pd.read_csv('maintenance.csv'); m['date']=pd.to_datetime(m.date)
cl=m[m.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date.max(); return (r.date-c).days
b['dsc']=b.apply(dsc,axis=1)
b['mt_act']=b.mt.copy()
b.loc[(b.line=='L1')&(b.date>=pd.Timestamp('2025-04-15')),'mt_act']-=8
EOF
python3 -c "
exec(open('$TMPDIR/w/load.py').read())
import statsmodels.formula.api as smf
print(b.mt_act.median(), b.loc[(b.line=='L1')&(b.date==pd.Timestamp('2025-04-14'))].mt.values)
bb=b.copy(); bb.loc[(bb.line=='L1')&(bb.date==pd.Timestamp('2025-04-14')),'mt_act']-=8; print(bb.mt_act.median())
print(b.groupby(pd.cut(b.dsc,[-1,3,7,10,14,18,22,30,40])).apply(lambda g:pd.Series([len(g),g.defective_units.sum()/g.units_produced.sum()])))
print(b.groupby(pd.cut(b.mt_act,10)).rate.agg(['mean','size']))
print(b.groupby(pd.cut(b.hum,10)).rate.agg(['mean','size']))
print(b.groupby('supplier_name').rate.agg(['mean','size']))
"

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/m.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
d=b.dropna(subset=['mt_act','hum']).copy()
d['ok']=d.units_produced-d.defective_units
d['d14']=(d.dsc-14).clip(lower=0)
f='defective_units + ok ~ mt_act + I(mt_act**2) + hum*C(supplier_name) + I(hum**2)*C(supplier_name) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(line) + dsc + d14'
r=smf.glm(f,d,family=sm.families.Binomial()).fit(scale='X2')
print(r.summary().tables[1])
EOF
python3 $TMPDIR/w/m.py

cd /tmp/edabench_claude_5ysl2lkz; python3 -c "
exec(open('$TMPDIR/w/load.py').read())
print(pd.crosstab(b.operator_id,b.line).to_string())
print(pd.crosstab(b.line,b.shift)); print(b[['machine_age_years','ambient_temp_c','hum','mt_act','cycle_time_s','dsc','units_produced']].corr().round(2))
"

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/m2.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
d=b.dropna(subset=['mt_act','hum']).copy()
d['ok']=d.units_produced-d.defective_units
d['d14']=(d.dsc-14).clip(lower=0)
base='mt_act + I(mt_act**2) + hum*C(supplier_name) + I(hum**2)*C(supplier_name) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + dsc + d14'
for extra in ['', '+C(line)', '+C(operator_id)']:
    r=smf.glm('defective_units + ok ~ '+base+extra,d,family=sm.families.Binomial()).fit()
    print(extra, 'pearson chi2/df', r.pearson_chi2/r.df_resid, 'aic',r.aic)
    print(r.summary2().tables[1].loc[lambda t:~t.index.str.contains('operator')][['Coef.','Std.Err.','P>|z|']].round(5).to_string())
EOF
python3 $TMPDIR/w/m2.py

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/m3.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
d=b.dropna(subset=['mt_act','hum']).copy()
d['ok']=d.units_produced-d.defective_units
d['d14']=(d.dsc-14).clip(lower=0)
base='mt_act + hum*C(supplier_name) + I(hum**2)*C(supplier_name) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + dsc'
r=smf.glm('defective_units + ok ~ '+base,d,family=sm.families.Binomial()).fit(scale='X2')
d['res']=(d.defective_units-r.fittedvalues*d.units_produced)
d['exp']=r.fittedvalues*d.units_produced
w=d.groupby([pd.Grouper(key='date',freq='W'),'line']).apply(lambda g:g.defective_units.sum()/g.exp.sum()).unstack()
print(w.round(2).to_string())
EOF
python3 $TMPDIR/w/m3.py

cd /tmp/edabench_claude_5ysl2lkz; cat >> $TMPDIR/w/m3.py <<'EOF'
l2=d[d.line=='L2'].sort_values('date')
dd=l2.groupby('date')[['defective_units','exp']].sum()
print((dd.defective_units/dd.exp).loc['2025-06-05':'2025-06-30'].round(2).to_string())
import numpy as np
best=[]
for c in dd.index[20:-20]:
    a=dd[dd.index<c]; z=dd[dd.index>=c]
    ra=a.defective_units.sum()/a.exp.sum(); rz=z.defective_units.sum()/z.exp.sum()
    ll=(a.defective_units*np.log(ra)).sum()-ra*a.exp.sum()+(z.defective_units*np.log(rz)).sum()-rz*z.exp.sum()
    best.append((ll,c))
print(sorted(best)[-5:])
EOF
python3 $TMPDIR/w/m3.py 2>/dev/null | tail -30

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/m4.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
d=b.dropna(subset=['mt_act','hum']).copy()
d['ok']=d.units_produced-d.defective_units
d['d14']=(d.dsc-14).clip(lower=0)
d['reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['l1post']=((d.line=='L1')&(d.date>='2025-04-15')).astype(int)
d['mt_raw']=d.mt
d['L4']=(d.line=='L4').astype(int)
def fit(f):
    r=smf.glm('defective_units + ok ~ '+f,d,family=sm.families.Binomial()).fit(scale='X2'); return r
base='hum*C(supplier_name) + I(hum**2)*C(supplier_name) + cycle_time_s + I(cycle_time_s**2) + machine_age_years + ambient_temp_c + C(shift) + dsc + reg'
for f in [base+'+mt_act+I(mt_act**2)', base+'+mt_raw+I(mt_raw**2)', base+'+mt_act+I(mt_act**2)+C(line)', base+'+mt_act+I(mt_act**2)+C(operator_id)',base+'+mt_act+I(mt_act**2)+l1post', base+'+mt_act+I(mt_act**2)+d14']:
    r=fit(f); print(f[-40:], 'scale',round(r.scale,3),'dev',round(r.deviance,1))
    t=r.summary2().tables[1]; print(t.loc[~t.index.str.contains('operator|supplier|hum')][['Coef.','Std.Err.','P>|z|']].round(5).to_string())
EOF
python3 $TMPDIR/w/m4.py

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/m5.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
d=b.dropna(subset=['mt_act','hum']).copy()
d['ok']=d.units_produced-d.defective_units
d['reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
def fit(f): return smf.glm('defective_units + ok ~ '+f,d,family=sm.families.Binomial()).fit()
terms={'mt':'mt_act+I(mt_act**2)','hum':'hum*C(supplier_name) + I(hum**2)*C(supplier_name)','ct':'cycle_time_s + I(cycle_time_s**2)','age':'machine_age_years','amb':'ambient_temp_c','shift':'C(shift)','dsc':'dsc','reg':'reg','line':'C(line)','op':'C(operator_id)'}
for full_keys in [['mt','hum','ct','age','amb','shift','dsc','reg','line'],['mt','hum','ct','age','amb','shift','dsc','reg','op'],['mt','hum','ct','age','amb','shift','dsc','reg']]:
    F=fit('+'.join(terms[k] for k in full_keys)); phi=F.pearson_chi2/F.df_resid
    print('FULL',full_keys,'phi',round(phi,2))
    for k in full_keys:
        R=fit('+'.join(terms[j] for j in full_keys if j!=k)) if k!='hum' else fit('+'.join(terms[j] for j in full_keys if j!=k)+'+C(supplier_name)')
        df=R.df_resid-F.df_resid; Fs=(R.deviance-F.deviance)/df/phi
        print(f'  {k}: df={df:.0f} F={Fs:.1f} p={stats.f.sf(Fs,df,F.df_resid):.3g}')
    print(F.params[[p for p in F.params.index if 'operator' not in p]].round(4).to_string())
# operator within line
F=fit('+'.join(terms[k] for k in ['mt','hum','ct','age','amb','shift','dsc','reg','op'])); R=fit('+'.join(terms[k] for k in ['mt','hum','ct','age','amb','shift','dsc','reg','line']))
phi=F.pearson_chi2/F.df_resid; df=R.df_resid-F.df_resid; Fs=(R.deviance-F.deviance)/df/phi; print('op|line',df,Fs,stats.f.sf(Fs,df,F.df_resid))
EOF
python3 $TMPDIR/w/m5.py

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/m6.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
d=b.dropna(subset=['mt_act','hum']).copy()
d['ok']=d.units_produced-d.defective_units
d['reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
f='mt_act+hum*C(supplier_name) + I(hum**2)*C(supplier_name)+cycle_time_s + I(cycle_time_s**2)+C(shift)+dsc+reg+C(operator_id)'
ps=[]
for part in [d.index%2==0, d.index%2==1]:
    r=smf.glm('defective_units + ok ~ '+f,d[part],family=sm.families.Binomial()).fit()
    p=r.params.filter(like='operator'); ps.append(p)
P=pd.concat(ps,axis=1); P['line']=[d[d.operator_id==o.split('[T.')[1][:-1]].line.iloc[0] for o in P.index]
P.columns=['a','b','line']
P['a']-=P.groupby('line').a.transform('mean'); P['b']-=P.groupby('line').b.transform('mean')
print(P.round(3)); print(P[['a','b']].corr())
for L in ['L4']:
    s=d[d.line==L]; r=smf.glm('defective_units + ok ~ mt_act+hum*C(supplier_name) + I(hum**2)*C(supplier_name)+cycle_time_s + I(cycle_time_s**2)+C(shift)+dsc+machine_age_years',s,family=sm.families.Binomial()).fit()
    print(L, r.params['machine_age_years'], r.bse['machine_age_years'])
EOF
python3 $TMPDIR/w/m6.py

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/m7.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
d=b.dropna(subset=['mt_act','hum']).copy()
d['ok']=d.units_produced-d.defective_units
d['reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['l1post']=((d.line=='L1')&(d.date>='2025-04-15')).astype(int)
for bias in [0,4,8,10,12,14]:
    d['x']=d.mt-bias*d.l1post
    r=smf.glm('defective_units + ok ~ x+hum*C(supplier_name) + I(hum**2)*C(supplier_name)+cycle_time_s + I(cycle_time_s**2)+C(shift)+dsc+reg+C(line)',d,family=sm.families.Binomial()).fit()
    r2=smf.glm('defective_units + ok ~ x+l1post+hum*C(supplier_name) + I(hum**2)*C(supplier_name)+cycle_time_s + I(cycle_time_s**2)+C(shift)+dsc+reg+C(line)',d,family=sm.families.Binomial()).fit()
    print(bias, round(r.deviance,1), r2.params['l1post'].round(3), r2.bse['l1post'].round(3))
EOF
python3 $TMPDIR/w/m7.py

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/m8.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
d=b.dropna(subset=['mt_act','hum']).copy()
d['ok']=d.units_produced-d.defective_units
d['reg']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['db']=pd.cut(d.dsc,[-1,1,3,5,7,9,11,13,15,17,19,22,25,28,40]).astype(str)
r=smf.glm('defective_units + ok ~ mt_act+hum*C(supplier_name) + I(hum**2)*C(supplier_name)+cycle_time_s + I(cycle_time_s**2)+C(shift)+C(db)+reg+C(line)',d,family=sm.families.Binomial()).fit()
print(r.params.filter(like='db').round(3))
for f in ['dsc','dsc+I(dsc**2)','np.log1p(dsc)','np.minimum(dsc,14)+np.maximum(dsc-14,0)']:
    r=smf.glm('defective_units + ok ~ mt_act+hum*C(supplier_name) + I(hum**2)*C(supplier_name)+cycle_time_s + I(cycle_time_s**2)+C(shift)+reg+C(line)+'+f,d,family=sm.families.Binomial()).fit()
    print(f, r.deviance)
for f in ['mt_act','mt_act+I(mt_act**2)']:
    r=smf.glm('defective_units + ok ~ hum*C(supplier_name) + I(hum**2)*C(supplier_name)+cycle_time_s + I(cycle_time_s**2)+C(shift)+reg+C(line)+dsc+'+f,d,family=sm.families.Binomial()).fit()
    print(f, r.deviance)
EOF
python3 $TMPDIR/w/m8.py

cd /tmp/edabench_claude_5ysl2lkz; cat > $TMPDIR/w/final.py <<'EOF'
exec(open(__import__('os').environ['TMPDIR']+'/w/load.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy.special import expit, logit
b['reg']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['ok']=b.units_produced-b.defective_units
d=b.dropna(subset=['mt_act','hum']).copy()
f='defective_units + ok ~ mt_act+hum*C(supplier_name) + I(hum**2)*C(supplier_name)+cycle_time_s + I(cycle_time_s**2)+C(shift)+dsc+reg+C(line)'
r=smf.glm(f,d,family=sm.families.Binomial()).fit()
# C1
for s in ['Alpha','Beta','Gamma']:
    x=d.assign(supplier_name=s); p=r.predict(x); print(s, (p*x.units_produced).sum()/x.units_produced.sum())
print('obs cc', d.defective_units.sum()/d.units_produced.sum(), 'pred', (r.predict(d)*d.units_produced).sum()/d.units_produced.sum())
# C2
P=r.params; a=P['hum']; q=P['I(hum ** 2)']; print('Alpha opt', -a/(2*q), 'range', b.hum.min(), b.hum.max())
for s in ['Beta','Gamma']:
    print(s,'opt', -(a+P[f'hum:C(supplier_name)[T.{s}]'])/(2*(q+P[f'I(hum ** 2):C(supplier_name)[T.{s}]'])))
A=d[d.supplier_name=='Alpha']
hs=np.arange(13,72.5,0.1); m=[]
for h in hs:
    x=A.assign(hum=h); m.append((r.predict(x)*x.units_produced).sum()/x.units_produced.sum())
print('grid opt', hs[np.argmin(m)])
from patsy import dmatrix
ra=smf.glm('defective_units + ok ~ mt_act+bs(hum,df=6)+cycle_time_s + I(cycle_time_s**2)+C(shift)+dsc+reg+C(line)',A,family=sm.families.Binomial()).fit()
m2=[(ra.predict(A.assign(hum=h))*A.units_produced).sum() for h in hs]; print('spline opt', hs[np.argmin(m2)])
# C3 apply to all batches
beta=P['dsc']; dcf=b.dsc%14
rate=b.rate.clip(1e-6,1-1e-6)
pcf=expit(logit(rate)+beta*(dcf-b.dsc))
print('C3', (pcf*b.units_produced).sum()/b.units_produced.sum(), 'obs', b.defective_units.sum()/b.units_produced.sum(), 'beta',beta)
# alt: model-based on complete cases
pc=r.predict(d.assign(dsc=d.dsc%14)); po=r.predict(d)
print('C3 model-ratio cc', (d.defective_units + (pc-po)*d.units_produced).sum()/d.units_produced.sum(), d.defective_units.sum()/d.units_produced.sum())
EOF
python3 $TMPDIR/w/final.py

cd /tmp/edabench_claude_5ysl2lkz; sed -i 's/^hs=np.arange(13,72.5,0.1)/hs=np.arange(A.hum.min(),A.hum.max(),0.1)/' $TMPDIR/w/final.py; python3 $TMPDIR/w/final.py; python3 -c "
exec(open('$TMPDIR/w/load.py').read())
print(pd.crosstab(pd.cut(b.hum,[0,20,30,40,50,80]),b.supplier_name,normalize='index').round(2))"

cd /tmp/edabench_claude_5ysl2lkz; python3 -c "
exec(open('$TMPDIR/w/load.py').read())
print(pd.crosstab(b.line,b.supplier_name,normalize='index').round(2)); print(b.groupby('supplier_name')[['dsc','mt_act','cycle_time_s','ambient_temp_c']].mean())
print(b.groupby(['line','supplier_name']).apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).unstack().round(4))"
