# compute defect_rate per batch
batches['defect_rate'] = batches['defective_units'] / batches['units_produced']
# drop rows with missing units
batches_clean = batches.dropna(subset=['units_produced','defective_units'])
# Ensure numeric
batches_clean = batches_clean[(batches_clean['units_produced']>0)]

# For each line, aggregate by production_date (date only)
batches_clean['date'] = batches_clean['production_date'].dt.date
line_dates = batches_clean.groupby(['line','date'])['defect_rate'].mean().reset_index()

# Function to detect abrupt shift: compute overall mean before and after each candidate date, require at least 30 days data before and after, and difference > 0.02 (2 percentage points) sustained.
import numpy as np, pandas as pd

def find_shift(df_line):
    dates = sorted(df_line['date'].unique())
    rates = df_line.set_index('date')['defect_rate']
    # fill missing dates with nan
    full = pd.Series(index=pd.date_range(dates[0], dates[-1]), dtype=float)
    full.loc[rates.index] = rates.values
    # compute rolling means? We'll brute.
    for cut in dates[30:-30]:
        before = full[:cut]
        after = full[cut:]
        if before.notna().sum()<20 or after.notna().sum()<20:
            continue
        mean_before = before.mean()
        mean_after = after.mean()
        if abs(mean_after-mean_before)>0.02:
            # check that after remains relatively stable (std low)
            if after.std()<0.03:
                return cut
    return None

shifts = {}
for line, grp in line_dates.groupby('line'):
    d = find_shift(grp)
    if d:
        shifts[line]=d
print('shifts found', shifts)

