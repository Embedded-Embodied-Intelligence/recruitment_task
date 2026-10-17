batches['prod_date_parsed'] = pd.to_datetime(batches['production_date'], dayfirst=True, errors='coerce')
print(batches['prod_date_parsed'].head(10))
print('NaT count', batches['prod_date_parsed'].isna().sum())
