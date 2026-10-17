import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
from scipy import stats
b=pd.read_pickle('work/f.pkl')
b['L2post']=((b.line=='L2')&(b.date>='2025-06-16')).astype(int)
b['L3post']=((b.line=='L3')&(b.date>='2025-07-21')).astype(int)
b['m']=b.mt-6.17*b.L1post
b.to_pickle('work/g.pkl')
d=b.dropna(subset=['m','hum']).copy()
terms={'mold_temp':['m','I(m**2)'],'humidity_pct':['hum*C(supplier_name)','I(hum**2)*C(supplier_name)'],'cycle_time_s':['cdev','I(cdev**2)'],
'machine_age_years':['machine_age_years'],'ambient_temp_c':['ambient_temp_c'],'operator_id':['C(operator_id)'],'shift':['C(shift)']}
base=['C(supplier_name)','dsc','L2post','L3post','C(line)']
def fit(ts):
    return smf.glm('rate~'+'+'.join(ts),d,family=sm.families.Binomial(),var_weights=d.units_produced).fit(scale='X2')
full=fit(base+sum(terms.values(),[]))
print('dispersion',full.scale)
for k,v in terms.items():
    red=fit(base+sum([t for kk,t in terms.items() if kk!=k],[]))
    df=full.df_model-red.df_model
    F=(red.deviance-full.deviance)/df/full.scale
    print(k,df,round(F,2),stats.f.sf(F,df,full.df_resid))
print(full.summary().tables[1])
