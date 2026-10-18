import pandas as pd, numpy as np
d=pd.read_csv('batches.csv',dtype=str)
for c in d.columns: d[c]=d[c].str.strip()
d=d.drop_duplicates()
d['supplier_code']=d.supplier_code.str.upper()
d['shift']=d['shift'].str.lower().str[0].map({'d':'Day','n':'Night'})
def pdt(r):
    s=r.production_date
    if r.line=='L1': return pd.to_datetime(s,format='%m/%d/%Y')
    if r.line=='L4': return pd.to_datetime(s,format='%d/%m/%Y')
    return pd.to_datetime(s,format='%Y-%m-%d')
d['date']=d.apply(pdt,axis=1)
for c in ['machine_age_years','ambient_temp_c','mold_temp','humidity_pct','cycle_time_s','units_produced','defective_units','qc_inspection_min','rework_cost_eur']:
    d[c]=pd.to_numeric(d[c])
d=d.drop_duplicates()
s=pd.read_csv('suppliers.csv'); d=d.merge(s,on='supplier_code',how='left')
d['rate']=d.defective_units/d.units_produced
d['mt']=d.mold_temp.where(d.mold_temp>0)
d.loc[d.line=='L3','mt']=(d.mt-32)*5/9
d['hum']=d.humidity_pct.where(d.humidity_pct>=0)
d.loc[(d.line=='L2')&(d.date>='2025-03-03')&(d.date<='2025-04-13')&(d.humidity_pct==50.2),'hum']=np.nan
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
mc=m[m.event=='mold_cleaning']
def dsc(r):
    x=mc[(mc.line==r.line)&(mc.date<=r.date)].date
    return (r.date-x.max()).days if len(x) else np.nan
d['dsc']=d.apply(dsc,axis=1)
d['opn']=d.operator_id
