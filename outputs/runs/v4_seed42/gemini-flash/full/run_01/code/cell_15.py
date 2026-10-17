# Check date formats
dates_raw = batches_unique['production_date']
print("Slash dates count:", dates_raw.str.contains('/').sum())
print("Hyphen dates count:", dates_raw.str.contains('-').sum())
print("Sample slash dates:", dates_raw[dates_raw.str.contains('/')].head(10).tolist())
print("Sample hyphen dates:", dates_raw[dates_raw.str.contains('-')].head(10).tolist())

