import pandas as pd, numpy as np
b=pd.read_csv('batches.csv')
s=b.production_date
iso=pd.to_datetime(s.where(s.str.contains('-')),format='%Y-%m-%d')
mdy=pd.to_datetime(s.where(s.str.contains('/')),format='%m/%d/%Y',errors='coerce')
dmy=pd.to_datetime(s.where(s.str.contains('/')),format='%d/%m/%Y',errors='coerce')
known=iso.fillna(mdy.where(dmy.isna())).fillna(dmy.where(mdy.isna()))
kn=known.dropna()
def ref_at(i):
    w=kn[(kn.index>=i-10)&(kn.index<=i+10)]
    return w.sort_values().iloc[len(w)//2]
ref=pd.Series([ref_at(i) for i in b.index],index=b.index)
amb=known.isna()
pick=[m if abs((m-r).days)<=abs((d-r).days) else d for m,d,r in zip(mdy,dmy,ref)]
b['date']=known.where(~amb,pd.Series(pick,index=b.index))
b['dist']=(b.date-ref).abs()
b=b.sort_values('dist').drop_duplicates('batch_id').sort_index().drop(columns='dist').reset_index(drop=True)
assert len(b)==3000
b['shift']=b['shift'].str.strip().str.upper().str[0].map({'D':'Day','N':'Night'})
b['supplier_code']=b.supplier_code.str.strip().str.upper()
b['hum']=b.humidity_pct.where(b.humidity_pct>=0)
b['mt']=b.mold_temp.where(b.mold_temp>0)
b['F']=b.mt>300
b.loc[b.F,'mt']=(b.loc[b.F,'mt']-32)*5/9
b['rate']=b.defective_units/b.units_produced
s=pd.read_csv('suppliers.csv'); b=b.merge(s,on='supplier_code',how='left')
b.to_pickle('work/b.pkl')
