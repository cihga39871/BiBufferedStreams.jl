module BiBufferedStreams


export BiBufferedStream

mutable struct BiBufferedStream
    source::IO
    fill2::Bool  # true: buffer to read is 1, buffer to fill source is 2.
    buf1::Vector{UInt8}
    buf2::Vector{UInt8}
    pos1::Int  # Position of the next byte to be read in buffer;
    pos2::Int
    available1::Int  # Number of bytes available in buffer.
    available2::Int  # I.e. buf[pos:available] is valid data.
    lock::ReentrantLock    # lock when switch buf1 and buf2
    task_fill_source::Ref{Task}
end

const default_buffer_size = 2^24

"""
    BiBufferedStream(source::IO, bufsize::Integer = BiBufferedStreams.default_buffer_size)

Wrap `source::IO` into `BiBufferedStream`. `default_buffer_size = 2^24` for each buffer.
"""
function BiBufferedStream(source::IO, bufsize::Integer = default_buffer_size)
    if bufsize < 2048
        bufsize = 2048
    end
    t = @async 1
    io = BiBufferedStream(source, eof(source), Vector{UInt8}(undef, bufsize), Vector{UInt8}(undef, bufsize), 1, 1, 0, 0, ReentrantLock(), Ref{Task}())
    io.task_fill_source[] = t
    wait(t)
    async_fill_buffer_from_source!(io::BiBufferedStream)
    io
end

"""
    async_fill_buffer_from_source!(io::BiBufferedStream)

Require lock, and fill backup buffer. No change to positions of current buffer.

This function runs asynchronously.
"""
function async_fill_buffer_from_source!(io::BiBufferedStream)
    eof(io.source) && (return false)
    lock(io.lock) do
        if istaskdone(io.task_fill_source[])
            if io.fill2 && io.available2 == 0
                io.task_fill_source[] = @async lock(io.lock) do 
                    io.available2 = readbytes!(io.source, io.buf2)
                    io.pos2 = 1
                end
            elseif !io.fill2 && io.available1 == 0
                io.task_fill_source[] = @async lock(io.lock) do 
                    io.available1 = readbytes!(io.source, io.buf1)
                    io.pos1 = 1
                end
            end
        end
    end
    true
end

"""
    switch(io::BiBufferedStream) -> Bool

Used only when current `buf[pos:available]` is copied!

Lock io, and switch current and backup. Old current pos and available will be set to 1 and 0. Then, asyncly fill old current buffer (ie. new backup buffer).

Return `true` if switch success, `false` if `eof(io)`.
"""
function switch(io::BiBufferedStream)
    lock(io.lock) do
        eof(io) && (return false)
        if io.fill2  # current=1, backup=2
            # current has been read through.
            # make backup as new current
            io.pos1 = 1
            io.available1 = 0
            io.fill2 = false
        else
            io.pos2 = 1
            io.available2 = 0
            io.fill2 = true
        end
        async_fill_buffer_from_source!(io)
    end
    return true
end

"""
    enlarge_buffer!(io::BiBufferedStream)

Return `false` if `eof(io)`.

Lock io, resize both buffers to double sizes. Append backup's available data to current data. Then, asyncly fill backup buffer from source.
"""
function enlarge_buffer!(io::BiBufferedStream)
    eof(io.source) && (return false)

    lock(io.lock)

    resize!(io.buf1, 2 * length(io.buf1))
    resize!(io.buf2, 2 * length(io.buf2))

    if io.fill2  # current=1, fill=2
        # copy fill to current
        n_copy = io.available2
        if length(io.buf1) < io.available1 + n_copy
            resize!(io.buf1, io.available1 + n_copy)
        end
        p_src = pointer(io.buf2)
        p_dest = pointer(io.buf1, io.available1 + 1)
        unsafe_copyto!(p_dest, p_src, n_copy)

        io.available1 += n_copy
        io.available2 = 0
        io.pos2 = 1
    else
        n_copy = io.available1
        if length(io.buf2) < io.available2 + n_copy
            resize!(io.buf2, io.available2 + n_copy)
        end
        p_src = pointer(io.buf1)
        p_dest = pointer(io.buf2, io.available2 + 1)
        unsafe_copyto!(p_dest, p_src, n_copy)

        io.available2 += n_copy
        io.available1 = 0
        io.pos1 = 1
    end
    unlock(io.lock)
    async_fill_buffer_from_source!(io)

    return true
end

Base.eof(io::BiBufferedStream) = io.pos1 > io.available1 && io.pos2 > io.available2 && eof(io.source)
Base.close(io::BiBufferedStream) = close(io.source)

"""
    readline(io::BiBufferedStream; keep::Bool = false)

Read a single line of text from the given io stream. Lines in the input end with '\n' or the end of an input stream. When `keep` is `true`, `\n` (if in the end) is returned as part of the line.
"""
Base.readline(io::BiBufferedStream; keep::Bool = false) = readuntil(io, 0x0a; keep = keep)

"""
    readuntil(io::BiBufferedStream, delim::Union{Char,UInt8}; keep::Bool = false)

Read a string from `io``, up to the given delimiter. The delimiter can be a UInt8 or Char (which can be converted to UInt8).

Keyword argument keep controls whether the delimiter is included in the result. The text is assumed to be encoded in UTF-8.
"""
Base.readuntil(io::BiBufferedStream, delim::Char; keep::Bool = false) = readuntil(io, UInt8(delim); keep = keep)

function Base.readuntil(io::BiBufferedStream, delim::UInt8; keep::Bool = false)
    eof(io) && (return "")
    line_first = Ref{String}()

    @label start_of_readline

    if io.fill2  # current 1, backup 2
        buf = io.buf1
        pos = io.pos1
        available = io.available1
        buf_other = io.buf2
    else
        buf = io.buf2
        pos = io.pos2
        available = io.available2
        buf_other = io.buf1
    end

    stop = pos
    
    @label loop_to_find_char

    while stop <= available
        @inbounds if buf[stop] == delim
            line = String(buf[pos:(keep ? stop : stop - 1)])
            if io.fill2
                io.pos1 = stop + 1
            else
                io.pos2 = stop + 1
            end
            if isdefined(line_first, 1)
                return line_first[] * line
            else
                return line
            end
        end
        stop += 1
    end

    if !isdefined(line_first, 1)
        ## not found until readthrough buf[pos:available]
        # first part of string:
        line_first[] = String(buf[pos:available])
        if io.fill2  # current 1, backup 2
            io.pos1 = io.available1 + 1
        else
            io.pos2 = io.available2 + 1
        end

        # check buf_other
        wait(io.task_fill_source[])
        switched = switch(io)
        if switched
            # switch success 
            @goto start_of_readline
        else
            # eof(io)
            return line_first[]
        end
    
    else
        ## line_first is defined,
        ## so this is the second round through @label start_of_readline.
        ## Besides line_first[],
        ## current String(buf[pos:available]) is still used up.

        ## we need to enlarge the buffer.
        # Lock io, resize both buffers to double sizes. Append backup's available data to current data. Then, asyncly fill backup buffer from source.
        enlarged = enlarge_buffer!(io)
        if enlarged
            # buf, pos are the same
            # available is enlarged, so need refresh
            available = io.fill2 ? io.available1 : io.available2

            # stop are the same.
            @goto loop_to_find_char
        else
            # eof(io)
            line = line_first[] * String(buf[pos:available])

            if io.fill2  # current 1, backup 2
                io.pos1 = io.available1 + 1
            else
                io.pos2 = io.available2 + 1
            end
            return line
        end
    end
end

end # module BiBufferedStreams
