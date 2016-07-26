VERSION >= v"0.4.0-dev+6521" && __precompile__()

module Blosc
export compress, compress!, decompress, decompress!

using Compat
import Compat.String

const libblosc = joinpath(dirname(@__FILE__), "..", "deps", "libblosc")

function __init__()
    ccall((:blosc_init,libblosc), Void, ())
    atexit() do
        ccall((:blosc_destroy,libblosc), Void, ())
    end
end

# The following constants should match those in blosc.h
const VERSION_FORMAT = 2
const MAX_OVERHEAD = 16
const DOSHUFFLE = 0x1
const MEMCPYED = 0x2
const MAX_THREADS = 256

# Blosc is currently limited to 32-bit buffer sizes (Blosc/c-blosc#67)
const MAX_BUFFERSIZE = typemax(Cint) - MAX_OVERHEAD
const MAX_TYPESIZE = 255

# low-level functions:
blosc_compress(level, shuffle, itemsize, srcsize, src, dest, destsize) =
    ccall((:blosc_compress,libblosc), Cint,
          (Cint,Cint,Csize_t, Csize_t, Ptr{Void}, Ptr{Void}, Csize_t),
          level, shuffle, itemsize, srcsize, src, dest, destsize)

blosc_decompress(src, dest, destsize) =
    ccall((:blosc_decompress,libblosc), Cint,
          (Ptr{Void},Ptr{Void},Csize_t), src, dest, destsize)

# check whether the strides of A correspond to contiguous data
iscontiguous(::Array) = true
iscontiguous(::Vector) = true
iscontiguous(A::DenseVector) = stride(A,1) == 1
function iscontiguous(A::DenseArray)
    p = sortperm([strides(A)...])
    s = 1
    for k = 1:ndims(A)
        if stride(A,p[k]) != s
            return false
        end
        s *= size(A,p[k])
    end
    return true
end

# Returns the size of compressed data inside dest
function compress!{T}(dest::DenseVector{UInt8},
                      src::Ptr{T},
                      src_size::Integer;
	                  level::Integer=5,
                      shuffle::Bool=true,
                      itemsize::Integer=sizeof(T))
    iscontiguous(dest) || throw(ArgumentError("dest must be contiguous array"))
    if !isbits(T)
        throw(ArgumentError("buffer eltype must be `isbits` type"))
    end
    if itemsize <= 0
        throw(ArgumentError("itemsize must be positive"))
    end
    if level < 0 || level > 9
        throw(ArgumentError("invalid compression level $level not in [0,9]"))
    end
    if src_size > MAX_BUFFERSIZE
        throw(ArgumentError("data > $MAX_BUFFERSIZE bytes is not supported by Blosc"))
    end
    sz = blosc_compress(level, shuffle, itemsize, src_size, src, dest, sizeof(dest))
    sz < 0 && error("Blosc internal error when compressing data (errorcode: $sz)")
    return convert(Int, sz)
end

compress!(dest::DenseVector{UInt8}, src::AbstractString; kws...) =
    compress!(dest, pointer(src), sizeof(src); kws...)

function compress!(dest::DenseVector{UInt8}, src::DenseArray; kws...)
    iscontiguous(src) || throw(ArgumentError("src must be a contiguous array"))
    return compress!(dest, pointer(src), sizeof(src); kws...)
end

function compress{T}(src::Ptr{T}, src_size::Integer; kws...)
    dest = Array(UInt8, src_size + MAX_OVERHEAD)
    sz = compress!(dest,src,src_size; kws...)
    assert(sz > 0 || src_size == 0)
    return resize!(dest, sz)
end
function compress(src::DenseArray; kws...)
    iscontiguous(src) || throw(ArgumentError("src must be a contiguous array"))
    compress(pointer(src), sizeof(src); kws...)
end
compress(src::AbstractString; kws...) = compress(pointer(src), sizeof(src); kws...)

# given a compressed buffer, return the (uncompressed, compressed, block) size
const _sizes_vals = Array(Csize_t, 3)
function cbuffer_sizes(buf::Ptr)
    ccall((:blosc_cbuffer_sizes,libblosc), Void,
          (Ptr{Void}, Ptr{Csize_t}, Ptr{Csize_t}, Ptr{Csize_t}),
          buf,
          pointer(_sizes_vals, 1),
          pointer(_sizes_vals, 2),
          pointer(_sizes_vals, 3))
    return (_sizes_vals[1], _sizes_vals[2], _sizes_vals[3])
end
sizes(buf::Vector{UInt8}) = cbuffer_sizes(pointer(buf))

function decompress!{T}(dest::DenseVector{T}, src::DenseVector{UInt8})
    if !iscontiguous(dest) || !iscontiguous(src)
        throw(ArgumentError("src and dest must be contiguous arrays"))
    end
    if !isbits(T)
        throw(ArgumentError("dest must be a DenseVector of `isbits` element types"))
    end
    uncompressed, = sizes(src)
    if uncompressed == 0
        return resize!(dest, 0)
    end
    sizeT = sizeof(T)
    len = div(uncompressed, sizeT)
    if len * sizeT != uncompressed
        error("uncompressed data is not a multiple of sizeof($T)")
    end
    resize!(dest, len)
    sz = blosc_decompress(src, dest, sizeof(dest))
    sz == 0 && error("Blosc decompress error, compressed data is corrupted")
    sz <  0 && error("Blosc decompress error, output buffer is not large enough")
    return dest
end
decompress{T}(::Type{T}, src::DenseVector{UInt8}) =
    decompress!(Array(T,0), src)

# Initialize a pool of threads for compression / decompression.
# If `nthreads` is 1, the the serial version is chosen and a possible previous existing pool is ended.
# If this function is not callled, `nthreads` is set to 1 internally.
function set_num_threads(n::Integer=CPU_CORES)
    1 <= n <= MAX_THREADS || throw(ArgumentError("must have 1 ≤ nthreads ≤ $MAX_THREADS"))
    return ccall((:blosc_set_nthreads,libblosc), Cint, (Cint,), n)
end

# Select the compressor to be used.
# Supported ones are "blosclz", "lz4", "lz4hc", "snappy", and "zlib".
# If this function is not called, "blosclz" will be used.
# Throws an ArgumentError if the given compressor is not supported
function set_compressor(s::AbstractString)
    compcode = ccall((:blosc_set_compressor,libblosc), Cint, (Ptr{UInt8},), s)
    compcode == -1 && throw(ArgumentError("unrecognized compressor $s"))
    return compcode
end

# Force the use of a specific blocksize
function set_blocksize(blocksize::Integer)
    blocksize >= 0 || throw(ArgumentError("n must be ≥ 0 (default)"))
    ccall((:blosc_set_blocksize,libblosc), Void, (Csize_t,), blocksize)
end

# Allow Blosc to set the optimal blocksize (default)
set_default_blocksize() = set_blocksize(0)

function compression_library(src::DenseVector{UInt8})
    iscontiguous(src) || throw(ArgumentError("src must be a contiguous array"))
    nptr = ccall((:blosc_cbuffer_complib,libblosc), Ptr{UInt8}, (Ptr{UInt8},), src)
    nptr == convert(Ptr{UInt8}, 0) && error("unknown compression library")
    name = unsafe_string(nptr)
    return name
end

immutable CompressionInfo
    library::String
    typesize::Int
    pure_memcopy::Bool
    shuffled::Bool
end

# return compressor information for a compressed buffer
function compressor_info(cbuf::DenseVector{UInt8})
    iscontiguous(cbuf) || throw(ArgumentError("cbuf must be contiguous array"))
    flag, typesize = Cint[0], Csize_t[0]
    ccall((:blosc_cbuffer_metainfo, libblosc), Void,
          (Ptr{Void},Ptr{Csize_t},Ptr{Cint}), cbuf, typesize, flag)
    pure_memcopy = flag[1] & MEMCPYED != 0
    shuffled = flag[1] & DOSHUFFLE != 0
    return CompressionInfo(compression_library(cbuf),
                           typesize[1],
                           pure_memcopy,
                           shuffled)
end

# list of compression libraries in the Blosc library build (list of strings)
compressors() = split(unsafe_string(ccall((:blosc_list_compressors, libblosc), Ptr{UInt8}, ())), ',')

# given a compressor in the Blosc library, return (compressor name, library name, version number) tuple
function compressor_info(name::AbstractString)
    lib, ver = Array(Ptr{UInt8},1), Array(Ptr{UInt8},1)
    ret = ccall((:blosc_get_complib_info, libblosc), Cint,
                (Cstring,Ptr{Ptr{UInt8}},Ptr{Ptr{UInt8}}),
                name, lib, ver)
    ret < 0 && error("Error retrieving compressor info for $name")
    lib_str = unsafe_wrap(Compat.String, lib[1], true)
    ver_str = unsafe_wrap(Compat.String, ver[1], true)
    return (name, lib_str, convert(VersionNumber, ver_str))
end


# Get info from compression libraries included in the `Blosc` library build.
# Returns an array of tuples, (library name, version number).
compressors_info() = map(compressor_info, compressors())

# Free possible memory temporaries and thread resources.
# Use this when you are not going to use `Blosc` for a long while.
# In case of problems releasing resources, it returns false, else returns true.
free_resources!() = ccall((:blosc_free_resources,libblosc), Cint, ()) == 0

end # module
