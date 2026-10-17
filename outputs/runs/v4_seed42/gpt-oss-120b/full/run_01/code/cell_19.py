import pandas as pd, numpy as np
batches = pd.read_csv('batches.csv')
A1 = batches['batch_id'].nunique()
# humidity invalid as non-numeric or missing
batches['humidity_num'] = pd.to_numeric(batches['humidity_pct'], errors='coerce')
A2 = batches['humidity_num'].isna().sum()
A3 = batches['defective_units'].sum() / batches['units_produced'].sum()
# mold temp median numeric
batches['mold_temp_num'] = pd.to_numeric(batches['mold_temp'], errors='coerce')
A4 = batches['mold_temp_num'].median()
print(A1, A2, A3, A4)

