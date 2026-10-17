op_sig = model.pvalues[model.pvalues.index.str.contains('C(operator_id)')].lt(0.05).any()
sh_sig = model.pvalues[model.pvalues.index.str.contains('C(shift)')].lt(0.05).any()
print('operator any significant?', op_sig)
print('shift any significant?', sh_sig)

