cd /tmp/edabench_claude_q9wmp7bm; ls; head -5 *.csv; wc -l *.csv; cat suppliers.csv

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/a.py <<'E'
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.describe().T)
for c in ['production_date','line','shift','operator_id','supplier_code']:
    print(d[c].value_counts(dropna=False).head(30))
print(d.batch_id.duplicated().sum(), d.duplicated().sum())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(d[c],errors='coerce'); print(c,x.isna().sum(),x.describe().to_dict()); print(d[c][x.isna()].unique()[:10])
print(d[d.batch_id.duplicated(keep=False)].sort_values('batch_id').head(20).to_string())
print(open('maintenance.csv').read())
E
python3 -I $TMPDIR/a.py

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/b.py <<'E'
import pandas as pd,re
d=pd.read_csv('batches.csv',dtype=str)
d['fmt']=d.production_date.map(lambda s:'iso' if re.match(r'\d{4}-',s) else 'sl')
sl=d[d.fmt=='sl'].copy()
sl['a']=sl.production_date.str[:2].astype(int);sl['b']=sl.production_date.str[3:5].astype(int)
print(sl.groupby('line').apply(lambda g:pd.Series({'n':len(g),'a>12':(g.a>12).sum(),'b>12':(g.b>12).sum()})))
print(d.groupby(['line','fmt']).size())
# mold temp by line
d['mt']=d.mold_temp.astype(float)
print(d.groupby('line').mt.describe())
print(d[d.mt==0].line.value_counts())
E
python3 -I $TMPDIR/b.py

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
d=pd.read_csv('batches.csv',dtype=str)
def pdate(r):
    s=r.production_date
    if s[4]=='-': return pd.Timestamp(s)
    a,b,y=s.split('/')
    return pd.Timestamp(int(y),int(a),int(b)) if r.line=='L1' else pd.Timestamp(int(y),int(b),int(a))
d['date']=d.apply(pdate,axis=1)
d['shift']=d['shift'].str.strip().str.lower().str[0].map({'d':'Day','n':'Night'})
d['supplier_code']=d.supplier_code.str.strip().str.upper()
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']: d[c]=pd.to_numeric(d[c])
print(d.date.min(),d.date.max(), len(d))
n0=len(d)
d=d.drop_duplicates(subset=[c for c in d.columns if c!='production_date'])
print(n0,len(d),d.duplicated(['line','batch_id']).sum(), d.batch_id.nunique(), d.drop_duplicates(['batch_id','line']).shape)
x=d[d.duplicated(['line','batch_id'],keep=False)].sort_values('batch_id');print(x.head(10).to_string())
d['hum_bad']=d.humidity_pct.isna()|(d.humidity_pct<0)
print('hum bad',d.hum_bad.sum(), (d.humidity_pct>100).sum())
d['mt']=d.mold_temp.where(d.mold_temp>0)
d['mtc']=np.where(d.line=='L3',(d.mt-32)*5/9,d.mt)
print('A3',d.defective_units.sum()/d.units_produced.sum(),'A4',d.mtc.median())
print(d.groupby('line').mtc.describe())
d['dr']=d.defective_units/d.units_produced
d['month']=d.date.dt.to_period('M')
print(d.pivot_table(index='month',columns='line',values='mtc',aggfunc='median'))
print(d.pivot_table(index='month',columns='line',values='dr',aggfunc='mean'))
print((d.defective_units>d.units_produced).sum(), d.dr.describe())
d.to_pickle(__import__('os').environ['TMPDIR']+'/d.pkl')
E
python3 -I $TMPDIR/c.py

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/e.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']);m=m[m.event=='mold_cleaning']
def dsc(r):
    p=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-p.max()).days if len(p) else np.nan
d['dsc']=d.apply(dsc,axis=1)
d['sup']=d.supplier_code
d['hum']=d.humidity_pct.where(~d.hum_bad)
d['cyc_dev']=d.cycle_time_s-d.supplier_code.map({'SP-01':30,'SP-02':30,'SP-03':36})
d['ok']=d.units_produced-d.defective_units
print(d.groupby('line').machine_age_years.describe())
print(d[['mtc','hum','cycle_time_s','machine_age_years','ambient_temp_c','dsc','qc_inspection_min','rework_cost_eur','dr']].corr().round(2))
print(d.groupby('sup').agg(dr=('dr','mean'),hum=('hum','mean'),cyc=('cycle_time_s','mean')))
d.to_pickle(os.environ['TMPDIR']+'/d2.pkl')
f='ok+defective_units~'
dd=d.dropna(subset=['mtc','hum','dsc'])
f='I(defective_units/units_produced)~'
mod=smf.glm('dr~mtc+I(mtc**2)+hum+I(hum**2)+cyc_dev+I(cyc_dev**2)+machine_age_years+ambient_temp_c+dsc+C(sup)+C(shift)+C(operator_id)+C(line)',dd,family=sm.families.Binomial(),freq_weights=dd.units_produced).fit()
print(mod.summary().tables[1])
E
python3 -I $TMPDIR/e.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
print(pd.crosstab(d.operator_id,d.line).T.to_string())
print(pd.crosstab(d['shift'],d.line))
dd=d.dropna(subset=['mtc','hum','dsc']).copy()
dd['opgrp']=dd.operator_id
def fit(f,data=dd):
    m=smf.glm(f,data,family=sm.families.Binomial(),freq_weights=data.units_produced).fit(scale='X2')
    return m
base='dr~mtc+I(mtc**2)+hum+I(hum**2)+cyc_dev+machine_age_years+ambient_temp_c+dsc+C(sup)+C(shift)+'
for extra in ['C(line)','C(line)+C(operator_id)','1']:
    m=fit(base+extra); t=m.summary2().tables[1]; print(extra);print(t[~t.index.str.contains('operator')].round(4).iloc[:,[0,1,3]].to_string())
E
python3 -I $TMPDIR/f.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
dd=d.dropna(subset=['mtc','hum','dsc']).copy()
dd['mt_c']=dd.mtc-210; dd['h']=dd.hum-30
def fit(f):
    m=smf.glm('ok+defective_units~'.replace('ok+defective_units','I(defective_units)+I(ok)')+f,dd,family=sm.families.Binomial()).fit(scale='X2')
    return m
def show(f):
    m=fit(f);t=m.summary2().tables[1];print(f,m.scale);print(t[~t.index.str.contains('operator')].round(4).iloc[:,[0,1,3]].to_string())
    return m
dd['y']=1
show('mt_c+I(mt_c**2)+h*C(sup)+I(h**2)*C(sup)+cyc_dev+I(cyc_dev**2)+machine_age_years+ambient_temp_c+dsc+C(sup)+C(shift)+C(line)')
# without ambient and with only mt
show('mt_c+h*C(sup)+I(h**2)*C(sup)+cyc_dev+machine_age_years+dsc+C(sup)+C(shift)+C(line)')
E
python3 -I $TMPDIR/g.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
dd=d.dropna(subset=['mtc','hum','dsc']).copy()
dd['mt_c']=dd.mtc-210; dd['h']=dd.hum-30
def show(f,data=dd):
    m=smf.glm('dr~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
    t=m.summary2().tables[1];print(f,m.scale);print(t[~t.index.str.contains('operator')].round(4).iloc[:,[0,1,3]].to_string());return m
show('mt_c+I(mt_c**2)+h*C(sup)+I(h**2)*C(sup)+cyc_dev+machine_age_years+ambient_temp_c+dsc+C(sup)+C(shift)+C(line)')
dd['hb']=pd.cut(dd.hum,range(0,80,8))
print(dd.pivot_table(index='hb',columns='sup',values='dr',aggfunc='mean').round(4))
print(dd.groupby(pd.cut(dd.mtc,[180,200,205,210,215,220,225,230,245])).dr.mean())
print(dd.groupby(pd.cut(dd.dsc,[-1,3,6,9,12,14,16,20,30,60])).dr.agg(['mean','size']))
print(dd.groupby(pd.cut(dd.cyc_dev,[-15,-8,-4,-2,0,2,4,8,15])).dr.mean())
E
python3 -I $TMPDIR/g.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
d['w']=d.date.dt.to_period('2W')
for l in ['L1','L2','L3','L4']:
    x=d[d.line==l].dropna(subset=['mtc'])
    r=smf.ols('mtc~ambient_temp_c',x).fit(); x=x.assign(res=r.resid)
    print(l,r.params.values.round(2)); print(x.groupby(x.date.dt.to_period('M')).res.mean().round(1).to_dict())
x=d[(d.line=='L1')&(d.date.between('2025-03-25','2025-05-05'))].dropna(subset=['mtc']).sort_values('date')
print(x[['date','ambient_temp_c','mtc']].groupby('date').mean().round(1).T.to_string())
E
python3 -I $TMPDIR/h.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/h2.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
for l in ['L1','L2','L3','L4']:
  for nm,x in [('pre',d[(d.line==l)&(d.date<'2025-04-14')]),('post',d[(d.line==l)&(d.date>='2025-04-14')])]:
    x=x.dropna(subset=['mtc']); r=smf.ols('mtc~ambient_temp_c',x).fit(); print(l,nm,r.params.values.round(2),round(r.resid.std(),2),len(x))
# defect rate vs mtc by line pre/post
dd=d.dropna(subset=['mtc']).copy();dd['post']=dd.date>='2025-04-14'
print(dd.groupby(['line','post'])[['mtc','ambient_temp_c']].mean())
E
python3 -I $TMPDIR/h2.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/i.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
dd=d.dropna(subset=['mtc','hum','dsc']).copy()
dd['mt_c']=dd.mtc-210; dd['h']=dd.hum-30
f='dr~mt_c+I(mt_c**2)+h*C(sup)+I(h**2)*C(sup)+cyc_dev+ambient_temp_c+dsc+C(sup)+C(shift)+C(line)'
m=smf.glm(f,dd,family=sm.families.Binomial(),var_weights=dd.units_produced).fit(scale='X2')
dd['ratio']=dd.dr/m.predict(dd)
dd['mon']=dd.date.dt.to_period('2W')
print(dd.pivot_table(index='mon',columns='line',values='ratio',aggfunc='mean').round(2).to_string())
# changepoint search per line on log ratio
for l in ['L1','L2','L3','L4']:
    x=dd[dd.line==l].sort_values('date'); y=np.log(x.ratio.values); best=None
    for i in range(30,len(x)-30):
        s=((y[:i]-y[:i].mean())**2).sum()+((y[i:]-y[i:].mean())**2).sum()
        if best is None or s<best[0]: best=(s,i)
    i=best[1];print(l,x.date.iloc[i],np.exp(y[:i].mean()),np.exp(y[i:].mean()),((y-y.mean())**2).sum()-best[0])
E
python3 -I $TMPDIR/i.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/j.py <<'E'
import pandas as pd,numpy as np,os
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
for l,c in [('L2','2025-06-16'),('L3','2025-07-21')]:
    x=d[d.line==l].copy(); x['p']=pd.to_datetime(x.date)>=c
    print(l,x.groupby('p')[['qc_inspection_min','rework_cost_eur','dr','units_produced','mold_temp','cycle_time_s','humidity_pct']].mean())
    x['rc']=x.rework_cost_eur/x.defective_units; x['qcu']=x.qc_inspection_min
    print(x.groupby('p')[['rc']].mean())
    print(x[(x.date>=pd.Timestamp(c)-pd.Timedelta(days=14))&(x.date<=pd.Timestamp(c)+pd.Timedelta(days=14))].groupby(x.date.dt.date).dr.mean().round(3).to_dict())
E
python3 -I $TMPDIR/j.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/k.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
dd=d.dropna(subset=['mtc','hum','dsc']).copy()
dd['mt_c']=dd.mtc-210; dd['h']=dd.hum-30
f='dr~mt_c+I(mt_c**2)+h*C(sup)+I(h**2)*C(sup)+cyc_dev+ambient_temp_c+dsc+C(sup)+C(shift)+C(line)'
x=dd[dd.line=='L2']
res=[]
for c in pd.date_range('2025-06-01','2025-07-05'):
    x2=x.assign(p=(x.date>=c).astype(int))
    m=smf.glm(f.replace('+C(line)','')+'+p',x2,family=sm.families.Binomial(),var_weights=x2.units_produced).fit()
    res.append((c.date(),round(m.llf,1) if False else round(m.deviance,1),round(m.params['p'],3)))
for r in res: print(r)
print(x[(x.date>='2025-06-10')&(x.date<='2025-06-20')].groupby('date').size())
E
python3 -I $TMPDIR/k.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/l.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
d['r2']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['r3']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
dd=d.dropna(subset=['mtc','hum','dsc']).copy()
dd['mt_c']=dd.mtc-210; dd['h']=dd.hum-30
dd.to_pickle(os.environ['TMPDIR']+'/dd.pkl')
def fit(f,data=dd): return smf.glm('dr~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
core='mt_c+I(mt_c**2)+h*C(sup)+I(h**2)*C(sup)+cyc_dev+dsc+C(sup)+C(line)+r2+r3'
full=fit(core+'+ambient_temp_c+machine_age_years+C(shift)+C(operator_id)')
print(full.summary2().tables[1].round(4).iloc[:,[0,1,3]].to_string())
for drop,name in [('ambient_temp_c','amb'),('machine_age_years','age'),('C(shift)','shift'),('C(operator_id)','op')]:
    ext='+ambient_temp_c+machine_age_years+C(shift)+C(operator_id)'.replace('+'+drop,'')
    m=fit(core+ext); 
    k=full.df_model-m.df_model; F=((m.deviance-full.deviance)/k)/full.scale
    from scipy import stats; print(name,k,F,stats.f.sf(F,k,full.df_resid))
E
python3 -I $TMPDIR/l.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/m.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy import stats
dd=pd.read_pickle(os.environ['TMPDIR']+'/dd.pkl')
print(pd.crosstab(dd.operator_id,dd['shift']).T.to_string())
core='mt_c+I(mt_c**2)+h*C(sup)+I(h**2)*C(sup)+cyc_dev+dsc+C(sup)+r2+r3+C(shift)'
for l in ['L1','L2','L3','L4']:
    x=dd[dd.line==l]
    a=smf.glm('dr~'+core+'+C(operator_id)'+('+machine_age_years' if l=='L4' else ''),x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
    b=smf.glm('dr~'+core+('+machine_age_years' if l=='L4' else ''),x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
    k=a.df_model-b.df_model;F=(b.deviance-a.deviance)/k/a.scale;print(l,k,F,stats.f.sf(F,k,a.df_resid), a.params.filter(like='machine').round(3).to_dict() )
    print(a.params.filter(like='operator').round(3).to_dict())
E
python3 -I $TMPDIR/m.py 2>&1|grep -v Warn

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/n.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=pd.read_pickle(os.environ['TMPDIR']+'/dd.pkl')
def fit(f,x): return smf.glm('dr~'+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
base='mt_c+cyc_dev+dsc+C(line)+r2+r3+C(shift)'
a=dd[dd.sup=='SP-01']
for f in ['+h+I(h**2)','+h+I(h**2)+I(h**3)','+h+I(h**2)+I(h**3)+I(h**4)']:
    m=fit(base+f,a); print(f,m.deviance,m.scale)
    g=np.arange(8,72,.1); p=m.predict(a.iloc[[0]*len(g)].assign(h=g-30)); print(g[np.argmin(p.values)])
m=fit(base+'+h+I(h**2)',a); print(m.params.filter(like='h').to_dict(), 30-m.params['h']/(2*m.params['I(h ** 2)']))
print(a.hum.describe())
# absolute vs relative cycle time
for cyc in ['cyc_dev','cycle_time_s']:
    mm=fit(f'mt_c+{cyc}+dsc+C(line)+r2+r3+C(shift)+C(sup)*(h+I(h**2))',dd); print(cyc,mm.deviance, mm.params.filter(like='sup').round(3).to_dict())
mm=fit('mt_c+cycle_time_s+cyc_dev+dsc+C(line)+r2+r3+C(shift)+C(sup)*(h+I(h**2))',dd);print(mm.params[['cycle_time_s','cyc_dev']],mm.bse[['cycle_time_s','cyc_dev']])
E
python3 -I $TMPDIR/n.py 2>&1|grep -v -i Warn|grep -v wls

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/o.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=pd.read_pickle(os.environ['TMPDIR']+'/dd.pkl')
def fit(f,x=dd): return smf.glm('dr~'+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
for f in ['mt_c+cyc_dev+dsc+C(line)+r2+r3+C(shift)+C(sup)*(h+I(h**2))',
          'mt_c+I(mt_c**2)+cyc_dev+I(cyc_dev**2)+dsc+C(line)+r2+r3+C(shift)+C(sup)*(h+I(h**2))',
          'C(sup)*(mt_c+cyc_dev+h+I(h**2))+dsc+C(line)+r2+r3+C(shift)']:
    m=fit(f); print(m.deviance, m.scale)
    for s in ['SP-01','SP-02','SP-03']:
        x=dd.assign(sup=s,cyc_dev=0.0); p=m.predict(x)
        print(s, (p*x.units_produced).sum()/x.units_produced.sum())
E
python3 -I $TMPDIR/o.py 2>&1|grep -v -i Warn|grep -v wls

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/p.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=pd.read_pickle(os.environ['TMPDIR']+'/dd.pkl')
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
d['r2']=((d.line=='L2')&(d.date>='2025-06-16')).astype(int)
d['r3']=((d.line=='L3')&(d.date>='2025-07-21')).astype(int)
def fit(f,x=dd): return smf.glm('dr~'+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
b='mt_c+cyc_dev+C(line)+r2+r3+C(shift)+C(sup)*(h+I(h**2))'
dd['ex']=np.maximum(dd.dsc-14,0)
for f in ['+dsc','+dsc+ex','+dsc+I(dsc**2)','+ex']:
    m=fit(b+f);print(f,m.deviance,m.params.filter(regex='dsc|ex').round(4).to_dict())
print(dd.dsc.describe(), (d.dsc>14).sum(), (d.dsc>=14).sum(), d.dsc.max())
m=fit(b+'+dsc'); beta=m.params['dsc']; print(beta,m.bse['dsc'])
# all rows: odds shift
dsc2=d.dsc%14; 
for nm,dsc_new in [('mod14',d.dsc%14),('cap',np.minimum(d.dsc,13))]:
    rate=d.defective_units/d.units_produced; lo=np.log(rate/(1-rate))+beta*(dsc_new-d.dsc); p=1/(1+np.exp(-lo))
    print(nm,(p*d.units_produced).sum()/d.units_produced.sum())
    # model based on valid rows ratio
    x=dd.assign(dsc=dsc_new[dd.index]); r=(m.predict(x)*x.units_produced).sum()/(m.predict(dd)*dd.units_produced).sum(); print(' ratio',r*d.defective_units.sum()/d.units_produced.sum())
    # sum def scaled by per-row model ratio
    ratio=pd.Series(1.0,index=d.index); ratio[dd.index]=m.predict(x)/m.predict(dd)
    print(' rowratio',(d.defective_units*ratio).sum()/d.units_produced.sum())
E
python3 -I $TMPDIR/p.py 2>&1|grep -v -i Warn|grep -v wls

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/q.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=pd.read_pickle(os.environ['TMPDIR']+'/dd.pkl')
def fit(f,x=dd): return smf.glm('dr~'+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
b='mt_c+cyc_dev+C(line)+r2+r3+C(shift)+C(sup)*(h+I(h**2))'
dd['db']=pd.cut(dd.dsc,[-1,0,1,2,3,4,5,6,8,10,12,14,17,20,25,30,40,70])
m=fit(b+'+C(db)');t=m.params.filter(like='db');print(t.round(3).to_string())
print(dd.db.value_counts().sort_index().to_dict())
for nm,f in [('log','+np.log1p(dsc)'),('sqrt','+np.sqrt(dsc)'),('exp7','+I(1-np.exp(-dsc/7))'),('exp14','+I(1-np.exp(-dsc/14))'),('exp4','+I(1-np.exp(-dsc/4))'),('exp20','+I(1-np.exp(-dsc/20))'),('lin','+dsc'),('cat','+C(db)')]:
    mm=fit(b+f);print(nm,round(mm.deviance,1))
E
python3 -I $TMPDIR/q.py 2>&1|grep -v -i Warn|grep -v wls

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/r.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=pd.read_pickle(os.environ['TMPDIR']+'/dd.pkl')
x=dd[dd.dsc>35];print(x.groupby('line').date.agg(['min','max','size']), x.groupby('line').dsc.max())
print(dd[dd.dsc>20].groupby(['line',dd.date.dt.to_period('M')]).size().unstack(0))
E
python3 -I $TMPDIR/r.py 2>&1|grep -v -i Warn|grep -v wls

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/s.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=pd.read_pickle(os.environ['TMPDIR']+'/dd.pkl')
def fit(f,x): return smf.glm('dr~'+f,x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
b='mt_c+cyc_dev+C(line)+r2+r3+C(shift)+C(sup)*(h+I(h**2))'
for nm,x in [('all',dd),('noL4gap',dd[~((dd.line=='L4')&(dd.dsc>35))])]:
    print(nm)
    for cap in [14,18,21,25,28,30,35,100]:
        x=x.assign(c=np.minimum(x.dsc,cap)); print(' cap',cap,round(fit(b+'+c',x).deviance,1))
    for tau in [6,8,10,12,15,20]:
        x=x.assign(c=1-np.exp(-x.dsc/tau)); print(' tau',tau,round(fit(b+'+c',x).deviance,1))
    x=x.assign(db=pd.cut(x.dsc,[-1,0,1,2,3,4,5,6,8,10,12,14,17,20,25,30,40,70]))
    print(fit(b+'+C(db)',x).params.filter(like='db').round(2).values, fit(b+'+C(db)',x).deviance)
E
python3 -I $TMPDIR/s.py 2>&1|grep -v -i Warn|grep -v wls

cd /tmp/edabench_claude_q9wmp7bm; cat > $TMPDIR/t.py <<'E'
import pandas as pd,numpy as np,os
import statsmodels.api as sm, statsmodels.formula.api as smf
dd=pd.read_pickle(os.environ['TMPDIR']+'/dd.pkl')
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
gap=lambda x:(x.line=='L4')&(x.date>='2025-02-15')&(x.date<='2025-04-10')
print(d.dsc.isna().sum(), gap(d).sum(), d[gap(d)].dsc.min())
x=dd[~gap(dd)]
b='mt_c+cyc_dev+C(line)+r2+r3+C(shift)+C(sup)*(h+I(h**2))'
m=smf.glm('dr~'+b+'+dsc',x,family=sm.families.Binomial(),var_weights=x.units_produced).fit(scale='X2')
beta=m.params['dsc'];print(beta,m.bse['dsc'])
for bt in [beta,beta-2*m.bse['dsc'],beta+2*m.bse['dsc']]:
    new=np.where(gap(d)|(d.dsc<14),d.dsc,d.dsc%14)
    rate=d.defective_units/d.units_produced; lo=np.log(rate/(1-rate))+bt*(new-d.dsc); p=1/(1+np.exp(-lo))
    print(bt,(p*d.units_produced).sum()/d.units_produced.sum())
    # model-based ratio on valid rows
    xx=dd.assign(dsc=np.where(gap(dd)|(dd.dsc<14),dd.dsc,dd.dsc%14))
    r=m.predict(xx)/m.predict(dd); print('  rowratio',(dd.defective_units*r).sum()+d.defective_units.sum()-dd.defective_units.sum(), ((dd.defective_units*r).sum()+d.defective_units.sum()-dd.defective_units.sum())/d.units_produced.sum())
E
python3 -I $TMPDIR/t.py 2>&1|grep -v -i Warn|grep -v wls
