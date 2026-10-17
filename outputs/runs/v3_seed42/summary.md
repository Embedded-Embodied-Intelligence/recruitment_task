# Benchmark results

23 scored runs. Scores are in [0, 1]; sd is the run-to-run standard deviation.

## Total score

| model | variant | count | mean | std | min | max | equal_weights_mean | format_ok | tool_calls_mean | turn_limit_runs |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 5 | 0.955 | 0.024 | 0.933 | 0.987 | 0.966 | 1.000 | 33.400 | 0 |
| claude-haiku | no_quality_hint | 5 | 0.969 | 0.036 | 0.911 | 0.994 | 0.976 | 1.000 | 34.400 | 0 |
| claude-opus | full | 3 | 0.994 | 0.002 | 0.992 | 0.996 | 0.994 | 1.000 | 16.000 | 0 |
| claude-sonnet | full | 5 | 0.982 | 0.013 | 0.961 | 0.992 | 0.986 | 1.000 | 14.600 | 0 |
| claude-sonnet | no_quality_hint | 5 | 0.987 | 0.009 | 0.977 | 0.996 | 0.990 | 1.000 | 14.800 | 0 |

## Mean score per question

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 1.00 | 1.00 | 1.00 | 1.00 | 0.88 | 1.00 | 0.98 | 1.00 | 0.85 | 0.96 |
| claude-haiku | no_quality_hint | 1.00 | 1.00 | 1.00 | 1.00 | 0.98 | 1.00 | 0.99 | 1.00 | 0.84 | 0.96 |
| claude-opus | full | 1.00 | 0.99 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 0.99 | 0.97 |
| claude-sonnet | full | 1.00 | 1.00 | 1.00 | 1.00 | 0.97 | 1.00 | 0.99 | 1.00 | 0.94 | 0.96 |
| claude-sonnet | no_quality_hint | 1.00 | 1.00 | 1.00 | 1.00 | 0.98 | 1.00 | 0.99 | 1.00 | 0.97 | 0.96 |

Run-to-run sd per question:

| model | variant | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.16 | 0.00 | 0.02 | 0.00 | 0.18 | 0.03 |
| claude-haiku | no_quality_hint | 0.00 | 0.00 | 0.00 | 0.00 | 0.05 | 0.00 | 0.02 | 0.00 | 0.24 | 0.03 |
| claude-opus | full | 0.00 | 0.02 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.02 | 0.00 |
| claude-sonnet | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.06 | 0.00 | 0.01 | 0.00 | 0.05 | 0.02 |
| claude-sonnet | no_quality_hint | 0.00 | 0.00 | 0.00 | 0.00 | 0.05 | 0.00 | 0.01 | 0.00 | 0.03 | 0.02 |

## How often the trap answer was given

Share of runs whose answer was closer to the naive (trap) answer than to the truth.

| model | variant | A1 | A2 | A3 | A4 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|
| claude-haiku | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-haiku | no_quality_hint | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-opus | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-sonnet | full | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| claude-sonnet | no_quality_hint | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |

## Wrong items in set answers

`+x` = listed but wrong, `-x` = missed; counts over runs.

- claude-haiku / full / B1: `+operator_id` x2, `+machine_age_years` x1, `+mold_temp_c` x1, `-mold_temp` x1, `+ambient_temp_c` x1
- claude-haiku / no_quality_hint / B1: `+operator_id` x1
- claude-sonnet / full / B1: `-cycle_time_s` x1
- claude-sonnet / no_quality_hint / B1: `+ambient_temp_c` x1

## Prompt ablation: full minus no_quality_hint

Positive = the data-quality hint helped.

| model | total | A1 | A2 | A3 | A4 | B1 | B2 | B3 | C1 | C2 | C3 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku | -0.014 | 0.000 | 0.000 | 0.000 | 0.000 | -0.102 | 0.000 | -0.007 | 0.000 | 0.010 | -0.003 |
| claude-sonnet | -0.005 | 0.000 | 0.000 | 0.000 | 0.000 | -0.006 | 0.000 | 0.000 | 0.000 | -0.030 | 0.001 |

## Robustness of the ranking to the weights

The ranking of models by mean total is the same with equal question weights (variant `full`).
