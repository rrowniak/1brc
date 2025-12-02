# Results of different experiments

## My machine

Memory: 16 GB
CPU: Intel(R) Core(TM) i7-6820HQ CPU @ 2.70GHz 

## The provided Java naive example

Repo: https://github.com/gunnarmorling/1brc 

```
$ time ./calculate_average_baseline.sh
...
real    4m4,879s
user    3m59,173s
sys     0m7,760s
```

## Zig naive implementation - starting point
```
$ time zig build -Doptimize=ReleaseFast run
 
real    1m34,617s
user    1m20,432s
sys     0m13,822s
```

With symbols visible in `perf`:
```
$ time zig build -Doptimize=ReleaseSafe run

real    2m8,279s
user    1m54,134s
sys     0m13,933s
```
