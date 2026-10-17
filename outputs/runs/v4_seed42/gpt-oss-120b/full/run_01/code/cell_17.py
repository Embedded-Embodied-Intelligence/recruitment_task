humidity = batches['humidity_pct']
missing = humidity.isna().sum()
invalid = ((humidity <= 0) | (humidity > 100)).sum()
missing, invalid
