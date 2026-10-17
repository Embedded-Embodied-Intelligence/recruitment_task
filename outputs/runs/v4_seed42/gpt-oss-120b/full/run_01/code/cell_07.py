def try_parse(series):
    # try multiple formats
    fmt1 = pd.to_datetime(series, format='%d/%m/%Y', errors='coerce')
    fmt2 = pd.to_datetime(series, format='%m/%d/%Y', errors='coerce')
    fmt3 = pd.to_datetime(series, errors='coerce')
    # combine: if fmt1 not NaT use it else fmt2 else fmt3
    combined = fmt1.copy()
    mask = combined.isna()
    combined[mask] = fmt2[mask]
    mask = combined.isna()
    combined[mask] = fmt3[mask]
    return combined

batches['prod_date'] = try_parse(batches['production_date'])
print('parsed count', batches['prod_date'].notna().sum())
print('min', batches['prod_date'].min(), 'max', batches['prod_date'].max())
print(batches['prod_date'].value_counts().head())

