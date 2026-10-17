print(batches_unique[batches_unique['humidity_pct'] <= 0]['humidity_pct'].value_counts())
print("Missing:", batches_unique['humidity_pct'].isna().sum())
print("Total invalid or missing:", batches_unique['humidity_pct'].isna().sum() + (batches_unique['humidity_pct'] < 0).sum())
print("Are there any 0.0?", (batches_unique['humidity_pct'] == 0).sum())

