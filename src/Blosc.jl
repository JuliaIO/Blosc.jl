module Blosc
export compress, compress!, decompress, decompress!

const libblosc = Pkg.dir("Blosc", "deps", "libblosc")

__init__() = ccall((:blosc_init,libblosc), Void, ())

# the following constants should match those in blosc.h
const MAX_OVERHEAD = 16
const MAX_THREADS = 256
const VERSION_FORMAT = 2
const MAX_TYPESIZE = 255

# Blosc is currently limited to 32-bit buffer sizes (Blosc/c-blosc#67)
const MAX_BUFFERSIZE = typemax(Cint) - MAX_OVERHEAD

# low-level functions:
blosc_compress(level, shuffle, itemsize, srcsize, src, dest, destsize) =
    ccall((:blosc_compress,libblosc), Cint,
          (Cint,Cint,Csize_t, Csize_t, Ptr{Void}, Ptr{Void}, Csize_t),
          level, shuffle, itemsize, srcsize, src, dest, destsize)
blosc_decompress(src, dest, destsize) =
    ccall((:blosc_decompress,libblosc), Cint, (Ptr{Void},Ptr{Void},Csize_t),
          src, dest, destsize)

# returns size of compressed data inside dest
function compress!{T}(dest::Vector{Uint8}, src::Ptr{T}, src_size::Integer;
	              level::Integer=5, shuffle::Bool=true,
                      itemsize::Integer=sizeof(T))	
    0 ≤ level ≤ 9 || throw(ArgumentError("invalid compression level $level not in [0,9]"))
    itemsize > 0 || throw(ArgumentError("itemsize must be positive"))
    src_size ≤ MAX_BUFFERSIZE || throw(ArgumentError("data > $MAX_BUFFERSIZE bytes is not supported by Blosc"))
    sz = blosc_compress(level, shuffle, itemsize,
                        src_size, src, dest, sizeof(dest))
    sz < 0 && error("Blosc error $sz")
    return convert(Int, sz)
end

compress!(dest::Vector{Uint8}, src::Union(Array,String); kws...) = 
    compress!(dest, pointer(src), sizeof(src); kws...)

function compress{T}(src::Ptr{T}, src_size::Integer; kws...)
    dest = Array(Uint8, src_size + MAX_OVERHEAD)
    sz = compress!(dest,src,src_size; kws...)
    assert(sz > 0 || src_size == 0)
    return resize!(dest, sz)
end

compress(src::Union(Array,String); kws...) = compress(pointer(src), sizeof(src); kws...)

# given a compressed buffer, return the (uncompressed, compressed, block) size
const sizes_vals = Array(Csize_t, 3)
function cbuffer_sizes(buf::Ptr)
    ccall((:blosc_cbuffer_sizes,libblosc), Void,
          (Ptr{Void}, Ptr{Csize_t}, Ptr{Csize_t}, Ptr{Csize_t}),
          buf,
          pointer(sizes_vals, 1),
          pointer(sizes_vals, 2),
          pointer(sizes_vals, 3))
    return (sizes_vals[1], sizes_vals[2], sizes_vals[3])
end
sizes(buf::Vector{Uint8}) = cbuffer_sizes(pointer(buf))

function decompress!{T}(dest::Vector{T}, src::Vector{Uint8})
    uncompressed, = sizes(src)
    uncompressed == 0 && return resize!(dest, 0)
    sizeT = sizeof(T)
    len = div(uncompressed, sizeT)
    if len*sizeT != uncompressed
        error("uncompressed data is not a multiple of sizeof($T)")
    end
    resize!(dest, len)
    sz = blosc_decompress(src, dest, sizeof(dest))
    sz <= 0 && error("Blosc decompress error $sz")
    return dest
end

decompress{T}(::Type{T}, src::Vector{Uint8}) = decompress!(Array(T,0), src)

function set_num_threads(n::Integer=CPU_CORES)
    1 ≤ n ≤ MAX_THREADS || throw(ArgumentError("must have 1 ≤ nthreads ≤ $MAX_THREADS"))
    return ccall((:blosc_set_nthreads,libblosc), Cint, (Cint,), n)
end

compressors() = split(bytestring(ccall((:blosc_list_compressors,libblosc),
                                       Ptr{Uint8}, ())),
                      ",")

function set_compressor(s::String)
    compcode = ccall((:blosc_set_compressor,libblosc), Cint, (Ptr{Uint8},), s)
    compcode == -1 && throw(ArgumentError("unrecognized compressor $s"))
    return compcode
end

end # module
