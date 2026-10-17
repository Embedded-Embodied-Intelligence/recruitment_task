operator_ps = pvals[pvals.index.str.contains('C(operator_id)')]
shift_ps = pvals[pvals.index.str.contains('C(shift)')]
print('operator significant any?', (operator_ps < 0.05).any())
print('shift significant any?', (shift_ps < 0.05).any())

