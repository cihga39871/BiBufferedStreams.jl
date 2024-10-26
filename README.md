# BiBufferedStreams.jl

A fast double-buffered stream to wrap Cmd Pipe (eg: `open(x::Cmd)`). It fills a buffer using Cmd asyncly, and another buffer is ready to take from the main process.

In Julia v1.11.1, calling `open(x::Cmd)` is extremely slower than v1.10.4, which is why I developed this package.

## Usage

```julia
bam = "/path/to/a/bam/file"
io = BiBufferedStream(open(`samtools view -h $bam`))

while !eof(io)
    line = readline(io)
    # do something
end

close(io)
```

## Benchmark

It was tested by reading a bam file (114 MB, 1_000_002 lines). After precompilation, the benchmark function runs 3 times. Scripts are followed by results.

### Results

In Julia v1.11.1, `BiBufferedStream` is ***6.73X*** faster than `open`: 1.41s vs. 9.50s.

In Julia v1.10.4, `BiBufferedStream` is ***1.26X*** faster than `open`: 1.74s vs. 2.19s.

#### Detail `@time` outputs:

Julia v1.11.1:

- `BiBufferedStream(open(cmd))`
  - 1.476861 seconds (3.06 M allocations: 815.326 MiB, 7.63% gc time)
  - 1.397820 seconds (3.06 M allocations: 815.330 MiB, 7.38% gc time)
  - 1.379766 seconds (3.06 M allocations: 815.340 MiB, 7.47% gc time)

- `open(cmd)`
  - 9.370884 seconds (9.84 M allocations: 1.516 GiB, 0.64% gc time)
  - 9.574880 seconds (9.84 M allocations: 1.516 GiB, 0.74% gc time)
  - 9.752019 seconds (9.84 M allocations: 1.516 GiB, 0.86% gc time)


Julia v1.10.4:

- `BiBufferedStream(open(cmd))`
  - 1.741036 seconds (3.06 M allocations: 847.324 MiB, 9.60% gc time)
  - 1.782255 seconds (3.06 M allocations: 847.315 MiB, 9.59% gc time)
  - 1.681973 seconds (3.06 M allocations: 847.310 MiB, 10.87% gc time)

- `open(cmd)`
  - 2.187896 seconds (5.00 M allocations: 1.400 GiB, 15.49% gc time)
  - 2.186295 seconds (5.00 M allocations: 1.400 GiB, 15.39% gc time)
  - 2.194213 seconds (5.00 M allocations: 1.400 GiB, 15.76% gc time)

### Script

```julia
using BiBufferedStreams

bam = "/path/to/a/bam/file"

function bench_readline(cmd; use_bi_buffered_stream=true)
    if use_bi_buffered_stream
        io = BiBufferedStream(open(cmd))
    else
        io = open(cmd)
    end
    c = 0
    @time while !eof(io)
        line = readline(io)
        c += length(line)
    end
    close(io)
    c
end

cmd = `samtools view -@ 10 -h $bam`

bench_readline(cmd; use_bi_buffered_stream=true)
bench_readline(cmd; use_bi_buffered_stream=true)
bench_readline(cmd; use_bi_buffered_stream=true)
bench_readline(cmd; use_bi_buffered_stream=true)

bench_readline(cmd; use_bi_buffered_stream=false)
bench_readline(cmd; use_bi_buffered_stream=false)
bench_readline(cmd; use_bi_buffered_stream=false)
bench_readline(cmd; use_bi_buffered_stream=false)
```


## API

Currently, the following API is available.

```julia
BiBufferedStream(io::IO)

readline(io::BiBufferedStream; keep::Bool = false)

readuntil(io::BiBufferedStream, delim::Union{Char,UInt8}; keep::Bool = false)

eof(io::BiBufferedStream)

close(io::BiBufferedStream)
```
