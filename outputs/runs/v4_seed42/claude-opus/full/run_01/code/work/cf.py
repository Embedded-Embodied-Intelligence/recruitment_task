import pandas as pd, numpy as np, statsmodels.formula.api as smf, statsmodels.api as sm
b=pd.read_pickle('work/g.pkl')
# impute humidity / mold temp for counterfactual prediction
print('hum corr same day across batches:', b.groupby('date').hum.transform('std').mean(), b.hum.std())
b['hum_i']=b.hum.fillna(b.groupby('date').hum.transform('mean')).fillna(b.hum.mean())
b['m_i']=b.m.fillna(b.groupby(['line','date']).m.transform('mean')).fillna(b.groupby('line').m.transform('mean'))
d=b.dropna(subset=['m','hum']).copy()
d['y']=np.log((d.defective_units+.5)/(d.ok+.5))
v=1/(d.defective_units+.5)+1/(d.ok+.5); d['w']=1/(v+0.054)
f='y~C(supplier_name)*(hum+I(hum**2))+m+cdev+dsc+L2post+L3post+C(shift)+C(line)'
r=smf.wls(f,d,weights=d.w).fit()
g=smf.glm(f.replace('y~','rate~'),d,family=sm.families.Binomial(),var_weights=d.units_produced).fit()
X=b.assign(hum=b.hum_i,m=b.m_i)
for mod,nm in [(r,'wls'),(g,'glm')]:
    eta0=mod.predict(X,which='linear') if nm=='glm' else mod.predict(X)
    lo=np.log(b.rate/(1-b.rate))  # observed logit (rates never 0)
    for keep in [True,False]:
        out={}
        for s in ['Alpha','Beta','Gamma']:
            Z=X.assign(supplier_name=s, cdev=X.cdev if keep else 0)
            Z0=X.assign(cdev=X.cdev if keep else 0)
            e1=mod.predict(Z,which='linear') if nm=='glm' else mod.predict(Z)
            e0=mod.predict(Z0,which='linear') if nm=='glm' else mod.predict(Z0)
            p=1/(1+np.exp(-(lo+e1-eta0)))
            out[s]=round((p*b.units_produced).sum()/b.units_produced.sum(),5)
        print(nm,'keep cdev' if keep else 'cdev=0',out)
    # C2
    hs=np.linspace(b.hum.min(),b.hum.max(),2001)
    pa=mod.params
    a=pa['hum']; q=pa['I(hum ** 2)']; print(nm,'alpha opt hum',-a/2/q)
    # C3
    bd=mod.params['dsc']; dn=b.dsc%14
    p=1/(1+np.exp(-(lo+bd*(dn-b.dsc))))
    print(nm,'C3',(p*b.units_produced).sum()/b.units_produced.sum(), 'beta',bd)
print(b.hum.min(),b.hum.max())
