def parse_date(row):
    line = row['line']
    d_str = row['production_date']
    if line == 'L1':
        return pd.to_datetime(d_str, format='%m/%d/%Y')
    elif line in ['L2', 'L3']:
        return pd.to_datetime(d_str, format='%Y-%m-%d')
    elif line == 'L4':
        return pd.to_datetime(d_str, format='%d/%m/%Y')
    else:
        raise ValueError(f"Unknown line {line}")

batches_unique['parsed_date'] = batches_unique.apply(parse_date, axis=1)
print("Parsed date min:", batches_unique['parsed_date'].min())
print("Parsed date max:", batches_unique['parsed_date'].max())
print("Any nulls in parsed_date?", batches_unique['parsed_date'].isna().sum())

