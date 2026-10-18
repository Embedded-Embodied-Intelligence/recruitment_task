cd /tmp/edabench_claude_0f1dqps5; ls; head -5 *.csv; wc -l *.csv; cat suppliers.csv

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
for c in d.columns:
  print(c, d[c].nunique(), d[c].isna().sum(), d[c].value_counts().head(8).to_dict())
print(d.batch_id.value_counts().head(10))
print(d.duplicated().sum(), d.drop(columns='batch_id').duplicated().sum())
"; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c

cd /tmp/edabench_claude_0f1dqps5; grep -v mold_cleaning maintenance.csv; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates()
x=d[d.batch_id.duplicated(keep=False)].sort_values('batch_id')
print(x.head(20).to_string()); print(len(x))
print(d.production_date.str.len().value_counts())
print(d[d.production_date.str.contains('/')].production_date.unique()[:40])
m=pd.to_numeric(d.mold_temp); print(m.describe()); print(m[m>260].head(), (m>260).sum(), (m<150).sum())
h=pd.to_numeric(d.humidity_pct); print(h.describe()); print(sorted(h.dropna().unique())[:5], sorted(h.dropna().unique())[-5:])
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
d['fmt']=d.production_date.str.contains('/')
print(pd.crosstab(d.line,d.fmt))
s=d[d.fmt].production_date.str.split('/',expand=True).astype(int)
print(pd.crosstab(d[d.fmt].line,[s[0]>12, s[1]>12]))
m=pd.to_numeric(d.mold_temp)
print(pd.crosstab(d.line,pd.cut(m,[-1,1,150,300,600])))
h=pd.to_numeric(d.humidity_pct)
print(pd.crosstab(d.line,h==50.2)); print(d[h==50.2].production_date.head(30).tolist())
"

cd /tmp/edabench_claude_0f1dqps5; mkdir -p $TMPDIR; cat > clean.py <<'EOF'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv',dtype=str)
for c in d.columns: d[c]=d[c].str.strip()
def pdate(r):
    s=r.production_date
    if r.line=='L1': return pd.to_datetime(s,format='%m/%d/%Y')
    if r.line=='L4': return pd.to_datetime(s,format='%d/%m/%Y')
    return pd.to_datetime(s,format='%Y-%m-%d')
d['date']=d.apply(pdate,axis=1)
d['shift']=d['shift'].str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
d['supplier_code']=d.supplier_code.str.upper()
num=['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']
for c in num: d[c]=pd.to_numeric(d[c])
d=d.drop(columns='production_date').drop_duplicates()
d['mold_c']=np.where(d.line=='L3',(d.mold_temp-32)*5/9,d.mold_temp)
d.loc[d.mold_temp<=0,'mold_c']=np.nan
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['rate']=d.defective_units/d.units_produced
s=pd.read_csv('suppliers.csv'); d=d.merge(s,on='supplier_code',how='left')
d=d.sort_values(['line','date']).reset_index(drop=True)
EOF
python3 -c "
exec(open('clean.py').read())
print(len(d), d.shift.isna().sum(), d.supplier_name.isna().sum(), d.date.min(), d.date.max())
print(d.batch_id.duplicated().sum())
l2=d[d.line=='L2']; f=l2.humidity_pct==50.2
print(l2[f].date.min(), l2[f].date.max(), l2[(l2.date>=l2[f].date.min())&(l2.date<=l2[f].date.max())].shape, f.sum())
print(d.groupby('line').date.agg(['min','max','count']))
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('clean.py').read())
print(len(d), d['shift'].isna().sum(), d.supplier_name.isna().sum(), d.date.min(), d.date.max())
l2=d[d.line=='L2']; f=l2.humidity_pct==50.2
print(l2[f].date.min(), l2[f].date.max(), l2[(l2.date>=l2[f].date.min())&(l2.date<=l2[f].date.max())].shape, f.sum())
print(d.groupby('line').date.agg(['min','max','count']))
print(d[d.humidity_pct==50.2][['line','date']].to_string()[:0])
print(d[(d.humidity_pct==50.2)&(d.line!='L2')])
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('clean.py').read())
l2=d[(d.line=='L2')&(d.date>='2025-02-25')&(d.date<='2025-04-20')]
print(l2[['date','humidity_pct']].to_string())
" | head -200 | awk 'NR<20 || NR>120'

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('clean.py').read())
d.loc[(d.line=='L2')&(d.humidity_pct==50.2)&(d.date>='2025-03-03')&(d.date<='2025-04-13'),'hum']=np.nan
print('A2',d.hum.isna().sum(),'A3',d.defective_units.sum()/d.units_produced.sum(),'A4',d.mold_c.median())
d['month']=d.date.dt.to_period('M')
print(d.pivot_table(index='month',columns='line',values='mold_c',aggfunc='median').round(1))
d['wk']=d.date.dt.to_period('W')
print(d.groupby(['wk','line']).apply(lambda g:g.defective_units.sum()/g.units_produced.sum()).unstack().round(3).to_string())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('clean.py').read())
d['wk']=d.date.dt.to_period('W')
for v in ['mold_c','qc_inspection_min','cycle_time_s','ambient_temp_c']:
  print(v); print(d[(d.date>='2025-03-20')&(d.date<='2025-08-20')].pivot_table(index='wk',columns='line',values=v,aggfunc='mean').round(1).to_string())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('clean.py').read())
d['m']=d.date.dt.to_period('M')
p=d.pivot_table(index='m',columns='line',values='mold_c',aggfunc='mean')
print((p.sub(p[['L2','L4']].mean(axis=1),axis=0)).round(2))
print(d.groupby('supplier_name')[['mold_c','cycle_time_s','recipe_cycle_time_s']].mean())
print(d[['rate','rework_cost_eur','qc_inspection_min','defective_units','units_produced']].corr().round(2))
print((d.rework_cost_eur/d.defective_units).describe())
"

cd /tmp/edabench_claude_0f1dqps5; cat >> clean.py <<'EOF'
d.loc[(d.line=='L2')&(d.humidity_pct==50.2)&(d.date>='2025-03-03')&(d.date<='2025-04-13'),'hum']=np.nan
mt=pd.read_csv('maintenance.csv',parse_dates=['date'])
cl=mt[mt.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
d['dsc']=d.apply(dsc,axis=1)
d['cyc_dev']=d.cycle_time_s-d.recipe_cycle_time_s
EOF
python3 -c "
exec(open('clean.py').read())
print(cl.groupby('line').date.apply(lambda s:s.diff().dt.days.describe()).unstack())
print(d.dsc.describe())
print(d.groupby(pd.cut(d.dsc,[-1,3,7,10,14,18,21,28,40,80])).apply(lambda g:pd.Series({'n':len(g),'r':g.defective_units.sum()/g.units_produced.sum()})))
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('clean.py').read())
x=d[(d.line=='L3')&(d.date>='2025-07-10')&(d.date<='2025-07-30')]
print(x[['date','qc_inspection_min','rate','dsc']].to_string())
print(d.groupby(d.qc_inspection_min<17).qc_inspection_min.describe())
print(d[(d.line!='L3')&(d.qc_inspection_min<17)][['line','date','qc_inspection_min']])
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('clean.py').read())
import statsmodels.formula.api as smf
x=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
print(smf.ols('qc_inspection_min~defective_units+units_produced+rate+mold_c+cyc_dev+machine_age_years+dsc',x).fit().summary().tables[1])
print(smf.ols('rework_cost_eur~defective_units+units_produced+rate',x).fit().summary().tables[1])
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('clean.py').read())
x=d[~((d.line=='L3')&(d.date>='2025-07-21'))&~((d.line=='L1')&(d.date>='2025-04-14'))].copy()
def g(v,b):
  print(x.groupby(pd.cut(x[v],b),observed=True).apply(lambda g:pd.Series({'n':len(g),'r':g.defective_units.sum()/g.units_produced.sum()})).round(4).T.to_string())
g('mold_c',[0,195,200,205,210,215,220,225,230,240,260])
g('cyc_dev',[-20,-6,-3,-1,1,3,6,20])
g('machine_age_years',[0,3,5,7,10,15,25])
g('ambient_temp_c',[0,15,18,21,24,27,35])
for s in ['Alpha','Beta','Gamma']:
  print(s); x2=x; x=x2[x2.supplier_name==s]; g('hum',[0,20,30,40,50,60,80]); x=x2
print(x.groupby(['shift']).apply(lambda g:g.defective_units.sum()/g.units_produced.sum()))
print(x.groupby(['operator_id','line']).size().unstack())
"

cd /tmp/edabench_claude_0f1dqps5; cat > fit.py <<'EOF'
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
d['l1new']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['l3qc']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
d['h']=d.hum-35
d['m']=d.mold_c-212
d['ok']=d.defective_units; d['bad']=d.units_produced-d.defective_units
x=d.dropna(subset=['hum','mold_c']).copy()
def fit(f,data=x):
    return smf.glm(f+'',data,family=sm.families.Binomial(),var_weights=None,freq_weights=None).fit() if False else smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit()
EOF
python3 -c "
exec(open('fit.py').read())
r=fit('m+I(m**2)+C(supplier_name)*(h+I(h**2))+cyc_dev+machine_age_years+ambient_temp_c+dsc+C(shift)+C(operator_id)+l1new+l1new:m+l3qc')
print(r.summary().tables[1])
x['res']=x.rate-r.predict(x)
x['mo']=x.date.dt.to_period('M')
print(x.pivot_table(index='mo',columns='line',values='res').round(4))
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('fit.py').read())
base='m+C(supplier_name)*(h+I(h**2))+cyc_dev+ambient_temp_c+dsc+C(shift)+C(line)+machine_age_years+l1new+l3qc'
x=d.dropna(subset=['mold_c']).copy(); x['h']=x.h.fillna(0); x['hm']=x.hum.isna().astype(int)
best=[]
for t in pd.date_range('2025-04-15','2025-08-15',freq='D'):
  x['s2']=((x.line=='L2')&(x.date>=t)).astype(int)
  r=fit(base+'+hm+s2',x); best.append((r.llf,t,r.params['s2']))
best.sort(); print(best[-5:])
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('fit.py').read())
base='m+C(supplier_name)*(h+I(h**2))+cyc_dev+ambient_temp_c+dsc+C(shift)+C(line)+machine_age_years+l1new+l3qc+hm'
x=d.dropna(subset=['mold_c']).copy(); x['h']=x.h.fillna(0); x['hm']=x.hum.isna().astype(int)
x['s2']=((x.line=='L2')&(x.date>='2025-06-19')).astype(int)
r=fit(base+'+s2',x)
x['lr']=np.log(x.rate.clip(1e-3)/(1-x.rate))- (r.predict(x,which='linear') if False else np.log(r.predict(x)/(1-r.predict(x)))) + r.params['s2']*x.s2
y=x[(x.line=='L2')&(x.date>='2025-06-05')&(x.date<='2025-07-01')]
print(y.groupby('date').lr.agg(['mean','count']).round(2).to_string())
for L in ['L1','L3','L4']:
  b=[]
  for t in pd.date_range('2025-02-01','2025-09-15',freq='D'):
    x['sx']=((x.line==L)&(x.date>=t)).astype(int)
    rr=fit(base+'+s2+sx',x); b.append((round(rr.llf-r.llf,1),t.date(),round(rr.params['sx'],3)))
  b.sort(); print(L,b[-2:])
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('fit.py').read())
x=d.dropna(subset=['mold_c']).copy()
x['l3s']=((x.line=='L3')&(x.date>='2025-05-19')).astype(int)
r=smf.ols('mold_c~ambient_temp_c+C(line)+l1new+l3s+C(supplier_name)+cycle_time_s+machine_age_years',x).fit(); print(r.summary().tables[1])
y=x[x.line=='L1']; print(y[(y.date>='2025-04-08')&(y.date<='2025-04-20')][['date','mold_c','ambient_temp_c']].to_string())
y=x[x.line=='L3']; print(y[(y.date>='2025-05-12')&(y.date<='2025-05-26')][['date','mold_c','mold_temp','ambient_temp_c']].to_string())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('fit.py').read())
for start in ['2025-04-14','2025-04-15']:
  x=d.dropna(subset=['mold_c']).copy()
  x['l1new']=((x.line=='L1')&(x.date>=start)).astype(int)
  x['l3s']=((x.line=='L3')&(x.date>='2025-05-19')).astype(int)
  r=smf.ols('mold_c~ambient_temp_c+C(line)+l1new+l3s',x).fit(); k=r.params['l1new']
  mc=x.mold_c-k*x.l1new
  print(start,k,r.rsquared,mc.median(), (x.mold_c-8*x.l1new).median(),(x.mold_c-7*x.l1new).median())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('fit.py').read())
x=d.dropna(subset=['mold_c']).copy(); x['h']=x.h.fillna(0); x['hm']=x.hum.isna().astype(int)
x['s2']=((x.line=='L2')&(x.date>='2025-06-16')).astype(int)
x['m']=x.mold_c-212-7.7*x.l1new
b='m+C(supplier_name)*(h+I(h**2))+cyc_dev+ambient_temp_c+dsc+C(shift)+C(line)+machine_age_years+l3qc+hm+s2'
r=fit(b+'+l1new',x); print(r.params[['m','l1new','s2','ambient_temp_c','machine_age_years']])
r=fit(b+'+C(operator_id)+l1new',x); print(r.params[['m','l1new','s2','ambient_temp_c','machine_age_years']])
"

cd /tmp/edabench_claude_0f1dqps5; cat >> fit.py <<'EOF'
d['m']=d.mold_c-212-7.7*d.l1new
d['mc']=d.mold_c-7.7*d.l1new
d['s2']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
c=d.dropna(subset=['hum','mold_c'])
c=c[c.l3qc==0].copy()
def fitq(f,data=c):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
EOF
python3 -c "
exec(open('fit.py').read())
print(c.groupby('line').machine_age_years.describe())
r=fitq('m+I(m**2)+C(supplier_name)*(h+I(h**2))+cyc_dev+I(cyc_dev**2)+ambient_temp_c+dsc+C(shift)+machine_age_years+s2+C(operator_id)')
print(r.summary().tables[1]); print(r.scale)
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('fit.py').read())
print(pd.crosstab(c.operator_id,c['shift']).T.to_string())
base='m+C(supplier_name)*(h+I(h**2))+cyc_dev+dsc+C(shift)+s2'
for L in ['L1','L2','L3','L4']:
  y=c[c.line==L]
  r=fitq(base+'+ambient_temp_c+machine_age_years+C(operator_id)',y)
  r0=fitq(base+'+ambient_temp_c+machine_age_years',y)
  print(L, r.params[['ambient_temp_c','machine_age_years','C(shift)[T.Night]']].round(4).to_dict(), r.pvalues[['ambient_temp_c','machine_age_years']].round(3).to_dict(), 'opdev', round(r0.deviance-r.deviance,1), r.scale)
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('fit.py').read())
r=fitq('m+C(supplier_name)*(h+I(h**2))+cyc_dev+dsc+C(shift)+s2',c)
c['res']=np.log(c.rate.clip(1e-3)/(1-c.rate))-np.log(r.predict(c)/(1-r.predict(c)))
print(c.groupby(['line',pd.cut(c.machine_age_years,[0,3,5,7,9,10,12,14,16,18,25])],observed=True).res.agg(['mean','count']).round(3).to_string())
"

cd /tmp/edabench_claude_0f1dqps5; grep L2 maintenance.csv | grep 2025-0[5-7]; python3 -c "
exec(open('fit.py').read())
x=d.dropna(subset=['mold_c']).copy(); x['h']=x.h.fillna(0); x['hm']=x.hum.isna().astype(int); x=x[x.l3qc==0]
b='m+C(supplier_name)*(h+I(h**2))+cyc_dev+dsc+C(shift)+C(line)+hm'
out=[]
for t in pd.date_range('2025-06-08','2025-06-25'):
  x['s']=((x.line=='L2')&(x.date>=t)).astype(int)
  r=fitq(b+'+s',x); out.append((t.date(),round(r.deviance,1)))
print(out)
r=fitq(b,x[~((x.line=='L2')&(x.date>='2025-06-01'))])
y=x[(x.line=='L2')&(x.date>='2025-06-05')&(x.date<='2025-06-25')].copy()
p=r.predict(y); y['oe']=y.defective_units/(p*y.units_produced)
print(y[['date','dsc','defective_units','units_produced','oe']].to_string())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -c "
exec(open('fit.py').read())
x=d.dropna(subset=['mold_c']).copy(); x['h']=x.h.fillna(0); x['hm']=x.hum.isna().astype(int); x=x[x.l3qc==0]
b='m+C(supplier_name)*(h+I(h**2))+cyc_dev+dsc+C(shift)+C(line)+hm+s2'
r0=fitq(b,x); print('scale',r0.scale)
for L in ['L1','L2','L3','L4']:
  o=[]
  for t in pd.date_range('2025-02-01','2025-09-10',freq='2D'):
    x['s']=((x.line==L)&(x.date>=t)).astype(int)
    r=fitq(b+'+s',x); o.append((round((r0.deviance-r.deviance)/r0.scale,1),t.date(),round(r.params['s'],2)))
  o.sort(); print(L,o[-1])
"

cd /tmp/edabench_claude_0f1dqps5; grep L4 maintenance.csv | tr '\n' ' '; python3 -W ignore -c "
exec(open('fit.py').read())
x=d.dropna(subset=['mold_c']).copy(); x['h']=x.h.fillna(0); x['hm']=x.hum.isna().astype(int); x=x[x.l3qc==0]
b='m+C(supplier_name)*(h+I(h**2))+cyc_dev+C(shift)+C(line)+hm+s2+C(np.minimum(dsc,40)//4)'
r=fitq(b,x); print(r.params.filter(like='dsc'))
x['oe']=x.defective_units/(r.predict(x)*x.units_produced)
x['wk']=x.date.dt.to_period('W')
print(x.pivot_table(index='wk',columns='line',values='oe').round(2).to_string())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -W ignore -c "
exec(open('fit.py').read())
x=d.dropna(subset=['mold_c']).copy(); x['h']=x.h.fillna(0); x['hm']=x.hum.isna().astype(int); x=x[x.l3qc==0]
b='m+C(supplier_name)*(h+I(h**2))+cyc_dev+C(shift)+C(line)+hm+s2'
r=fitq(b,x[x.dsc<=30])
x['oe']=x.defective_units/(r.predict(x)*x.units_produced)
y=x[(x.line=='L4')&(x.date>='2025-01-25')&(x.date<='2025-04-25')]
print(y.groupby('date').agg(oe=('oe','mean'),n=('oe','size'),dsc=('dsc','first')).round(2).to_string())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -W ignore -c "
exec(open('fit.py').read())
x=d.dropna(subset=['mold_c']).copy(); x['h']=x.h.fillna(0); x['hm']=x.hum.isna().astype(int); x=x[x.l3qc==0]
b='m+C(supplier_name)*(h+I(h**2))+cyc_dev+C(shift)+C(line)+hm+s2+dsc'
r=fitq(b,x[(x.dsc<=30)]); print(r.params['dsc'])
x['oe']=x.defective_units/(r.predict(x)*x.units_produced)
x['ex']=x.defective_units/x.units_produced/r.predict(x.assign(dsc=0))
y=x[(x.line=='L4')&(x.date>='2025-01-18')&(x.date<='2025-04-25')]
print(y.groupby(y.dsc//4*4).agg(ex=('ex','mean'),n=('ex','size')).round(2).T.to_string())
y=x[(x.line!='L4')|(x.date>='2025-04-11')|(x.date<'2025-02-01')]
print(y.groupby(np.minimum(y.dsc,40)//2*2).agg(ex=('ex','mean'),n=('ex','size')).round(2).T.to_string())
"

cd /tmp/edabench_claude_0f1dqps5; cat >> fit.py <<'EOF'
d['l4gap']=((d.line=='L4')&(d.date>='2025-02-01')&(d.date<'2025-04-11')).astype(int)
c=c.merge(d[['l4gap']],left_index=True,right_index=True) if 'l4gap' not in c else c
EOF
python3 -W ignore -c "
exec(open('fit.py').read())
c['l4gap']=d.loc[c.index,'l4gap']
cc=c[c.l4gap==0]
F='m+C(supplier_name)*(h+I(h**2))+cyc_dev+C(shift)+C(line)+s2+dsc'
r=fitq(F,cc); print(r.params.round(4).to_string())
a=cc[cc.supplier_name=='Alpha']
for f in ['m+h+I(h**2)+cyc_dev+C(shift)+C(line)+s2+dsc','m+h+I(h**2)+I(h**3)+cyc_dev+C(shift)+C(line)+s2+dsc']:
  ra=fitq(f,a)
  g=np.arange(12,72.5,0.1); X=a.iloc[[0]*len(g)].copy(); X['h']=g-35
  p=ra.predict(X); print(f, g[np.argmin(p.values)].round(1))
print(a.hum.min(),a.hum.max())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -W ignore -c "
exec(open('fit.py').read())
c['l4gap']=d.loc[c.index,'l4gap']; cc=c[c.l4gap==0]
a=cc[cc.supplier_name=='Alpha'].copy()
a['hb']=pd.cut(a.hum,np.arange(10,76,4))
r=fitq('m+cyc_dev+C(shift)+C(line)+s2+dsc+C(hb)',a)
print(r.params.filter(like='hb').round(3).to_string())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -W ignore -c "
exec(open('fit.py').read())
c['l4gap']=d.loc[c.index,'l4gap']; cc=c[c.l4gap==0]
F='m+C(supplier_name)*(h+I(h**2))+cyc_dev+C(shift)+C(line)+s2+dsc'
r=fitq(F,cc)
# all batches; impute missing covariates
x=d.copy()
x['m']=x.m.fillna(x.groupby('line').m.transform('median'))
x['h']=x.h.fillna(x.groupby([x.line,x.date.dt.month]).h.transform('median'))
p0=r.predict(x)
s=pd.read_csv('suppliers.csv')
for _,row in s.iterrows():
  X=x.copy(); X['supplier_name']=row.supplier_name; X['cyc_dev']=0
  p=r.predict(X); print(row.supplier_name, (p*x.units_produced).sum()/x.units_produced.sum())
# also with original cycle times as is (deviation preserved)
for _,row in s.iterrows():
  X=x.copy(); X['supplier_name']=row.supplier_name
  p=r.predict(X); print('keepdev',row.supplier_name, (p*x.units_produced).sum()/x.units_produced.sum())
# C3
X=x.copy(); adj=(X.l4gap==0)&(X.dsc>=14)
X.loc[adj,'dsc']=X.loc[adj,'dsc']%14
p1=r.predict(X)
cf=(x.defective_units*p1/p0).sum()/x.units_produced.sum()
print('obs',x.defective_units.sum()/x.units_produced.sum(),'C3',cf, 'adj rows',adj.sum())
X2=x.copy(); adj2=X2.dsc>=14; X2.loc[adj2,'dsc']=X2.loc[adj2,'dsc']%14
print('C3 incl L4gap', (x.defective_units*r.predict(X2)/p0).sum()/x.units_produced.sum())
"

cd /tmp/edabench_claude_0f1dqps5; python3 -W ignore -c "
exec(open('fit.py').read())
c['l4gap']=d.loc[c.index,'l4gap']; cc=c[c.l4gap==0]
x=d.copy()
x['m']=x.m.fillna(x.groupby('line').m.transform('median'))
x['h']=x.h.fillna(x.groupby([x.line,x.date.dt.month]).h.transform('median'))
for F in ['m+C(supplier_name)*(h+I(h**2))+cyc_dev+C(shift)+C(line)+s2+dsc+I(dsc**2)','m+C(supplier_name)*(h+I(h**2))+cyc_dev+C(shift)+C(line)+s2+bs(dsc,df=4)']:
  r=fitq(F,cc); p0=r.predict(x)
  X=x.copy(); adj=(X.l4gap==0)&(X.dsc>=14); X.loc[adj,'dsc']=X.loc[adj,'dsc']%14
  print((x.defective_units*r.predict(X)/p0).sum()/x.units_produced.sum())
"
