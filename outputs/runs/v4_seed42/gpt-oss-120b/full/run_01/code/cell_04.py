# Parse dates robustly
import dateutil.parser as dp

def parse_date(x):
    try:
        return pd.to_datetime(x, infer_datetime_format=True, errors='coerce')
    except Exception:
        return pd.NaT

batches['prod_date_parsed'] = batches['production_date'].apply(parse_date)
print(batches['production_date'].head(10))
print(batches['prod_date_parsed'].head(10))
print('NaT count', batches['prod_date_parsed'].isna().sum())

