cd /tmp/edabench_claude_letxn2__; ls; for f in *.csv; do echo $f; head -5 $f; wc -l $f; done

cd /tmp/edabench_claude_letxn2__; python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str)
print(b.nunique())
for c in ['shift','operator_id','supplier_code','line']: print(b[c].value_counts(dropna=False))
print(b.batch_id.duplicated().sum(), b.duplicated().sum())
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min']:
    x=pd.to_numeric(b[c],errors='coerce'); print(c,x.isna().sum(),x.describe().to_dict()); print(b[c][x.isna()].value_counts(dropna=False).head())
print(b.production_date.str.len().value_counts()); print(b.production_date.sample(10).tolist())
"; cat maintenance.csv | cut -d, -f3,4 | sort | uniq -c

cd /tmp/edabench_claude_letxn2__; grep sensor maintenance.csv; python3 -c "
import pandas as pd,numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b),b.batch_id.duplicated().sum())
d=b.production_date
iso=d.str.match(r'\d{4}-')
b['date']=pd.to_datetime(d.where(iso),errors='coerce').fillna(pd.to_datetime(d.where(~iso),format='%m/%d/%Y',errors='coerce'))
print(b.date.isna().sum(),b.date.min(),b.date.max())
print(b.humidity_pct.describe(), (b.humidity_pct<=0).sum(), b.humidity_pct.isna().sum(), (b.humidity_pct>=99).sum())
print(b.humidity_pct.sort_values().head(8).tolist(), b.humidity_pct.sort_values().tail(5).tolist())
print(np.histogram(b.mold_temp,bins=[-1,1,100,150,180,200,220,250,300,350,400,500]))
print(b.groupby('line').mold_temp.describe())
print(b.mold_temp[b.mold_temp<150].value_counts().head())
b.to_pickle('/tmp/b.pkl')
"

mkdir -p $TMPDIR; cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/l.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('/tmp/edabench_claude_letxn2__/batches.csv').drop_duplicates()
d=b.production_date
sl=d.str.contains('/')
print(d[sl].str[:2].astype(int).max(), d[sl].str[3:5].astype(int).max())
print(d[~sl].sort_values().iloc[[0,-1]].tolist())
E
python3 $TMPDIR/l.py

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/l.py <<'E'
iso=pd.to_datetime(d.where(~sl),errors='coerce')
print(iso.is_monotonic_increasing, iso.dropna().is_monotonic_increasing)
b['iso']=iso
print(b[['production_date','line']].iloc[::150].to_string())
x=d[sl]; a=x.str[:2].astype(int); c=x.str[3:5].astype(int)
print((a>12).sum(),(c>12).sum(),((a<=12)&(c<=12)).sum())
E
python3 $TMPDIR/l.py

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/l.py <<'E'
fmt=np.where(~sl,'iso',np.where(a>12,'dmy',np.where(c>12,'mdy','amb')))
fmt=pd.Series(fmt,index=b.index)
print(pd.crosstab(b.line,fmt))
E
python3 $TMPDIR/l.py | tail -7

cd /tmp/edabench_claude_letxn2__; sed -i '/^x=d\[sl\]/,$d' $TMPDIR/l.py; cat >> $TMPDIR/l.py <<'E'
a=d.str[:2]; c=d.str[3:5]
a=pd.to_numeric(a,errors='coerce'); c=pd.to_numeric(c,errors='coerce')
fmt=pd.Series(np.where(~sl,'iso',np.where(a>12,'dmy',np.where(c>12,'mdy','amb'))),index=b.index)
print(pd.crosstab(b.line,fmt))
E
python3 $TMPDIR/l.py | tail -7

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/c.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('/tmp/edabench_claude_letxn2__/batches.csv').drop_duplicates().reset_index(drop=True)
d=b.production_date
fmt=np.where(b.line=='L4','%d/%m/%Y',np.where(b.line=='L1','%m/%d/%Y','%Y-%m-%d'))
b['date']=[pd.to_datetime(x,format=f) for x,f in zip(d,fmt)]
b['sup']=b.supplier_code.str.strip().str.upper()
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
sup=pd.read_csv('suppliers.csv'); b=b.merge(sup,left_on='sup',right_on='supplier_code',suffixes=('','_s'))
b['rate']=b.defective_units/b.units_produced
b['mt']=b.mold_temp.where(b.mold_temp>0)
b['mt']=np.where(b.line=='L3',(b.mt-32)/1.8,b.mt)
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
E
cat > $TMPDIR/a.py <<'E'
exec(open('/tmp/claude-0/-tmp-edabench-claude-letxn2--/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/c.py').read())
print(b.date.min(),b.date.max(),len(b))
print((b.humidity_pct<0).sum(),b.humidity_pct.isna().sum(),b.hum.isna().sum(), b.humidity_pct[b.humidity_pct<=0].value_counts())
print(b.defective_units.sum()/b.units_produced.sum(), b.mt.median(), b.mt.isna().sum())
print(b.groupby('line').mt.describe())
l1=b[b.line=='L1']; print(l1.groupby(l1.date>='2025-04-14').mt.describe())
print(b.groupby('line').mt.apply(lambda s:s.groupby(b.date.dt.month).mean()).unstack().round(1))
print((b.defective_units>b.units_produced).sum(), b.rate.describe())
E
cp $TMPDIR/c.py /tmp/claude-0/-tmp-edabench-claude-letxn2--/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/c.py 2>&1; echo $TMPDIR

cd /tmp/edabench_claude_letxn2__; sed -i "s#^exec.*#exec(open('/tmp/claude-0/c.py').read())#" $TMPDIR/a.py; python3 $TMPDIR/a.py

cd /tmp/edabench_claude_letxn2__; sed -i "s#pd.to_datetime(x,format=f)#pd.to_datetime(x,format=str(f))#" $TMPDIR/c.py; python3 $TMPDIR/a.py

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/d.py <<'E'
exec(open('/tmp/claude-0/c.py').read())
import statsmodels.formula.api as smf
b['post']=(b.date>='2025-04-14').astype(int)
for l,g in b.groupby('line'):
    g=g.dropna(subset=['mt'])
    print(l,smf.ols('mt~ambient_temp_c+post+cycle_time_s+machine_age_years',g).fit().params.round(2).to_dict())
g=b[b.line=='L1'].dropna(subset=['mt']);g=g[(g.date>'2025-04-01')&(g.date<'2025-04-28')]
print(g.groupby('date').mt.mean().round(1).to_string())
E
python3 $TMPDIR/d.py

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/e.py <<'E'
exec(open('/tmp/claude-0/c.py').read())
import statsmodels.formula.api as smf, statsmodels.api as sm
m=(b.line=='L1')&(b.date>='2025-04-14')
b['mt']=b.mt-7*m
print('A4',b.mt.median())
print(b[['rate','qc_inspection_min','rework_cost_eur','mt','hum','cycle_time_s','machine_age_years','ambient_temp_c']].corr().round(2)['rate'])
print(b.groupby('sup').rate.mean(), b.groupby('shift').rate.mean())
# days since cleaning
mt_=pd.read_csv('maintenance.csv',parse_dates=['date']);mt_=mt_[mt_.event=='mold_cleaning']
def ds(r):
    c=mt_[(mt_.line==r.line)&(mt_.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
b['dsc']=b.apply(ds,axis=1)
print(b.dsc.describe()); print(b.groupby(pd.cut(b.dsc,[-1,0,3,7,10,14,20,30,100])).rate.agg(['mean','count']))
b['ctd']=b.cycle_time_s-b.recipe_cycle_time_s
b.to_csv('/tmp/claude-0/b2.csv',index=False)
E
python3 $TMPDIR/e.py

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_csv('/tmp/claude-0/b2.csv',parse_dates=['date'])
b['nd']=b.units_produced-b.defective_units
b['hum2']=b.hum.fillna(b.hum.mean()); b['hmiss']=b.hum.isna().astype(int)
f='nd+defective_units~'
def fit(rhs,d=b):
    return smf.glm('rate~'+rhs,d,family=sm.families.Binomial(),freq_weights=d.units_produced).fit(cov_type='HC0')
r=fit('mt+hum+cycle_time_s+ctd+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+C(line)+dsc',b.dropna(subset=['mt','hum']))
print(r.summary().tables[1])
E
python3 $TMPDIR/f.py

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_csv('/tmp/claude-0/b2.csv',parse_dates=['date'])
b['nd']=b.units_produced-b.defective_units; b['df']=b.defective_units
def fit(rhs,d):
    return smf.glm('df+nd~'+rhs,d,family=sm.families.Binomial()).fit(scale='X2')
d=b.dropna(subset=['mt','hum'])
r=fit('mt+hum+I(hum**2)+cycle_time_s+machine_age_years+ambient_temp_c+C(operator_id)+C(shift)+C(sup)+C(line)+dsc',d)
print(r.summary().tables[1])
E
python3 $TMPDIR/f.py

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_csv('/tmp/claude-0/b2.csv',parse_dates=['date'])
print(b.groupby('line').machine_age_years.describe())
print(b.groupby('line').rate.mean(), b.groupby('line').dsc.mean())
print(b.groupby('operator_id').line.nunique().head(), b.groupby('operator_id').shift.nunique().head())
print(pd.crosstab(b.line,b.sup))
E
python3 $TMPDIR/f.py

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np
b=pd.read_csv('/tmp/claude-0/b2.csv',parse_dates=['date'])
print(pd.crosstab(b.operator_id,b.line).T.to_string())
print(pd.crosstab(b.operator_id,b['shift']).T.to_string())
E
python3 $TMPDIR/f.py

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/f.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
b=pd.read_csv('/tmp/claude-0/b2.csv',parse_dates=['date'])
b['nd']=b.units_produced-b.defective_units; b['df']=b.defective_units
d=b.dropna(subset=['mt','hum']).copy()
def fit(rhs,d=d):
    return smf.glm('df+nd~'+rhs,d,family=sm.families.Binomial()).fit(scale='X2')
base='mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+C(shift)+C(sup)+C(line)+dsc+machine_age_years'
full=fit(base)
print(full.scale); print(full.summary().tables[1])
def drop(term,rhs):
    return rhs.replace('+'+term,'')
for t in ['mt','cycle_time_s','ambient_temp_c','C(shift)','machine_age_years','C(sup)','dsc']:
    r=fit(drop(t,base)); print(t, 'dev diff/scale', (r.deviance-full.deviance)/full.scale)
r=fit(base+'+C(operator_id)'); print('operator',(full.deviance-r.deviance)/r.scale, r.df_model-full.df_model)
E
python3 $TMPDIR/f.py 2>&1 | grep -v Warn

cd /tmp/edabench_claude_letxn2__; python3 - <<'E' 2>&1 | grep -v -i warn
import re
s=open('/tmp/claude-0/f.py').read()
s=s.replace("smf.glm('df+nd~'+rhs,d,family=sm.families.Binomial()).fit(scale='X2')","smf.glm('rate~'+rhs,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')")
open('/tmp/claude-0/f.py','w').write(s)
E
python3 $TMPDIR/f.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/f.py <<'E'
d['res']=(d.rate-full.fittedvalues)
d['wk']=d.date.dt.to_period('W').astype(str)
for l,g in d.groupby('line'):
    s=g.groupby('wk').apply(lambda x: np.average(x.res,weights=x.units_produced))
    print(l,(s*1000).round(0).astype(int).tolist())
E
python3 $TMPDIR/f.py 2>&1 | tail -4

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/f.py <<'E'
print('----')
for l in ['L2','L3']:
    g=d[d.line==l]
    s=g.groupby('wk').agg(raw=('rate','mean'),mt=('mt','mean'),hum=('hum','mean'),ct=('cycle_time_s','mean'),amb=('ambient_temp_c','mean'),dsc=('dsc','mean'))
    print(l);print(s.iloc[18:36].round(3).to_string())
    g=g.sort_values('date'); 
    for lo,hi in [('2025-06-01','2025-06-30'),('2025-07-01','2025-07-31')]:
        x=g[(g.date>=lo)&(g.date<=hi)].groupby('date').res.mean().round(3); print(x.to_string()) if l=='L3' and lo.startswith('2025-07') else None
E
python3 $TMPDIR/f.py 2>&1 | sed -n '/----/,$p'

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/g.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_csv('/tmp/claude-0/b2.csv',parse_dates=['date'])
b['over']=np.maximum(b.dsc-14,0); b['alpha']=(b.sup=='SP-01').astype(int)
d=b.dropna(subset=['mt','hum']).copy()
def fit(rhs,d=d):
    return smf.glm('rate~'+rhs,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
base='mt+hum+I(hum**2)+cycle_time_s+ambient_temp_c+C(shift)+C(sup)+C(line)+over'
f=fit(base);print(f.scale);print(f.params.round(4).to_dict())
f2=fit(base+'+dsc');print(f2.scale,f2.params[['over','dsc']])
f3=fit('mt+hum*C(sup)+I(hum**2)*C(sup)+cycle_time_s*C(sup)+ambient_temp_c+C(shift)+C(line)+over');print(f3.scale)
print(f3.params.round(4).to_dict())
d['res']=d.rate-f.fittedvalues
d['wk']=d.date.dt.to_period('W').astype(str)
for l,g in d.groupby('line'):
    s=g.groupby('wk').apply(lambda x: np.average(x.res,weights=x.units_produced))
    print(l,(s*1000).round(0).astype(int).tolist())
print(d.groupby(['line',d.date.dt.month]).qc_inspection_min.mean().unstack().round(1))
E
python3 $TMPDIR/g.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/g.py <<'E'
print('=====')
d=d[~((d.line=='L3')&(d.date>='2025-07-15'))]
f=fit(base,d)
g=d[d.line=='L2'].copy(); g['res']=g.rate-f.fittedvalues[g.index]
print(g[(g.date>='2025-06-05')&(g.date<='2025-06-25')].groupby('date').apply(lambda x: pd.Series({'res':np.average(x.res,weights=x.units_produced),'n':len(x)})).round(3).to_string())
best=[]
for dt in pd.date_range('2025-05-20','2025-07-10'):
    d['post']=((d.line=='L2')&(d.date>=dt)).astype(int)
    r=fit(base+'+post',d); best.append((r.deviance,dt))
print(sorted(best)[:5])
# L3 inspection drop date
g=b[b.line=='L3'].groupby('date').qc_inspection_min.mean(); print(g['2025-07-10':'2025-07-30'].round(1).to_string())
E
python3 $TMPDIR/g.py 2>&1 | sed -n '/=====/,$p'

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/h.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_csv('/tmp/claude-0/b2.csv',parse_dates=['date'])
b['over']=np.maximum(b.dsc-14,0)
b['post2']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
d=b.dropna(subset=['mt','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
def fit(rhs,d=d):
    return smf.glm('rate~'+rhs,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
common='mt+ambient_temp_c+C(shift)+C(line)+over+post2+machine_age_years'
forms={'raw':'cycle_time_s+hum+I(hum**2)+C(sup)',
'ctd':'ctd+hum+I(hum**2)+C(sup)',
'ctd_sq':'ctd+I(ctd**2)+hum+I(hum**2)+C(sup)',
'ctd_sqH_alphaonly':'ctd+I(ctd**2)+hum+I(hum**2)+C(sup)+hum:C(sup)+I(hum**2):C(sup)',
'ctdabs':'ctd+I(ctd**2)+hum+I(hum**2):alpha+C(sup)'}
d['alpha']=(d.sup=='SP-01').astype(int)
for k,v in forms.items():
    r=fit(common+'+'+v); print(k,round(r.scale,3),round(r.deviance,1)); 
r=fit(common+'+'+forms['ctd_sq']); print(r.summary().tables[1])
E
python3 $TMPDIR/h.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/h.py <<'E'
print('=======')
c2='C(shift)+C(line)+over+post2'
for k,v in {'a':'mt+cycle_time_s+hum+I(hum**2)',}.items():
    pass
R={}
R['all_int']=fit(c2+'+C(sup)*(mt+cycle_time_s+hum+I(hum**2))')
R['hum_int']=fit(c2+'+C(sup)*(hum+I(hum**2))+mt+cycle_time_s')
R['hum_cyc']=fit(c2+'+C(sup)*(hum+I(hum**2)+cycle_time_s)+mt')
R['hum_mt']=fit(c2+'+C(sup)*(hum+I(hum**2)+mt)+cycle_time_s')
for k,r in R.items(): print(k,round(r.scale,3),round(r.deviance,1))
r=R['hum_int']; print(r.summary().tables[1])
E
python3 $TMPDIR/h.py 2>&1 | sed -n '/=======/,$p'

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/h.py <<'E'
print('#########')
for s,g in d.groupby('sup'):
    r=fit(c2+'+mt+cycle_time_s+hum+I(hum**2)',g)
    a,bq=r.params['hum'],r.params['I(hum ** 2)']
    print(s,len(g),round(r.scale,2),a,bq,'opt',-a/(2*bq), r.bse[['hum','I(hum ** 2)']].values)
    g=g.assign(res=g.rate-r.fittedvalues)
    # cubic
    r3=fit(c2+'+mt+cycle_time_s+hum+I(hum**2)+I(hum**3)',g); print('cubic p',r3.pvalues['I(hum ** 3)'], round(r3.scale,2))
    # abs-dev from optimum
E
python3 $TMPDIR/h.py 2>&1 | sed -n '/####/,$p'

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/h.py <<'E'
print('@@@@@@@@')
base2=c2+'+C(sup)*(hum+I(hum**2))+mt+cycle_time_s'
r0=fit(base2)
for extra in ['I(mt**2)','I(cycle_time_s**2)','C(sup):mt','C(sup):cycle_time_s','mt:cycle_time_s','C(shift):mt','C(shift):hum','C(line):mt','ambient_temp_c','machine_age_years','dsc','C(operator_id)','C(line):hum','C(line):cycle_time_s','C(line):over']:
    r=fit(base2+'+'+extra); print(extra,round(r.scale,3),round((r0.deviance-r.deviance)/r.scale,1), r.df_model-r0.df_model)
E
python3 $TMPDIR/h.py 2>&1 | sed -n '/@@@@/,$p'

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/h.py <<'E'
print('$$$$$$$$')
b2=c2.replace('+over','')
base3=b2+'+C(sup)*(hum+I(hum**2))+mt+cycle_time_s'
d['dsc_c']=d.dsc
for name,ex in {'lin':'dsc','hinge14':'over','lin+hinge':'dsc+over','cap20':'I(np.minimum(dsc,20))','cap25':'I(np.minimum(dsc,25))','quad':'dsc+I(dsc**2)'}.items():
    r=fit(base3+'+'+ex); print(name,round(r.scale,3),round(r.deviance,1),r.params.filter(like='dsc').round(4).to_dict() or r.params.filter(like='over').round(4).to_dict())
r=fit(base3+'+C(pd.cut(dsc,[-1,0,2,4,6,8,10,12,14,16,18,20,25,40]))')
print(r.params.filter(like='dsc').round(3).to_string())
E
python3 $TMPDIR/h.py 2>&1 | sed -n '/\$\$\$\$/,$p'

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/h.py <<'E'
print('%%%%%%%')
print(d.groupby('sup').cycle_time_s.describe(), d.groupby('sup').ctd.describe())
print(d.groupby('sup')[['mt','hum','ambient_temp_c']].mean())
E
python3 $TMPDIR/h.py 2>&1 | sed -n '/%%%%/,$p'

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/k.py <<'E'
import pandas as pd,numpy as np,statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_csv('/tmp/claude-0/b2.csv',parse_dates=['date'])
b['post2']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['l1post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
d=b.dropna(subset=['mt','hum']).copy()
d=d[~((d.line=='L3')&(d.date>='2025-07-21'))]
def fit(rhs,d):
    return smf.glm('rate~'+rhs,d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
rhs='C(shift)+C(line)+post2+C(sup)*(hum+I(hum**2))+mt+ctd+dsc'
for off in [0,3,5,6,7,8,9,10,12]:
    d['mt']=d.mt0 if 'mt0' in d else d.mt
    if 'mt0' not in d: d['mt0']=d.mt
    d['mt']=d.mt0-(7-off)*0  # placeholder
E
echo

cd /tmp/edabench_claude_letxn2__; python3 - <<'E' 2>&1 | grep -v -i warn
exec(open('/tmp/claude-0/k.py').read().split("for off")[0])
d['mtraw']=d.mt+7*d.l1post
r=fit(rhs.replace('+mt','+mtraw')+'+l1post',d); print(r.params[['mtraw','l1post']], r.params['l1post']/r.params['mtraw'])
r=fit(rhs+'+l1post',d); print(r.params[['mt','l1post']],r.bse['l1post'])
E

cd /tmp/edabench_claude_letxn2__; cat > $TMPDIR/z.py <<'E'
exec(open('/tmp/claude-0/k.py').read().split("for off")[0])
r=fit(rhs,d); print(r.summary().tables[1], r.scale)
for ex in ['ambient_temp_c','machine_age_years','C(operator_id)','C(shift):hum','C(sup)*mt','C(sup)*ctd']:
    r2=fit(rhs+'+'+ex,d); print(ex,round((r.deviance-r2.deviance)/r2.scale,1),r2.df_model-r.df_model)
# calibration
d['p']=r.predict(d); print((d.p*d.units_produced).sum(),d.defective_units.sum())
# imputation for all rows
b['alpha']=0
full=b.copy()
full['mt']=full.mt.fillna(full.groupby('line').mt.transform('median'))
full['hum_f']=full.hum.fillna(full.hum.median()); full['hum']=full.hum_f
full['dsc0']=full.dsc
def pred(df): return (r.predict(df)*df.units_produced).sum()/df.units_produced.sum()
print('fact',pred(full))
# C1
rec={'SP-01':30,'SP-02':30,'SP-03':36}
for s,n in [('SP-01','Alpha'),('SP-02','Beta'),('SP-03','Gamma')]:
    f=full.copy(); f['sup']=s; print(n,pred(f))
# C2
a=full[full.sup=='SP-01']
for h in np.arange(5,70,1.0):
    pass
hs=np.arange(float(d.hum.min()),float(d.hum.max())+0.01,0.1)
vals=[]
for h in hs:
    f=a.copy(); f['hum']=h; vals.append(pred(f))
print('opt hum',hs[int(np.argmin(vals))], d.hum.min(), d.hum.max())
# C3 simulate cleaning
mt_=pd.read_csv('maintenance.csv',parse_dates=['date']); mt_=mt_[mt_.event=='mold_cleaning']
newdsc={}
for l,g in full.groupby('line'):
    cl=set(mt_[mt_.line==l].date)
    start=min(cl); last=start; m={}
    for day in pd.date_range(start,'2025-09-30'):
        if day in cl: last=day
        elif (day-last).days>=14: last=day
        m[day]=(day-last).days
    newdsc[l]=m
full['dsc']=[newdsc[l][dt] for l,dt in zip(full.line,full.date)]
print(full.dsc.max(),full.dsc0.mean(),full.dsc.mean())
print('C3',pred(full))
full['dsc']=full.dsc0.clip(upper=14); print('C3 cap14',pred(full))
E
python3 $TMPDIR/z.py 2>&1 | grep -v -i warn

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/z.py <<'E'
print('OPERATORS')
r2=fit(rhs+'+C(operator_id)',d)
o=r2.params.filter(like='operator'); s=r2.bse.filter(like='operator'); print(pd.DataFrame({'c':o,'se':s,'z':o/s}).round(3).to_string())
# flexible alpha humidity
a=d[d.sup=='SP-01']
r3=fit('C(shift)+C(line)+post2+mt+ctd+dsc+bs(hum,df=6)',a); 
hs=np.arange(13,70,0.5); X=pd.DataFrame({'hum':hs}); 
base=a.iloc[[0]].copy()
pr=[]
for h in hs:
    f=a.copy(); f['hum']=h; pr.append((r3.predict(f)*f.units_produced).sum())
print('spline opt',hs[int(np.argmin(pr))])
E
python3 $TMPDIR/z.py 2>&1 | sed -n '/OPERATORS/,$p' | grep -v -i warn

cd /tmp/edabench_claude_letxn2__; cat >> $TMPDIR/z.py <<'E'
print('RESOP')
d['res']=(d.rate-r.fittedvalues)/ (r.fittedvalues*(1-r.fittedvalues))  # working residual on logit scale
d['w']=d.units_produced*r.fittedvalues*(1-r.fittedvalues)
def agg(g):
    m=np.average(g.res,weights=g.w); return pd.Series({'m':m,'se':np.sqrt(2.71/g.w.sum()),'n':len(g)})
t=d.groupby(['line','operator_id']).apply(agg); t['z']=t.m/t.se; print(t.round(3).to_string())
E
python3 $TMPDIR/z.py 2>&1 | sed -n '/RESOP/,$p' | grep -v -i warn
