# compute defect_rate per batch
batches['defect_rate'] = batches['defective_units'] / batches['units_produced']
# aggregate by line and date (prod_date)
agg = batches.groupby(['line','prod_date']).agg({'defect_rate':'mean','units_produced':'sum'}).reset_index()
# sort
agg = agg.sort_values(['line','prod_date'])
# compute rolling mean maybe 7 days
agg['rolling'] = agg.groupby('line')['defect_rate'].transform(lambda x: x.rolling(window=7, min_periods=1).mean())
# find large jumps: difference between successive days > 0.05
agg['diff'] = agg.groupby('line')['rolling'].diff().abs()
# find max diff per line
maxdiff = agg.groupby('line')['diff'].max().reset_index()
print(maxdiff)

