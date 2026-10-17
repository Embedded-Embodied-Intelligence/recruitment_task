ls -la && for f in batches.csv suppliers.csv maintenance.csv; do echo "== $f"; wc -l $f; head -5 $f; done

python3 -c "
import pandas as pd
b=pd.read_csv('batches.csv',dtype=str,keep_default_na=False)
print(b.shape)
for c in b.columns:
    vc=b[c].value_counts()
    print('==',c,'nunique',b[c].nunique(),'blank',(b[c].str.strip()=='').sum())
    if b[c].nunique()<40: print(vc.to_dict())
    else: print(b[c].sample(15,random_state=1).tolist())
print('dup batch rows', b.duplicated().sum(), 'dup batch_id', b.batch_id.duplicated().sum())
print(open('suppliers.csv').read()); 
m=pd.read_csv('maintenance.csv',dtype=str,keep_default_na=False)
print(m.to_string())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
print(b.dtypes)
print(b.describe().T.to_string())
d=b[b.duplicated(keep=False)]
print('exact dup rows', b.duplicated().sum())
print('dup batch ids', b.batch_id.duplicated().sum(), 'ids with >1 row', b.batch_id.value_counts().gt(1).sum())
# check if dup ids are identical rows
g=b[b.batch_id.duplicated(keep=False)].sort_values('batch_id')
print(g.head(8).to_string())
print('non-identical dup ids:', (g.groupby('batch_id').nunique(dropna=False).max(axis=1)>1).sum())
print('humidity NaN', b.humidity_pct.isna().sum())
print(b.loc[b.humidity_pct.isna()].head(3).to_string())
print('mold temp hist'); print(pd.cut(b.mold_temp,[0,100,150,180,200,230,250,300,350,380,400,420,500,1000]).value_counts().sort_index().to_string())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
print(len(b))
print('mold==0', (b.mold_temp<=0).sum(), 'mold<150', (b.mold_temp<150).sum())
print('humidity <0', (b.humidity_pct<0).sum(), 'humidity>100', (b.humidity_pct>100).sum(), 'humidity==0',(b.humidity_pct==0).sum())
print(b.loc[b.humidity_pct<0,['batch_id','humidity_pct']].value_counts().head())
b['hot']=b.mold_temp>300
b['mon']=b.production_date.str[:7]
print(pd.crosstab([b.line],[b.hot]))
print(pd.crosstab(b.mon,[b.line,b.hot]).to_string())
print(b.loc[b.mold_temp<150,['batch_id','line','production_date','mold_temp']].to_string())
"

python3 -c "
import pandas as pd, numpy as np
b=pd.read_csv('batches.csv').drop_duplicates()
b=b[b.mold_temp>0].copy()
b['mC']=np.where(b.line=='L3',(b.mold_temp-32)/1.8,b.mold_temp)
print(b.groupby('line').mC.describe().round(2).to_string())
b['per']=np.where(b.production_date<'2025-04-14','pre','post')
print(b[b.line=='L1'].groupby('per').mC.describe().round(2).to_string())
print(b[b.line=='L3'].mold_temp.describe().round(2).to_string())
print(b[b.line=='L3'].assign(c=lambda x:(x.mold_temp-32)/1.8).groupby(lambda i: 0).c.median())
for l in ['L2','L4','L3']:
  x=b[b.line==l].copy(); x['per']=np.where(x.production_date<'2025-04-14','pre','post'); print(l, x.groupby('per').mC.mean().round(2).to_dict())
"

mkdir -p "$TMPDIR" && S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && mkdir -p $S && cat > $S/clean.py <<'EOF'
import pandas as pd, numpy as np
D='/tmp/edabench_claude_zdn7pe95/'
raw=pd.read_csv(D+'batches.csv')
b=raw.drop_duplicates().copy()
b['shift']=b['shift'].str.strip().str.capitalize().replace({'D':'Day','N':'Night'})
b['supplier_code']=b['supplier_code'].str.strip().str.upper()
sup=pd.read_csv(D+'suppliers.csv')
b=b.merge(sup[['supplier_code','supplier_name','pre_dried']],on='supplier_code',how='left')
b['production_date']=pd.to_datetime(b['production_date'])
b['humidity_valid']=b.humidity_pct.notna()&(b.humidity_pct>=0)
b['mold_valid']=b.mold_temp>0
b['mold_c']=np.where(b.line=='L3',(b.mold_temp-32)/1.8,b.mold_temp)
b['mold_c']=np.where((b.line=='L1')&(b.production_date>='2025-04-14'),b.mold_c-8.0,b.mold_c)
b.loc[~b.mold_valid,'mold_c']=np.nan
b['rate']=b.defective_units/b.units_produced
mt=pd.read_csv(D+'maintenance.csv',parse_dates=['date'])
EOF
cd $S && python3 -c "
exec(open('clean.py').read())
print(b.shape, b.shift.value_counts().to_dict(), b.supplier_name.value_counts().to_dict(), b.supplier_name.isna().sum())
print('A2 invalid humidity unique:', (~b.humidity_valid).sum())
print('date range', b.production_date.min(), b.production_date.max())
print('def>units', (b.defective_units>b.units_produced).sum())
print('rework/def', (b.rework_cost_eur/b.defective_units).describe().round(3).to_dict())
print('corr qc vs defect', b[['qc_inspection_min','defective_units','rework_cost_eur','rate','units_produced']].corr().round(3).to_string())
print(b.groupby(pd.cut(b.defective_units,[0,10,20,40,80,500])).qc_inspection_min.mean())
print('A3', b.defective_units.sum()/b.units_produced.sum())
print('A4', b.mold_c.median(), b.mold_c.notna().sum())
"

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -c "
exec(open('clean.py').read())
print(b.shape, b['shift'].value_counts().to_dict(), b.supplier_name.value_counts().to_dict(), b.supplier_name.isna().sum())
print('A2 invalid humidity unique:', (~b.humidity_valid).sum())
print('date range', b.production_date.min(), b.production_date.max())
print('def>units', (b.defective_units>b.units_produced).sum())
print('rework/def', (b.rework_cost_eur/b.defective_units).describe().round(3).to_dict())
print('corr', b[['qc_inspection_min','defective_units','rework_cost_eur','rate','units_produced']].corr().round(3).to_string())
print(b.groupby(pd.cut(b.defective_units,[0,10,20,40,80,500])).qc_inspection_min.mean())
print('A3', b.defective_units.sum()/b.units_produced.sum())
print('A4', b.mold_c.median(), b.mold_c.notna().sum())
"

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -c "import statsmodels, sklearn; print(statsmodels.__version__, sklearn.__version__)"; python3 -c "
exec(open('clean.py').read())
import statsmodels.formula.api as smf
b['hum']=b.humidity_pct
v=b[b.humidity_valid & b.mold_valid]
# qc: does it depend on defects beyond process vars?
m1=smf.ols('qc_inspection_min ~ defective_units',data=b).fit(); print('qc~defects R2',round(m1.rsquared,3))
m2=smf.ols('qc_inspection_min ~ mold_c+hum+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(supplier_name)+C(line)+np.log(units_produced)',data=b.dropna(subset=['mold_c','hum'])).fit(); print('qc~process R2',round(m2.rsquared,3))
m3=smf.ols('qc_inspection_min ~ mold_c+hum+cycle_time_s+machine_age_years+ambient_temp_c+C(shift)+C(supplier_name)+C(line)+np.log(units_produced)+defective_units',data=b.dropna(subset=['mold_c','hum'])).fit(); print('qc~process+def R2',round(m3.rsquared,3), 'def coef',round(m3.params['defective_units'],4), round(m3.pvalues['defective_units'],4))
"

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
v=b[b.humidity_valid & b.mold_valid].copy()
v['hum']=v.humidity_pct
v['ok']=v.units_produced-v.defective_units
print(len(v))
print(v[['mold_c','hum','cycle_time_s','machine_age_years','ambient_temp_c','units_produced']].corr().round(3).to_string())
f='defective_units + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)'
g=smf.glm('defective_units + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)',data=v,family=sm.families.Binomial()).fit()
print(g.summary2().tables[1].round(4).to_string())
" 2>&1 | head -120

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && cat >> clean.py <<'EOF'
cl=mt[mt.event=='mold_cleaning']
def since(row, cleans=cl):
    c=cleans[(cleans.line==row.line)&(cleans.date<=row.production_date)]
    return (row.production_date-c.date.max()).days if len(c) else np.nan
b['days_since_clean']=b.apply(since,axis=1)
EOF
python3 -c "
exec(open('clean.py').read())
print(b.days_since_clean.describe().round(2).to_string())
print('nan', b.days_since_clean.isna().sum())
print(b.groupby(pd.cut(b.days_since_clean,[-1,0,3,7,10,14,20,30,60])).rate.agg(['mean','size']).round(4).to_string())
print('max gap check', b.groupby('line').days_since_clean.max().to_dict())
"

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf
v=b[b.humidity_valid & b.mold_valid].copy()
v['hum']=v.humidity_pct; v['ok']=v.units_produced-v.defective_units
v['days']=v.days_since_clean
v['t']=(v.production_date-v.production_date.min()).dt.days
base='mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line)'
for extra in ['', ' + days', ' + days + np.log(units_produced)', ' + days + np.log(units_produced) + t']:
    g=smf.glm('defective_units + ok ~ '+base+extra,data=v,family=sm.families.Binomial()).fit()
    print('MODEL extra=',extra, 'deviance',round(g.deviance,1),'aic',round(g.aic,1))
    print(g.params[['mold_c','hum','cycle_time_s','machine_age_years','ambient_temp_c']+[k for k in g.params.index if k in ('days','np.log(units_produced)','t','C(shift)[T.Night]')]].round(4).to_string())
    print(g.pvalues[['mold_c','hum','cycle_time_s','machine_age_years','ambient_temp_c']+[k for k in g.params.index if k in ('days','np.log(units_produced)','t')]].round(4).to_string())
"

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.formula.api as smf, patsy
import numpy as np
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean
X=patsy.dmatrix('mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days',v,return_type='dataframe')
print('shape',X.shape,'rank',np.linalg.matrix_rank(X.values))
print('mold~ambient slope by line/period')
v['post']=v.production_date>='2025-04-14'
for (l,p),g in v.groupby(['line','post']):
    s=np.polyfit(g.ambient_temp_c,g.mold_c,1)
    print(l,p,len(g),np.round(s,3), 'mean mold',round(g.mold_c.mean(),2),'mean amb',round(g.ambient_temp_c.mean(),2))
"

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np, patsy
print(pd.crosstab(b.operator_id,b.line).to_string())
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
g=smf.glm('defective_units + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + C(line) + days',data=v,family=sm.families.Binomial()).fit()
v['mu']=g.predict(v)*v.units_produced
v['res']=(v.defective_units-v.mu)/np.sqrt(v.mu*(1-g.predict(v)))
v['m']=v.production_date.dt.to_period('M')
print(v.groupby(['line','m']).res.agg(['mean','size']).round(2).unstack(0).to_string())
v=v.sort_values('production_date')
for l in ['L1','L2','L3','L4']:
    x=v[v.line==l]
    cs=x.res.cumsum()/np.sqrt(np.arange(1,len(x)+1))
    print(l, 'max|cusum-ish|', round(cs.abs().max(),2), 'at', x.production_date.iloc[int(cs.abs().values.argmax())].date())
" 2>&1 | tail -80

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
g=smf.glm('defective_units + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + days',data=v,family=sm.families.Binomial()).fit()
p=g.predict(v)
v['res']=(v.defective_units-p*v.units_produced)/np.sqrt(p*(1-p)*v.units_produced)
v['dev']=v.defective_units/v.units_produced-p
print('L-residual totals', v.groupby('line').res.mean().round(3).to_dict())
v=v.sort_values('production_date')
for l in ['L1','L2','L3','L4']:
    x=v[v.line==l].reset_index(drop=True)
    best=(0,None)
    res=[]
    for k in range(20,len(x)-20):
        a=x.res[:k]; c=x.res[k:]
        t=stats.ttest_ind(a,c,equal_var=False).statistic
        res.append((abs(t),k,t))
    t,k,tt=max(res)
    d=x.production_date[k]
    print(l,'split at',d.date(),'t=',round(tt,2),'mean before',round(x.res[:k].mean(),2),'after',round(x.res[k:].mean(),2), 'n',k,len(x)-k)
    # daily-ish mean around split
    w=x[(x.production_date>=d-pd.Timedelta(days=21))&(x.production_date<=d+pd.Timedelta(days=21))]
    print(w.groupby(w.production_date.dt.date).res.mean().round(2).to_dict() if l=='L2' else '')
" 2>&1 | tail -40

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
g=smf.glm('defective_units + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + days',data=v,family=sm.families.Binomial()).fit()
p=g.predict(v)
v['res']=(v.defective_units-p*v.units_produced)/np.sqrt(p*(1-p)*v.units_produced)
print('mean res', v.groupby('line').res.mean().round(3).to_dict())
v=v.sort_values('production_date')
for l in ['L1','L2','L3','L4']:
    x=v[v.line==l].reset_index(drop=True)
    res=[]
    for k in range(20,len(x)-20):
        t=stats.ttest_ind(x.res[:k],x.res[k:],equal_var=False).statistic
        res.append((abs(t),k,t))
    t,k,tt=max(res)
    d=x.production_date[k]
    print(l,'split at',d.date(),'t=',round(tt,2),'before',round(x.res[:k].mean(),2),'after',round(x.res[k:].mean(),2),'n',k,len(x)-k)
" 2>&1 | grep -v Warn | tail -20

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
g=smf.glm('defective_units + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + days',data=v,family=sm.families.Binomial()).fit()
p=g.predict(v); v['res']=(v.defective_units-p*v.units_produced)/np.sqrt(p*(1-p)*v.units_produced)
x=v[v.line=='L2'].sort_values('production_date')
w=x[(x.production_date>='2025-06-01')&(x.production_date<='2025-07-05')]
print(w[['production_date','shift','operator_id','supplier_name','mold_c','hum','cycle_time_s','days','rate','res']].round(3).to_string())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
v['lnU']=np.log(v.units_produced)
f='defective_units + ok ~ mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + days + l2shift + lnU'
g=smf.glm(f,data=v,family=sm.families.Binomial()).fit()
keep=['mold_c','hum','cycle_time_s','machine_age_years','ambient_temp_c','C(shift)[T.Night]','days','l2shift','lnU','C(supplier_name)[T.Beta]','C(supplier_name)[T.Gamma]']
print(pd.DataFrame({'coef':g.params[keep],'se':g.bse[keep],'p':g.pvalues[keep]}).round(5).to_string())
print('operator pvals', g.pvalues[[k for k in g.params.index if 'operator' in k]].round(4).sort_values().head(30).to_dict())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
base=' + mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days + l2shift'
full=smf.glm('defective_units + ok ~ C(operator_id)'+base,data=v,family=sm.families.Binomial()).fit()
terms={'mold_c':base.replace(' + mold_c',''),'hum':base.replace(' + hum',''),'cycle_time_s':base.replace(' + cycle_time_s',''),'machine_age_years':base.replace(' + machine_age_years',''),'ambient_temp_c':base.replace(' + ambient_temp_c',''),'shift':base.replace(' + C(shift)',''),'operator_id':None,'supplier':base.replace(' + C(supplier_name)','')}
for k,t in terms.items():
    f='defective_units + ok ~ '+(('C(line)'+t) if t is None else ('C(operator_id)'+t))
    r=smf.glm(f,data=v,family=sm.families.Binomial()).fit()
    lr=2*(full.llf-r.llf); dfz=full.df_model-r.df_model
    print(f'{k:20s} LR={lr:9.2f} df={dfz:.0f} p={stats.chi2.sf(lr,dfz):.3g}')
print(v.groupby('line').machine_age_years.agg(['mean','std']).round(2).to_string())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
base=' + mold_c + hum + cycle_time_s + machine_age_years + ambient_temp_c + C(shift) + C(supplier_name) + days + l2shift'
full=smf.glm('defective_units + ok ~ C(operator_id)'+base,data=v,family=sm.families.Binomial()).fit()
fs={'operator (vs line FE)':'defective_units + ok ~ C(line)'+base,
    'supplier':'defective_units + ok ~ C(operator_id)'+base.replace(' + C(supplier_name)',''),
    'line-level FE only (no operator)': 'defective_units + ok ~ C(line)'+base}
for k,f in fs.items():
    r=smf.glm(f,data=v,family=sm.families.Binomial()).fit()
    lr=2*(full.llf-r.llf); dfz=full.df_model-r.df_model
    print(f'{k:35s} LR={lr:9.2f} df={dfz:.0f} p={stats.chi2.sf(lr,dfz):.3g}')
print(v.groupby('line').machine_age_years.agg(['mean','std']).round(2).to_string())
print(v.groupby('operator_id').machine_age_years.mean().round(2).to_dict())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.formula.api as smf, numpy as np
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
f='defective_units + ok ~ mold_c + hum + cycle_time_s + machine_age_years + C(operator_id) + C(shift) + C(supplier_name) + days + l2shift'
g=smf.glm(f,data=v,family=smf.families.Binomial() if False else __import__('statsmodels.api').api.families.Binomial()).fit()
print('overall age coef',round(g.params.machine_age_years,4), round(g.pvalues.machine_age_years,4))
for l in ['L1','L2','L3','L4']:
    x=v[v.line==l]
    h=smf.glm(f,data=x,family=__import__('statsmodels.api').api.families.Binomial()).fit()
    print(l,'age coef',round(h.params.machine_age_years,4),'p',round(h.pvalues.machine_age_years,4))
v['ageb']=pd.cut(v.machine_age_years,[0,4,6,8,12,25])
print(v.groupby(['ageb','line'],observed=True).rate.agg(['mean','size']).round(4).unstack(1).to_string())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
ctl=' + mold_c + hum + cycle_time_s + C(operator_id) + C(shift) + C(supplier_name) + days + l2shift'
F=lambda s: smf.glm('defective_units + ok ~ '+s,data=v,family=sm.families.Binomial()).fit()
g0=F('machine_age_years'+ctl)
g1=F('machine_age_years:C(line)'+ctl)
g2=F('machine_age_years'+ctl+' + I(machine_age_years**2)')
g3=F('machine_age_years'+ctl)
lr=2*(g1.llf-g0.llf); print('age x line LR',round(lr,2),'df',g1.df_model-g0.df_model,'p',round(stats.chi2.sf(lr,g1.df_model-g0.df_model),4))
print('line-specific slopes', g1.params.filter(like='machine_age').round(4).to_dict())
print('quad p', round(g2.pvalues['I(machine_age_years ** 2)'],4))
print('no-op line-FE model age coef', round(F('machine_age_years + C(line)'+ctl.replace(' + C(operator_id)','')).params.machine_age_years,4))
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
F=lambda s: smf.glm('defective_units + ok ~ '+s,data=v,family=sm.families.Binomial()).fit()
base='mold_c + hum + cycle_time_s + machine_age_years + C(operator_id) + C(shift) + C(supplier_name) + days + l2shift'
g=F(base)
print('lin: age',round(g.params.machine_age_years,4),round(g.pvalues.machine_age_years,4))
for q in ['I(mold_c**2)','I(cycle_time_s**2)','I(hum**2)','I(machine_age_years**2)']:
    h=F(base+' + '+q); print('add',q,'age p',round(h.pvalues.machine_age_years,4),'q p',round(h.pvalues[q],4), 'llf gain', round(2*(h.llf-g.llf),1))
print(v.groupby('line').cycle_time_s.mean().round(2).to_dict(), v.groupby('line').mold_c.mean().round(2).to_dict())
print(v.groupby(pd.cut(v.days,[-1,3,7,14,21,40]),observed=True).rate.mean().round(4).to_dict())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
F=lambda s: smf.glm('defective_units + ok ~ '+s,data=v,family=sm.families.Binomial()).fit()
base='mold_c + hum + cycle_time_s + machine_age_years + C(operator_id) + C(shift) + C(supplier_name) + days + l2shift'
g=F(base)
print('lin: age',round(g.params.machine_age_years,4),round(g.pvalues.machine_age_years,4))
for q in ['I(mold_c**2)','I(cycle_time_s**2)','I(hum**2)','I(machine_age_years**2)']:
    h=F(base+' + '+q); print('add',q,'age p',round(h.pvalues.machine_age_years,4),'q p',round(h.pvalues.iloc[-1],4), 'llf gain', round(2*(h.llf-g.llf),1))
print(v.groupby('line').cycle_time_s.mean().round(2).to_dict(), v.groupby('line').mold_c.mean().round(2).to_dict())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import numpy as np
v=b[b.humidity_valid & b.mold_valid].copy()
print(v.humidity_pct.describe().round(2).to_dict())
bins=[0,5,10,15,20,25,30,35,40,45,50,55,60,65,75]
v['hb']=pd.cut(v.humidity_pct,bins)
print(v.groupby(['hb','supplier_name'],observed=True).rate.agg(['mean','size']).round(4).unstack(1).to_string())
print(v.groupby('line').humidity_pct.mean().round(2).to_dict(), v.groupby('shift' if False else 'supplier_name').humidity_pct.mean().round(2).to_dict())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
F=lambda s: smf.glm('defective_units + ok ~ '+s,data=v,family=sm.families.Binomial()).fit()
hq='hum + I(hum**2)'
ctl=' + mold_c + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + C(supplier_name) + days + l2shift'
full=F(hq+'*C(supplier_name)'+ctl.replace(' + C(supplier_name)',''))
print('full llf',round(full.llf,1))
for name,s in {'machine_age':'machine_age_years','ambient':'ambient_temp_c','shift':'C(shift)','operator':'C(operator_id)','cycle':'cycle_time_s','mold':'mold_c','humidity_all':'hum'}.items():
    pass
def drop(term):
    rhs=(hq+'*C(supplier_name)'+ctl.replace(' + C(supplier_name)',''))
    return F(rhs.replace(term,'') if term!='C(operator_id)' else rhs.replace(' + C(operator_id)',''))
for t in [' + machine_age_years',' + ambient_temp_c',' + C(shift)',' + cycle_time_s',' + mold_c',' + C(operator_id)']:
    r=drop(t); lr=2*(full.llf-r.llf); df=full.df_model-r.df_model
    print(f'{t:22s} LR {lr:9.2f} df {df:.0f} p {stats.chi2.sf(lr,df):.4g}')
print(full.params.round(4).filter(regex='hum|mold|cycle|machine|ambient|shift|l2|days').to_string())
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
F=lambda s: smf.glm('defective_units + ok ~ '+s,data=v,family=sm.families.Binomial()).fit()
H='cr(hum, df=5)*C(supplier_name)'
M='cr(mold_c, df=4)'
rest=' + cycle_time_s + machine_age_years + ambient_temp_c + C(operator_id) + C(shift) + days + l2shift'
full=F(H+' + '+M+rest)
print('llf',round(full.llf,1))
for t in ['machine_age_years','ambient_temp_c','C(shift)','cycle_time_s','C(operator_id)']:
    r=F(H+' + '+M+rest.replace(' + '+t,'') if t!='C(operator_id)' else H+' + '+M+rest.replace(' + C(operator_id)',''))
    lr=2*(full.llf-r.llf); df=full.df_model-r.df_model
    print(f'drop {t:20s} LR {lr:8.2f} df {df:.0f} p {stats.chi2.sf(lr,df):.4g}')
r=F(H+' + cr(mold_c,df=4)'.replace('cr(mold_c, df=4)','mold_c')+rest); lr=2*(full.llf-r.llf); print('mold linear vs spline LR',round(lr,2))
r=F(H.replace('cr(hum, df=5)*C(supplier_name)','hum*C(supplier_name)')+' + '+M+rest); lr=2*(full.llf-r.llf); print('hum spline vs linear*supplier LR',round(lr,2))
" 2>&1 | grep -v Warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -W ignore -c "
exec(open('clean.py').read())
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
v=b[b.humidity_valid & b.mold_valid].copy(); v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
H='cr(hum, df=5)*C(supplier_name)'
rest=' + mold_c + cycle_time_s + ambient_temp_c + C(operator_id) + C(shift) + days + l2shift'
g=smf.glm('defective_units + ok ~ '+H+rest,data=v,family=sm.families.Binomial()).fit()
p=g.predict(v); v['res']=(v.defective_units-p*v.units_produced)/np.sqrt(p*(1-p)*v.units_produced)
v['ageb']=pd.cut(v.machine_age_years,[0,3,4,5,6,7,8,10,12,14,16,18,22])
print(v.groupby(['line','ageb'],observed=True).res.agg(['mean','size']).round(2).unstack(0).to_string())
print(v.groupby('line').machine_age_years.describe().round(2).to_string())
" 2>&1 | grep -v -i warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && cat > model.py <<'EOF'
exec(open('/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad/clean.py').read())
import warnings; warnings.filterwarnings('ignore')
import statsmodels.api as sm, statsmodels.formula.api as smf, numpy as np
from scipy import stats
v=b[b.humidity_valid & b.mold_valid].copy()
v['hum']=v.humidity_pct; v['days']=v.days_since_clean; v['ok']=v.units_produced-v.defective_units
v['l2shift']=((v.line=='L2')&(v.production_date>='2025-06-15')).astype(int)
def fit(f,d=v):
    return smf.glm('defective_units + ok ~ '+f,data=d,family=sm.families.Binomial()).fit()
EOF
python3 -c "
exec(open('model.py').read())
rest=' + cycle_time_s + C(operator_id) + C(shift) + ambient_temp_c'
H='cr(hum, df=5)*C(supplier_name)'
base=fit(H+' + mold_c + days + l2shift'+rest)
for name,f in {'mold lin':'mold_c','mold spline':'cr(mold_c, df=4)','mold quad':'mold_c + I(mold_c**2)','days lin':'days','days spline':'cr(days, df=4)'}.items():
    pass
m_sp=fit(H+' + cr(mold_c, df=4) + days + l2shift'+rest); print('mold spline vs lin LR', round(2*(m_sp.llf-base.llf),2), 'df', m_sp.df_model-base.df_model)
d_sp=fit(H+' + mold_c + cr(days, df=4) + l2shift'+rest); print('days spline vs lin LR', round(2*(d_sp.llf-base.llf),2),'df', d_sp.df_model-base.df_model)
print('base params', base.params.filter(regex='mold|days|l2|cycle|Night|ambient').round(4).to_dict())
print('humidity coefs', base.params.filter(like='hum').round(4).to_dict())
" 2>&1 | grep -vi warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && cat > answers.py <<'EOF'
exec(open('model.py').read())
rest=' + cycle_time_s + C(operator_id) + C(shift) + ambient_temp_c'
F=' + mold_c + days + l2shift'
m=fit('cr(hum, df=5)*C(supplier_name)'+F+rest)
def pred(d):
    return m.predict(d)*d.units_produced   # expected defective units
# C1: single supplier for all batches
rows=[]
for s in ['Alpha','Beta','Gamma']:
    d=v.copy(); d['supplier_name']=s
    rows.append((s, pred(d).sum()/v.units_produced.sum()))
print('C1 counterfactual overall rate:', [(s,round(r,6)) for s,r in rows])
print('C1 factual predicted overall', round(pred(v).sum()/v.units_produced.sum(),6), 'actual valid', round(v.defective_units.sum()/v.units_produced.sum(),6))
# C2: Alpha humidity optimum
grid=np.round(np.arange(v.hum.min(), v.hum.max()+1e-9, 0.05),2)
ref=v[v.supplier_name=='Alpha'].iloc[[0]].copy()
ps=[]
for h in grid:
    d=pd.concat([ref]*1); d['hum']=h
    ps.append(float(m.predict(d).iloc[0]))
ps=np.array(ps); i=ps.argmin()
print('C2 Alpha grid range',grid.min(),grid.max(),'argmin hum',grid[i],'rate',round(ps[i],5))
EOF
python3 answers.py 2>&1 | grep -vi warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && cat > answers2.py <<'EOF'
exec(open('answers.py').read().split('# C1')[0])
# curve for Alpha
ref=v[v.supplier_name=='Alpha'].iloc[[0]].copy()
for h in [12,15,20,25,28,29,29.2,30,32,35,40,45,50,55,60,70]:
    d=ref.copy(); d['hum']=h; print('spline Alpha',h, round(float(m.predict(d).iloc[0]),5))
# sensitivity: quadratic humidity x supplier
mq=fit('(hum + I(hum**2))*C(supplier_name)'+F+rest)
best=min(((float(mq.predict(ref.assign(hum=h)).iloc[0]),h) for h in np.arange(12.1,72.3,0.05)))
print('quadratic spec argmin', round(best[1],2), round(best[0],5))
# C3: 14-day cleaning rule
cl=mt[mt.event=='mold_cleaning'].copy()
new_days=[]
forced=[]
for line in ['L1','L2','L3','L4']:
    last_prev=cl[cl.line==line].date.tolist()
    days_range=pd.date_range('2025-01-06','2025-09-30')
    # actual cleanings within the period plus pre-period cleaning as last
    last=max([d for d in last_prev if d<=days_range[0]], default=None)
    cleanings=set(d for d in last_prev)
    cur=last
    for day in days_range:
        if day in cleanings: cur=day
        if cur is None or (day-cur).days>=14:
            cur=day; forced.append((line,day.date()))
            cleanings.add(day)
        # record
    # compute per batch later
    ser=pd.Series(sorted(cleanings))
    sub=v[v.line==line]
    for idx,row in sub.iterrows():
        c=ser[ser<=row.production_date].max()
        new_days.append((idx,(row.production_date-c).days))
print('forced cleanings added',len(forced))
print(pd.Series([l for l,_ in forced]).value_counts().to_dict())
newd=pd.Series(dict(new_days))
w=v.copy(); w['days_new']=newd.reindex(w.index)
print('days_new max', w.days_new.max(), 'days_new mean', round(w.days_new.mean(),2),'orig mean',round(w.days.mean(),2))
w2=w.copy(); w2['days']=w2.days_new
base_pred=pred(w).sum()/w.units_produced.sum()
cf_pred=pred(w2).sum()/w.units_produced.sum()
print('C3 base pred', round(base_pred,6), 'cf pred', round(cf_pred,6), 'cf/base ratio', round(cf_pred/base_pred,4))
print('C3 cf with actual rate scaling', round(w.defective_units.sum()/w.units_produced.sum()*cf_pred/base_pred,6))
EOF
python3 answers2.py 2>&1 | grep -vi warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && cat > full.py <<'EOF'
exec(open('answers2.py').read().split('# curve for Alpha')[0])
# full 3000-batch frame with imputation
A=b.copy(); A['hum']=A.humidity_pct; A['days']=A.days_since_clean; A['ok']=A.units_produced-A.defective_units
A['l2shift']=((A.line=='L2')&(A.production_date>='2025-06-15')).astype(int)
# mold imputation from ambient + line (fit on valid mold)
mm=smf.ols('mold_c ~ ambient_temp_c + C(line)',data=A[A.mold_valid]).fit()
miss=~A.mold_valid
A.loc[miss,'mold_c']=mm.predict(A[miss])
A['hum_missing']=~A.humidity_valid
def pred_full(df, days_col='days'):
    out=np.zeros(len(df))
    d0=df.copy(); d0['days']=df[days_col]
    ok=~df.hum_missing.values
    p=m.predict(d0[ok]).values
    out[ok]=p*d0[ok].units_produced.values
    # humidity missing: average over the observed humidities of the same supplier
    for i,(idx,row) in enumerate(d0[~ok].iterrows()):
        pool=v[v.supplier_name==row.supplier_name].hum.values
        dd=pd.DataFrame({'hum':pool,'supplier_name':row.supplier_name,'mold_c':row.mold_c,'days':row.days,'l2shift':row.l2shift,'cycle_time_s':row.cycle_time_s,'operator_id':row.operator_id,'shift':row['shift'],'ambient_temp_c':row.ambient_temp_c})
        out[np.where(~ok)[0][i]]=m.predict(dd).mean()*row.units_produced
    return out
N=A.units_produced.sum()
print('all-batch actual rate', round(A.defective_units.sum()/N,6))
base=pred_full(A)
print('all-batch predicted base rate', round(base.sum()/N,6))
EOF
python3 full.py 2>&1 | grep -vi warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && cat > final_c.py <<'EOF'
exec(open('full.py').read())
# C1 on full frame
for s in ['Alpha','Beta','Gamma']:
    B=A.copy(); B['supplier_name']=s
    print('C1 full', s, round(pred_full(B).sum()/N,6))
# C3: every-14-days rule applied to all batches
cl=mt[mt.event=='mold_cleaning']
days_range=pd.date_range('2025-01-06','2025-09-30')
newd={}
for line in ['L1','L2','L3','L4']:
    cleanings=set(pd.to_datetime(cl[cl.line==line].date))
    pre=[d for d in cleanings if d<days_range[0]]
    cur=max(pre)
    for day in days_range:
        if day in cleanings: cur=day
        if (day-cur).days>=14:
            cur=day; cleanings.add(day)
    ser=pd.Series(sorted(cleanings))
    sub=A[A.line==line]
    for idx,row in sub.iterrows():
        c=ser[ser<=row.production_date].max()
        newd[idx]=(row.production_date-c).days
A['days_new']=pd.Series(newd)
print('days_new max', A.days_new.max(), 'mean', round(A.days_new.mean(),3), 'orig mean', round(A.days.mean(),3))
p0=pred_full(A)/N; p1=pred_full(A,'days_new')/N
print('C3 full base', round(p0.sum(),6), 'cf', round(p1.sum(),6))
EOF
python3 final_c.py 2>&1 | grep -vi warn

S=/tmp/claude-0/-tmp-edabench-claude-zdn7pe95/7048de4e-dead-54b1-94eb-1442c83575c4/scratchpad && cd $S && python3 -c "
exec(open('clean.py').read())
print('A1 unique batches', b.batch_id.nunique(), len(b))
print('A2 invalid humidity (unique)', (~b.humidity_valid).sum(), 'of which NaN', b.humidity_pct.isna().sum(), 'negative', (b.humidity_pct<0).sum())
print('A3', round(b.defective_units.sum()/b.units_produced.sum(),6))
print('A4 median mold C', round(b.mold_c.median(),3), 'n', b.mold_c.notna().sum())
" 2>&1 | grep -v Warn
