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
d.loc[(d.line=='L2')&(d.humidity_pct==50.2)&(d.date>='2025-03-03')&(d.date<='2025-04-13'),'hum']=np.nan
mt=pd.read_csv('maintenance.csv',parse_dates=['date'])
cl=mt[mt.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date
    return (r.date-c.max()).days if len(c) else np.nan
d['dsc']=d.apply(dsc,axis=1)
d['cyc_dev']=d.cycle_time_s-d.recipe_cycle_time_s
