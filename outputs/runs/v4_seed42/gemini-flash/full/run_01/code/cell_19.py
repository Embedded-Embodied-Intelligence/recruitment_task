for line in ['L1', 'L2', 'L3', 'L4']:
    sub = batches_unique[batches_unique['line'] == line]['production_date']
    print(f"Line {line}: total {len(sub)}")
    print(f"  hyphen count: {sub.str.contains('-').sum()}")
    print(f"  slash count: {sub.str.contains('/').sum()}")
    # check first 5 slash dates
    if sub.str.contains('/').sum() > 0:
        slash = sub[sub.str.contains('/')]
        parts = slash.str.split('/', expand=True)
        print(f"  slash part 0 range: {parts[0].astype(int).min()} - {parts[0].astype(int).max()}")
        print(f"  slash part 1 range: {parts[1].astype(int).min()} - {parts[1].astype(int).max()}")

