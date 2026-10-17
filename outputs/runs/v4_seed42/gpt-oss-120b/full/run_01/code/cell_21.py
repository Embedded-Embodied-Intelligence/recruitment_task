op_sig = model.pvalues.filter(like='C(operator_id)').lt(0.05).any()
sh_sig = model.pvalues.filter(like='C(shift)').lt(0.05).any()
print('operator any sig', op_sig)
print('shift any sig', sh_sig)

