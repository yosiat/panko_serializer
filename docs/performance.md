# Performance

The performance of Panko is measured using microbenchmarks and load testing.

## Microbenchmarks

The following microbenchmarks are run on MacBook Pro (Retina, 15-inch, Mid 2015), Ruby 2.4 with Rails 4.2
demonstrating the performance of ActiveModelSerializers 0.9 and Panko 0.3.3


 Benchmark                             | AMS ip/s     | Panko ip/s
---------------------------------------|----------|-----------------
| Simple_Posts_2300               | 25.81   | 135.29         |
| Simple_Posts_50                 | 1,248.39 | 6,518.68          |
| HasOne_Posts_2300               | 11.33     | 73.42         |
| HasOne_Posts_50                 | 523.14  | 4,985.41           |

> The corresponding benchmarks are `benchmarks/bm_active_model_serializers.rb` and `benchmarks/bm_panko_json.rb`


## Real-world benchmark

The real-world benchmark here is endpoint which serializes 7,884 entries with 48 attributes and no associations.
The benchmark took place in environment that simulates production environment and run using `wrk` from machine on the same cluster.


Metric | AMS | Panko
------------ |------------ | -------------
Avg Response Time| 4.89s| 1.48s|
Max Response Time| 5.42s| 1.83s|
99th Response Time| 5.42s| 1.74s|
Total Requests| 61| 202|


*Thanks to [Bringg](https://www.bringg.com) for providing the infrastructrue for the benchmarks*
