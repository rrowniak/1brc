# Results of different experiments

## My machine

Memory: 16 GB
CPU: Intel(R) Core(TM) i7-6820HQ CPU @ 2.70GHz 

Set perf event paranoid to -1:
```
sudo sysctl kernel.perf_event_paranoid=-1
```

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

## Zig simple optimizations
- reserve capacity for hash map
- enlarge reading buffer to 1MB
- still no `perf` in use

(ReleaseFast)
```
real    1m19,206s
user    1m13,195s
sys     0m2,407s
```

## Zig optimizations round 2
- more efficient hash map usage (removed double lookup)

```
real    1m1,822s
user    0m56,310s
sys     0m2,047s
```

## Zig mmap
- mmap instead of standard file reading
- mmap didn't bring performance boost

```
real    1m13,412s
user    1m0,376s
sys     0m2,690s
```

## Zig optimizations round 3
- mmap reverted - no performance boost, should be investigated further
- fast float parser written
- slow takeDelimiterExclusive and splitScalar replaced by simd-based implementation 
- `likely` hints added (gain about 5 seconds)

```
real    0m38,478s
user    0m27,706s
sys     0m3,029s

```

## Zig optimizations hash map
- buffer 1 MB -> 4 MB: the most efficient choice
- StringHashMap -> HashMapUnmanaged
- further optimizations of the std.mem.eql (branch hints)

```
real    0m28,663s
user    0m26,023s
sys     0m1,969s

```

## Zig optimization over simd vector length
- VEC_L changed from 64 to 32

```
real    0m25,378s
user    0m22,565s
sys     0m2,016s
```
