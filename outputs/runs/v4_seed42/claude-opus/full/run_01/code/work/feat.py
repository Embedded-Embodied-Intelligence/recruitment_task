import pandas as pd, numpy as np
b=pd.read_pickle('work/b.pkl')
m=pd.read_csv('maintenance.csv',parse_dates=['date'])
cl=m[m.event=='mold_cleaning']
def dsc(r):
    c=cl[(cl.line==r.line)&(cl.date<=r.date)].date
    return (r.date-c.max()).days
b['dsc']=b.apply(dsc,axis=1)
b['cdev']=b.cycle_time_s-b.recipe_cycle_time_s
b['L1post']=((b.line=='L1')&(b.date>='2025-04-14')).astype(int)
b['ok']=b.units_produced-b.defective_units
b.to_pickle('work/f.pkl')
