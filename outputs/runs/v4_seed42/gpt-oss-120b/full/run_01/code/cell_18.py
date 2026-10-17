import numpy as np, pandas as pd
corr = batches[['rework_cost_eur','defective_units','units_produced']].corr()
print(corr)

