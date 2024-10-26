
using BiBufferedStreams
using Test

@testset "BiBufferedStreams" begin

	bam = @__FILE__

	@testset "readline accuracy" begin

		io = BiBufferedStream(open(bam, "r"))

		io2 = open(bam, "r")

		n = 0
		@test_nowarn while !eof(io2) && !eof(io)
			n += 1
			x = readline(io)
			y = readline(io2)

			@assert x == y
		end

		@assert eof(io)
		@assert eof(io2)

		close(io)
		close(io2)

	end

	@testset "enlarge_buffer" begin

		### test enlarge_buffer

		io = BiBufferedStream(open(bam, "r"), 8)

		io2 = open(bam, "r")

		n = 0
		@test_nowarn while !eof(io2) && !eof(io)
			n += 1
			x = readline(io)
			y = readline(io2)
			@assert x == y
		end

		@test eof(io)
		@test eof(io2)

		close(io)
		close(io2)


		#### speed benchmark
		@info "speed benchmark"

		cmd = Sys.iswindows() ? `type` : `cat`

		bams = [bam for _ in 1:100]

		function bench_readline(cmd; bbs=true)
			io = open(cmd)
			if bbs
				io = BiBufferedStream(io)
			end
			c = 0
			tvs= @timed while !eof(io)
				line = readline(io)
				c += length(line)
			end
			close(io)
			c, tvs[2]
		end
		bench_readline(`$cmd $bams`; bbs=true)
		@show c, t = bench_readline(`$cmd $bams`; bbs=true)
		#   1.752296 seconds (4.09 M allocations: 863.047 MiB, 8.26% gc time)
		
		bench_readline(`$cmd $bams`; bbs=false)
		@show c2, t2 = bench_readline(`$cmd $bams`; bbs=false)
		#   2.250346 seconds (6.04 M allocations: 1.415 GiB, 13.29% gc time, 1.21% compilation time)

		@test c == c2
		@test t < t2 * 1.1

		close(io)
		close(io2)
	end

end
