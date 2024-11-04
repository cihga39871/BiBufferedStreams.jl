
@setup_workload begin
    file = joinpath(Sys.BINDIR, "../include/julia/uv.h")
    cmd = Sys.iswindows() ? `type` : `cat`
    
    @compile_workload begin
        c = 0
        io = BiBufferedStream(open(`$cmd $file`), 8)
        keep = true
        while !eof(io)
            keep = !keep
            line = readline(io; keep=keep)
            c += length(line)
        end
        close(io)
    end
end