import pandas as pd, numpy as np
batches = pd.read_csv('batches.csv')
# compute correlation between rework_cost_eur and defective_units
corr = batches[['rework_cost_eur','defective_units']].corr()
print(corr)

