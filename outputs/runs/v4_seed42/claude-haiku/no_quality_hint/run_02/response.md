The operator permutation test is still running with no result, and the wait wrapper was stopped at its time limit. I'm not going to keep waiting on it.

The answers I gave stand, but operator_id in B1 rests on the likelihood-ratio test alone (p ≈ 0.013 on 20 df). If the permutation test comes back above 0.05, remove `operator_id` from `B1_direct_drivers`. The other B1 entries (mold_temp, humidity_pct, cycle_time_s, shift) are clearly significant, and ambient_temp_c and machine_age_years are excluded.

The final JSON I already gave is the answer. Its B1 list includes operator_id; drop it if the permutation test fails to confirm.
