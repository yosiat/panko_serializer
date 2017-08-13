## Initial state
```
Native_Posts_2300             57 ip/s      13802 allocs/op
Native_Posts_50     2956 ip/s        302 allocs/op

AMS_Simple_Posts_2300         21 ip/s      94309 allocs/op
AMS_Simple_Posts_50         1008 ip/s       2059 allocs/op
AMS_HasOne_Posts_2300          9 ip/s     147209 allocs/op
AMS_HasOne_Posts_50          451 ip/s       3209 allocs/op

Panko_HasOne_Posts_2300      164 ip/s       2372 allocs/op
Panko_HasOne_Posts_50       6118 ip/s        122 allocs/op
Panko_Reused_HasOne_Posts_2300       178 ip/s       2303 allocs/op
Panko_Reused_HasOne_Posts_50        8203 ip/s         53 allocs/op

Panko_Simple_Posts_2300      150 ip/s       2372 allocs/op
Panko_Simple_Posts_50       5639 ip/s        122 allocs/op
Panko_Reused_Simple_Posts_2300       180 ip/s       2303 allocs/op
Panko_Reused_Simple_Posts_50        8388 ip/s         53 allocs/op
```

## Refactorings, method call support, combining

### class eval
```
Panko_HasOne_Posts_2300       64 ip/s       9477 allocs/op
Panko_HasOne_Posts_50       2397 ip/s        477 allocs/op
Panko_Reused_HasOne_Posts_2300        70 ip/s       9423 allocs/op
Panko_Reused_HasOne_Posts_50        2596 ip/s        423 allocs/op

Panko_Simple_Posts_2300      191 ip/s       2472 allocs/op
Panko_Simple_Posts_50       5128 ip/s        222 allocs/op
Panko_Reused_Simple_Posts_2300       180 ip/s       2418 allocs/op
Panko_Reused_Simple_Posts_50        5534 ip/s        168 allocs/op
```

### instance eval
```
Panko_HasOne_Posts_2300       60 ip/s       9473 allocs/op
Panko_HasOne_Posts_50       2399 ip/s        473 allocs/op
Panko_Reused_HasOne_Posts_2300        66 ip/s       9419 allocs/op
Panko_Reused_HasOne_Posts_50        2582 ip/s        419 allocs/op

Panko_Simple_Posts_2300      195 ip/s       2470 allocs/op
Panko_Simple_Posts_50       4838 ip/s        220 allocs/op
Panko_Reused_Simple_Posts_2300       196 ip/s       2416 allocs/op
Panko_Reused_Simple_Posts_50        6241 ip/s        166 allocs/op
```
