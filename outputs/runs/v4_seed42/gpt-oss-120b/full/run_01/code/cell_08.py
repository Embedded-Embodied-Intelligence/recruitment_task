# Unique batch count
a1 = batches['batch_id'].nunique()
print('Unique batches:', a1)
# Check humidity column
if 'humidity_pct' not in batches.columns:
    print('humidity column missing')
else:
    # Count missing or invalid: assume NaN or <=0 or >100 maybe
    humidity = batches['humidity_pct']
    missing = humidity.isna().sum()
    invalid = ((humidity <= 0) | (humidity > 100)).sum()
    print('missing', missing, 'invalid', invalid)
    a2 = missing + invalid
    print('A2 count:', a2)

