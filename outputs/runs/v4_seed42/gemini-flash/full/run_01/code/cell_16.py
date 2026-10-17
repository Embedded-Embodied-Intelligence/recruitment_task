# Let's inspect the slash dates
slash_dates = batches_unique[batches_unique['production_date'].str.contains('/')]['production_date']
parts = slash_dates.str.split('/', expand=True)
print("Part 0 range:", parts[0].astype(int).min(), parts[0].astype(int).max())
print("Part 1 range:", parts[1].astype(int).min(), parts[1].astype(int).max())
print("Part 2 range:", parts[2].unique())

