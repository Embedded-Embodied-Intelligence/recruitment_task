# recompute line_dates as before but with defect_rate per batch (already computed) and aggregate daily mean per line.
batches['defect_rate'] = batches['defective_units'] / batches['units_produced']
# drop rows where units_produced zero or NaN
valid = batches['units_produced'].notna() & (batches['units_produced']>0)
batches_valid = batches[valid].copy()
batches_valid['date'] = batches_valid['production_date'].dt.date
line_dates = batches_valid.groupby(['line','date'])['defect_rate'].mean().reset_index()

shifts = {}
for line, grp in line_dates.groupby('line'):
    # sort by date
    grp = grp.sort_values('date')
    dates = pd.to_datetime(grp['date'])
    rates = pd.Series(grp['defect_rate'].values, index=dates)
    # ensure continuous index for detection
    full = rates.reindex(pd.date_range(dates.min(), dates.max()))
    # look for split points where both sides have at least 30 days of non-NA
    for cut in full.index[30:-30]:
        before = full[:cut]
        after = full[cut:]
        if before.notna().sum() < 20 or after.notna().sum() < 20:
            continue
        mean_before = before.mean()
        mean_after = after.mean()
        if abs(mean_after-mean_before) > 0.02:  # 2%
            # check stability after: std of after low
            if after.std() < 0.03:
                shifts[line] = cut.date()
                break
print(shifts)

