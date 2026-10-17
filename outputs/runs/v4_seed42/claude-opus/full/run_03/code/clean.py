import pandas as pd, numpy as np
d=pd.read_csv('batches.csv').drop_duplicates().reset_index(drop=True)
def pdate(r):
    s=r.production_date
    if '-' in s: return pd.to_datetime(s)
    return pd.to_datetime(s, format='%m/%d/%Y' if r.line=='L1' else '%d/%m/%Y')
d['date']=d.apply(pdate,axis=1)
d['shift']=d['shift'].str.strip().str.lower().map({'day':'Day','d':'Day','night':'Night','n':'Night'})
d['supplier_code']=d.supplier_code.str.strip().str.upper()
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.mt>350,'mt']=(d.mt-32)*5/9
d['rate']=d.defective_units/d.units_produced
s=pd.read_csv('suppliers.csv'); d=d.merge(s,on='supplier_code',how='left')
mn=pd.read_csv('maintenance.csv',parse_dates=['date'])
cl=mn[mn.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date.max()
    return (r.date-c).days
d['dsc']=d.apply(dsc,axis=1)
d['post']=((d.line=='L1')&(d.date>='2025-04-14')).astype(int)
d['mt_c']=d.mt-6.4*d.post
d['ct_dev']=d.cycle_time_s-d.recipe_cycle_time_s
d['ok']=d.units_produced-d.defective_units
