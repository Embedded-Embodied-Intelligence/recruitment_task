cd /tmp/edabench_claude_7b_fdgs7; ls; for f in *.csv; do echo == $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_7b_fdgs7; cat suppliers.csv; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(d.describe().T)
for c in ['shift','operator_id','supplier_code','line']: print(d[c].value_counts(dropna=False))
print(d.production_date.str.len().value_counts())
print(d[d.batch_id.duplicated(keep=False)].sort_values('batch_id').head(20).to_string())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    x=pd.to_numeric(d[c],errors='coerce'); print(c,x.isna().sum(),x.min(),x.max(),d[c][x.isna()].unique()[:5])
"

cd /tmp/edabench_claude_7b_fdgs7; grep sensor maintenance.csv; python3 -c "
import pandas as pd
d=pd.read_csv('batches.csv',dtype=str)
print(len(d), len(d.drop_duplicates()))
d=d.drop_duplicates()
m=pd.to_numeric(d.mold_temp)
print(d.assign(m=m).groupby('line').m.describe())
print(d[m==0].line.value_counts()); print(d[m==0].production_date.sort_values().tolist()[:60])
print(d.production_date.str.extract(r'^(\d\d)/(\d\d)/')[[0,1]].astype(float).max())
d['fmt']=d.production_date.map(lambda s:'iso' if s[4]=='-' else 'slash')
print(d.groupby(['line','fmt']).size())
print(d[d.humidity_pct.isin(['-1.0'])].shape, d.humidity_pct.isna().sum(), (pd.to_numeric(d.humidity_pct)<0).sum())
print(d[d.production_date.str.startswith('2025-')].production_date.min())
"

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/p.py <<'E'
import pandas as pd, numpy as np
d=pd.read_csv('batches.csv',dtype=str).drop_duplicates()
print(len(d), d.batch_id.nunique(), len(d.drop_duplicates(['line','batch_id'])))
def pdte(r):
    s=r.production_date
    if s[4]=='-': return pd.Timestamp(s)
    return pd.to_datetime(s,format='%m/%d/%Y' if r.line=='L1' else '%d/%m/%Y')
d['date']=d.apply(pdte,axis=1)
print(d.date.min(),d.date.max())
d['shift']=d['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
d['sup']=d.supplier_code.str.strip().str.upper()
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']: d[c]=pd.to_numeric(d[c])
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.line=='L3','mt']=(d.mt-32)*5/9
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
print('A1',len(d),'A2',d.hum.isna().sum(),'A3',d.defective_units.sum()/d.units_produced.sum(),'A4',d.mt.median())
d['rate']=d.defective_units/d.units_produced
d.to_pickle('/tmp/edabench_claude_7b_fdgs7/../d.pkl') if False else d.to_pickle(__import__('os').environ['TMPDIR']+'/d.pkl')
print(d.groupby('line').mt.describe())
d['wk']=d.date.dt.to_period('M')
print(d.pivot_table(index='wk',columns='line',values='mt'))
print(d.pivot_table(index='wk',columns='line',values='rate'))
print(d.groupby('line').date.agg(['min','max']))
E
python3 $TMPDIR/p.py

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/q.py <<'E'
import pandas as pd, numpy as np, os
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
import statsmodels.formula.api as smf
l=d[d.line=='L1'].dropna(subset=['mt'])
l['w']=l.date.dt.to_period('W')
print(l.groupby('w')[['mt','ambient_temp_c']].mean().loc['2025-03-17':'2025-05-12'])
for ln in ['L1','L2','L3','L4']:
    x=d[(d.line==ln)].dropna(subset=['mt'])
    x['pre']=(x.date<'2025-04-14')
    r=smf.ols('mt~ambient_temp_c+pre',x).fit(); print(ln,r.params.round(2).to_dict())
E
python3 $TMPDIR/q.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/r.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
# L1 offset estimate
x=d[d.line=='L1'].dropna(subset=['mt']); x['pre']=(x.date<'2025-04-14')
x=x[(x.date>='2025-03-24')&(x.date<'2025-05-05')]
print(smf.ols('mt~ambient_temp_c+pre',x).fit().params)
d['off']=np.where((d.line=='L1')&(d.date<'2025-04-14'),7.0,0)
d['mtc']=d.mt+d.off
d['recipe']=d.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
d['dct']=d.cycle_time_s-d.recipe
d['fail']=d.units_produced-d.defective_units
d['dow']=d.date
print(d[['rate','mtc','hum','cycle_time_s','dct','machine_age_years','ambient_temp_c','qc_inspection_min','rework_cost_eur']].corr()['rate'])
f='rate~mtc+hum+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(sup)+C(line)'
dd=d.dropna(subset=['mtc','hum'])
r=smf.glm('defective_units+fail~mtc+I(mtc**2)+hum+I(hum**2)+cycle_time_s+I(cycle_time_s**2)+machine_age_years+ambient_temp_c+C(shift)+C(sup)+C(line)',dd,family=sm.families.Binomial()).fit()
print(r.summary().tables[1])
E
python3 $TMPDIR/r.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/s.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date']); m=m[m.event=='mold_cleaning']
d['off']=np.where((d.line=='L1')&(d.date<'2025-04-14'),7.3,0)
d['mtc']=d.mt+d.off
d['recipe']=d.sup.map({'SP-01':30,'SP-02':30,'SP-03':36})
d['dct']=d.cycle_time_s-d.recipe
d['fail']=d.units_produced-d.defective_units
def ds(r):
    c=m[(m.line==r.line)&(m.date<=r.date)].date
    return (r.date-c.max()).days
d['dsc']=d.apply(ds,axis=1)
print(m.groupby('line').date.apply(lambda s:s.sort_values().diff().dt.days.describe()))
print(d.dsc.describe())
d.to_pickle(os.environ['TMPDIR']+'/d2.pkl')
print(d.groupby(pd.cut(d.dsc,[-1,0,2,5,8,11,14,18,25,40,100])).agg(r=('rate','mean'),n=('rate','size')))
print(d.groupby(['sup',pd.cut(d.hum,[0,10,20,30,40,50,60,80])]).rate.mean().unstack(0))
print(d.groupby(['sup',pd.cut(d.dct,[-20,-6,-3,-1,1,3,6,20])]).rate.mean().unstack(0))
print(d.groupby('shift').rate.mean(), d.groupby(['line','shift']).rate.mean())
print(d.groupby('line').machine_age_years.describe())
E
python3 $TMPDIR/s.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/t.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
d['over']=np.maximum(d.dsc-14,0)
d['h2']=(d.hum-40)**2
dd=d.dropna(subset=['mtc','hum']).copy()
G=sm.families.Binomial()
def fit(f,data=dd):
    return smf.glm('defective_units+fail~'+f,data,family=G).fit()
base='mtc+hum+h2+C(sup)+C(line)+machine_age_years+ambient_temp_c+C(shift)+C(operator_id)+dsc+cycle_time_s+dct'
r=fit(base); print(r.summary().tables[1].as_text()[:6000]); print(r.deviance, r.df_resid)
E
python3 $TMPDIR/t.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/t.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
d['h2']=(d.hum-40)**2
d['L4']=(d.line=='L4')*1
dd=d.dropna(subset=['mtc','hum']).copy()
print(pd.crosstab(dd.operator_id,dd.line).T.to_string())
def fit(f,data=dd):
    return smf.glm('defective_units+fail~'+f,data,family=sm.families.Binomial()).fit(scale='X2')
def show(r): print(r.summary().tables[1].as_text()); print(r.scale)
show(fit('mtc+hum+h2+C(sup)+machine_age_years+ambient_temp_c+C(shift)+dsc+cycle_time_s+dct'))
print(dd.groupby('shift')[['ambient_temp_c','hum','mtc','dsc']].mean())
E
python3 $TMPDIR/t.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/t.py <<'E'
import pandas as pd, numpy as np, os
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
d['h2']=(d.hum-40)**2
dd=d.dropna(subset=['mtc','hum']).copy()
def fit(f,data=dd):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),freq_weights=data.units_produced).fit(scale='X2')
def show(r): print(r.summary().tables[1].as_text()); print(r.scale, r.deviance)
base='mtc+hum+h2+C(sup)+ambient_temp_c+C(shift)+dsc+cycle_time_s+dct'
r=fit(base+'+machine_age_years+C(line)'); show(r)
r0=fit(base+'+C(line)'); r1=fit(base+'+machine_age_years'); r2=fit(base+'+C(line)+machine_age_years+C(operator_id)')
print('dev line only',r0.deviance,'age+line',r.deviance,'age only',r1.deviance,'ops',r2.deviance, r.df_resid)
E
python3 $TMPDIR/t.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/t.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
dd=d.dropna(subset=['mtc','hum']).copy()
dd['hc']=dd.hum-40
def fit(f,data=dd):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit()
def show(r): print(r.params.round(4).to_string()); print('dev',r.deviance, r.df_resid, r.pearson_chi2/r.df_resid)
base='mtc+hc+I(hc**2)+C(sup)+ambient_temp_c+C(shift)+dsc+cycle_time_s+dct'
show(fit('mtc+hc+I(hc**2)+C(sup)+ambient_temp_c+C(shift)+dsc+dct+C(line)+machine_age_years'))
show(fit('mtc+hc+I(hc**2)+C(sup)+ambient_temp_c+C(shift)+dsc+cycle_time_s+C(line)+machine_age_years'))
E
python3 $TMPDIR/t.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/t.py <<'E'
print('-----')
dd['dscb']=pd.cut(dd.dsc,[-1,2,5,8,11,14,17,20,25,100])
dd['mtb']=pd.cut(dd.mtc,[0,195,200,205,210,215,220,225,230,260])
dd['hb']=pd.cut(dd.hum,[0,10,20,30,40,50,60,80])
dd['ctb']=pd.cut(dd.cycle_time_s-dd.recipe,[-20,-8,-4,-2,0,2,4,8,20])
dd['ageb']=pd.cut(dd.machine_age_years,[0,3,5,7,10,14,17,22])
f0='C(sup)+C(line)+C(shift)+ambient_temp_c'
for c in ['dscb','mtb','hb','ctb','ageb']:
    r=fit(f0+f'+C({c})'); print(c, round(r.deviance,0)); print(r.params.filter(like=c).round(3).to_string())
E
python3 $TMPDIR/t.py 2>&1 | sed -n '/-----/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/u.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
dd=d.dropna(subset=['mtc','hum']).copy()
dd['hc']=dd.hum-40
dd['ov']=np.maximum(dd.dsc-14,0)
dd['rs']=(dd.recipe==36)*1
def fit(f,data=dd):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit()
def show(r): print(r.params.round(4).to_string()); print('dev',round(r.deviance), r.df_resid, round(r.pearson_chi2/r.df_resid,2))
for ln in ['L1','L2','L3','L4']:
    x=dd[dd.line==ln]
    r=fit('mtc+hc*C(sup)+I(hc**2)*C(sup)+ambient_temp_c+C(shift)+dsc+cycle_time_s+machine_age_years+C(sup)',x); print(ln); print(r.params.round(3).to_dict()); print(round(r.deviance),r.df_resid)
E
python3 $TMPDIR/u.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/u.py <<'E'
print('=======')
print(dd.groupby('sup')[['cycle_time_s','hum','mtc']].describe().T.to_string())
f='mtc+(hc+I(hc**2))*C(sup)+C(shift)+dsc+cycle_time_s+C(line)'
r=fit(f); show(r)
dd['p']=r.predict(dd); dd['res']=(dd.defective_units-dd.p*dd.units_produced)
dd['m']=dd.date.dt.to_period('M')
dd['sres']=dd.res
t=dd.groupby(['line','m']).agg(o=('defective_units','sum'),e=('p',lambda s:(s*dd.loc[s.index,'units_produced']).sum()))
t['r']=t.o/t.e; print(t.r.unstack(0).round(2))
E
python3 $TMPDIR/u.py 2>&1 | sed -n '/=====/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/u.py <<'E'
print('#########')
dd['w']=dd.date.dt.to_period('W').dt.start_time
for ln,a,b in [('L2','2025-05-01','2025-07-15'),('L3','2025-06-01','2025-09-10')]:
    x=dd[(dd.line==ln)&(dd.date>=a)&(dd.date<=b)]
    t=x.groupby('w').apply(lambda g:pd.Series(dict(n=len(g),o=g.defective_units.sum(),e=(g.p*g.units_produced).sum(),qc=g.qc_inspection_min.mean())))
    t['r']=t.o/t.e; print(ln); print(t.round(2))
E
python3 $TMPDIR/u.py 2>&1 | sed -n '/####/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/u.py <<'E'
print('@@@@@@')
for ln,a,b in [('L2','2025-06-09','2025-06-24'),('L3','2025-07-10','2025-07-25')]:
    x=dd[(dd.line==ln)&(dd.date>=a)&(dd.date<=b)].sort_values('date')
    print(x[['batch_id','date','shift','operator_id','sup','mtc','hum','cycle_time_s','units_produced','defective_units','p','qc_inspection_min']].assign(p=lambda t:(t.p*t.units_produced).round(1)).to_string())
for ln in ['L2','L3']:
    x=dd[dd.line==ln]; c='2025-06-17' if ln=='L2' else '2025-07-21'
    print(ln, x.groupby(x.date>=c)[['mtc','hum','cycle_time_s','machine_age_years','ambient_temp_c','units_produced']].mean())
E
python3 $TMPDIR/u.py 2>&1 | sed -n '/@@@@@@/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/u.py <<'E'
print('$$$$$$')
x=dd[dd.line=='L2'].copy()
best=[]
for c in pd.date_range('2025-05-15','2025-07-15'):
    x['post']=(x.date>=c)*1
    r=fit(f+'-C(line)+post',x); best.append((r.deviance,c.date()))
print(sorted(best)[:6])
E
python3 $TMPDIR/u.py 2>&1 | sed -n '/\$\$\$\$/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/u.py <<'E'
print('%%%%%%')
dd['reg']=np.where((dd.line=='L3')&(dd.date>='2025-07-21'),'L3post',np.where((dd.line=='L2')&(dd.date>='2025-06-16'),'L2post','base'))
print(smf.ols('qc_inspection_min~rate+units_produced+C(reg)',dd).fit().summary().tables[1])
print(smf.ols('rework_cost_eur~defective_units+C(reg)',dd).fit().summary().tables[1])
print(smf.ols('qc_inspection_min~rate',dd).fit().rsquared)
E
python3 $TMPDIR/u.py 2>&1 | sed -n '/%%%%%%/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/v.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
d['hc']=d.hum-40
d['l2p']=((d.line=='L2')&(d.date>='2025-06-16'))*1
d['l3p']=((d.line=='L3')&(d.date>='2025-07-21'))*1
dd=d.dropna(subset=['mtc','hum']).copy()
def fit(f,data):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit()
def show(r): print(r.params.round(4).to_string()); print('dev',round(r.deviance), r.df_resid, round(r.pearson_chi2/r.df_resid,2))
x=dd[dd.l3p==0]
f='mtc+(hc+I(hc**2))*C(sup)+C(shift)+dsc+cycle_time_s+C(line)+l2p'
show(fit(f,x))
for ln in ['L1','L2','L3','L4']:
    y=x[x.line==ln]; r=fit('mtc+(hc+I(hc**2))*C(sup)+C(shift)+dsc+cycle_time_s+l2p' if ln=='L2' else 'mtc+(hc+I(hc**2))*C(sup)+C(shift)+dsc+cycle_time_s',y)
    print(ln, r.params[['dsc','C(shift)[T.Night]','mtc']].round(4).to_dict(), round(r.pearson_chi2/r.df_resid,2))
E
python3 $TMPDIR/v.py

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/v.py <<'E'
print('=====')
x=x.copy()
x['dscb']=pd.cut(x.dsc,[-1,0,2,4,6,8,10,12,14,16,18,21,25,30,70])
x['grp']=np.where(x.line=='L4','L4','other')
for g in ['other','L4']:
    y=x[x.grp==g]
    r=fit('mtc+(hc+I(hc**2))*C(sup)+C(shift)+cycle_time_s+C(line)+l2p+C(dscb)',y); print(g); print(r.params.filter(like='dscb').round(3).to_string())
E
python3 $TMPDIR/v.py | sed -n '/====/,$p'

cd /tmp/edabench_claude_7b_fdgs7; grep L4 maintenance.csv | sort; cat >> $TMPDIR/v.py <<'E'
print('&&&&&')
y=x[x.line=='L4'].copy()
r=fit('mtc+(hc+I(hc**2))*C(sup)+C(shift)+cycle_time_s',y); y['p']=r.predict(y)
y['w']=y.date.dt.to_period('W').dt.start_time
t=y.groupby('w').apply(lambda g:pd.Series(dict(o=g.defective_units.sum(),e=(g.p*g.units_produced).sum())));t['r']=t.o/t.e
print(t.r.round(2).to_string())
E
python3 $TMPDIR/v.py | sed -n '/&&&&&/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/w.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
d['hc']=d.hum-40
d['l2p']=((d.line=='L2')&(d.date>='2025-06-16'))*1
d['l3p']=((d.line=='L3')&(d.date>='2025-07-21'))*1
d['dscx']=np.where(d.line=='L4',0,d.dsc)
dd=d.dropna(subset=['mtc','hum']).copy()
x=dd[dd.l3p==0].copy()
def fit(f,data=x):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit(scale='X2')
base='mtc+(hc+I(hc**2))*C(sup)+C(shift)+dscx+cycle_time_s+C(line)+l2p'
r=fit(base); print(r.deviance, r.scale)
for add in ['ambient_temp_c','machine_age_years','C(operator_id)','I(mtc**2)','I(cycle_time_s**2)','mtc:C(sup)','cycle_time_s:C(sup)','C(shift):C(line)','mtc:hc','dscx:C(sup)']:
    r2=fit(base+'+'+add)
    print(add, 'ddev',round(r.deviance-r2.deviance,1),'ddf',r.df_resid-r2.df_resid, 'F-ish', round((r.deviance-r2.deviance)/(r.df_resid-r2.df_resid)/r2.scale,2))
r2=fit(base+'+ambient_temp_c+machine_age_years'); print(r2.summary().tables[1])
E
python3 $TMPDIR/w.py

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/w.py <<'E'
print('######')
from scipy import stats
r2=fit(base+'+C(operator_id)')
print(1-stats.f.cdf((r.deviance-r2.deviance)/20/r2.scale,20,r2.df_resid))
print(r2.params.filter(like='operator').round(3).to_string())
x['res']=(x.defective_units-r.predict(x)*x.units_produced)/np.sqrt(r.predict(x)*x.units_produced)
print(x.groupby('operator_id').res.agg(['mean','std']).round(2).T.to_string())
print(x.res.std())
E
python3 $TMPDIR/w.py | sed -n '/####/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/w.py <<'E'
print('@@@@@')
x['mraw']=x.mt
x['l1pre']=((x.line=='L1')&(x.date<'2025-04-14'))*1
b2=base.replace('mtc','mraw')
r3=fit(b2+'+l1pre'); print(r3.params[['mraw','l1pre']], r3.bse[['mraw','l1pre']], r3.params['l1pre']/r3.params['mraw'])
E
python3 $TMPDIR/w.py | sed -n '/@@@@@/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/x.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf
d=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl').dropna(subset=['mt'])
d['l1pre']=((d.line=='L1')&(d.date<'2025-04-14'))*1
d['mo']=d.date.dt.month
r=smf.ols('mt~ambient_temp_c+C(line)+l1pre+C(shift)+C(sup)',d).fit(); print(r.params.round(2), r.bse['l1pre'])
d['l1m']=np.where(d.l1pre==1,d.mo,0)
r=smf.ols('mt~ambient_temp_c+C(line)+C(l1m)',d).fit(); print(r.params.filter(like='l1m').round(2))
for ln in ['L1','L2','L3','L4']:
    print(ln, smf.ols('mt~ambient_temp_c',d[(d.line==ln)&(d.l1pre==0)]).fit().params.round(2).to_dict(), d[d.line==ln].mt.sub(0).std())
E
python3 $TMPDIR/x.py

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/w.py <<'E'
print('!!!!!')
x['pos']=np.maximum(x.dct,0)
r2=fit(base+'+pos'); print(r2.params[['cycle_time_s','pos']], r2.bse[['pos']])
x['cb']=pd.cut(x.dct,[-20,-8,-5,-3,-1,1,3,5,8,20])
r2=fit(base.replace('+cycle_time_s','')+'+C(cb)'); print(r2.params.filter(like='cb').round(3).to_string())
x['hb']=pd.cut(x.hum,[0,15,20,25,30,35,40,45,50,55,60,65,80])
for s in ['SP-01','SP-02','SP-03']:
    y=x[x.sup==s]
    r2=fit('mtc+C(shift)+dscx+cycle_time_s+C(line)+l2p+C(hb)',y); print(s, r2.params.filter(like='hb').round(2).values)
E
python3 $TMPDIR/w.py 2>&1| sed -n '/!!!!!/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat >> $TMPDIR/w.py <<'E'
print('?????')
a=x[x.sup=='SP-01']
rest='mtc+C(shift)+dscx+cycle_time_s+C(line)+l2p+'
grid=pd.DataFrame({'hum':np.arange(12,72.1,0.5)})
for nm,form in [('quad','hum+I(hum**2)'),('cubic','hum+I(hum**2)+I(hum**3)'),('cs4','cr(hum,df=4)'),('cs5','cr(hum,df=5)'),('cs6','cr(hum,df=6)'),('bs','bs(hum,df=5)')]:
    r2=fit(rest+form,a)
    g=grid.copy(); 
    for c in ['mtc','dscx','cycle_time_s','l2p']: g[c]=a[c].mean()
    g['shift']='Day'; g['line']='L1'
    p=r2.predict(g); print(nm, round(r2.deviance,1), g.hum[p.values.argmin()])
for s in ['SP-02','SP-03']:
    b=x[x.sup==s]
    for nm,form in [('quad','hum+I(hum**2)'),('cs5','cr(hum,df=5)')]:
        r2=fit(rest+form,b); g=grid.copy()
        for c in ['mtc','dscx','cycle_time_s','l2p']: g[c]=b[c].mean()
        g['shift']='Day'; g['line']='L1'; p=r2.predict(g); print(s,nm,round(r2.deviance,1), g.hum[p.values.argmin()])
E
python3 $TMPDIR/w.py 2>&1| sed -n '/?????/,$p'

cd /tmp/edabench_claude_7b_fdgs7; cat > $TMPDIR/y.py <<'E'
import pandas as pd, numpy as np, os, warnings
warnings.filterwarnings('ignore')
import statsmodels.formula.api as smf, statsmodels.api as sm
D=pd.read_pickle(os.environ['TMPDIR']+'/d2.pkl')
for off in [7.0,7.3]:
    mt=D.mt+np.where((D.line=='L1')&(D.date<'2025-04-14'),off,0); print('A4',off,mt.median(), D.mt.median())
print(D[D.line=='L3'].mt.describe())
D['hc']=D.hum-40
D['l2p']=((D.line=='L2')&(D.date>='2025-06-16'))*1
D['l3p']=((D.line=='L3')&(D.date>='2025-07-21'))*1
D['dscx']=np.where(D.line=='L4',0,D.dsc)
dd=D.dropna(subset=['mtc','hum']).copy()
x=dd[dd.l3p==0]
def fit(f,data=x):
    return smf.glm('rate~'+f,data,family=sm.families.Binomial(),var_weights=data.units_produced).fit()
base='mtc+(hc+I(hc**2))*C(sup)+C(shift)+dscx+cycle_time_s+C(line)+l2p'
r=fit(base)
# C1
names={'SP-01':'Alpha','SP-02':'Beta','SP-03':'Gamma'}
rec={'SP-01':30,'SP-02':30,'SP-03':36}
for s in rec:
    g=dd.copy(); g['sup']=s; g['cycle_time_s']=rec[s]
    p=r.predict(g); print(names[s], (p*g.units_produced).sum()/g.units_produced.sum())
g=dd.copy(); print('actual-model', (r.predict(g)*g.units_produced).sum()/g.units_produced.sum(), g.defective_units.sum()/g.units_produced.sum())
# C3
beta=r.params['dscx']; print('beta',beta)
for mode in ['mod14','cap14','mod13']:
    D2=D.copy()
    new = D2.dsc%14 if mode=='mod14' else (np.minimum(D2.dsc,14) if mode=='cap14' else D2.dsc%13)
    new=np.where(D2.line=='L4',D2.dsc,new)
    dl=(D2.dsc-new)
    lo=(D2.line=='L4')
    # p per row: model p where available else observed rate
    p=r.predict(D2.assign(mtc=D2.mtc.fillna(D2.mtc.mean()),hc=D2.hc.fillna(0),hum=D2.hum.fillna(40)))
    # use baseline-model p only for odds conversion
    lg=np.log(p/(1-p)); pn=1/(1+np.exp(-(lg-beta*dl)))
    ratio=pn/p
    newdef=(D2.defective_units*ratio).sum(); print(mode,'ratio-approach',newdef/D2.units_produced.sum())
    # observed-odds approach
    po=D2.rate; lo_=np.log(po/(1-po)); pn2=1/(1+np.exp(-(lo_-beta*dl))); print(mode,'obs-odds',(pn2*D2.units_produced).sum()/D2.units_produced.sum())
E
python3 $TMPDIR/y.py
