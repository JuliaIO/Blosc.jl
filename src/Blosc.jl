module Blosc
export compress, compress!, decompress, decompress!

const libblosc = Pkg.dir("Blosc", "deps", "libblosc")

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

# Returns the size of compressed data inside dest
function compress!{T}(dest::Vector{Uint8},
                      src::Ptr{T},
                      src_size::Integer;
	                  level::Integer=5,
                      shuffle::Bool=true,
                      itemsize::Integer=sizeof(T))
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
sizes(buf::Vector{Uint8}) = cbuffer_sizes(pointer(buf))

function decompress!{T}(dest::DenseVector{T}, src::DenseVector{Uint8})
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
decompress{T}(::Type{T}, src::DenseVector{Uint8}) =
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
function set_compressor(s::String)
    compcode = ccall((:blosc_set_compressor,libblosc), Cint, (Ptr{Uint8},), s)
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

function compression_library(src::DenseVector{Uint8})
    nptr = ccall((:blosc_cbuffer_complib,libblosc), Ptr{Cchar}, (Ptr{Void},), convert(Ptr{Void}, src))
    nptr == convert(Ptr{Cchar}, 0) && error("unknown compression library")
    name = bytestring(nptr)
    return name
end

immutable CompressionInfo
    library::String
    typesize::Int
    pure_memcopy::Bool
    shuffled::Bool
end

# return compressor information for a compressed buffer
function compressor_info(cbuf::DenseVector{Uint8})
    flag, typesize = Cint[0], Csize_t[0]
    ccall((:blosc_cbuffer_metainfo, libblosc), Void,
          (Ptr{Void},Ptr{Csize_t},Ptr{Cint}), cbuf, typesize, flag)
    pure_memcopy, shuffled = bool(flag[1] & MEMCPYED), bool(flag[1] & DOSHUFFLE)
    return CompressionInfo(compression_library(cbuf),
                           typesize[1],
                           pure_memcopy,
                           shuffled)
end

# list of compression libraries in the Blosc library build (list of strings)
compressors() = split(bytestring(ccall((:blosc_list_compressors, libblosc), Ptr{Cchar}, ())), ',')

# given a compressor in the Blosc library, return (library name, version number) tuple
function compressor_info(name::String)
    lib, ver = Array(Ptr{Cchar},1), Array(Ptr{Cchar},1)
    ret = ccall((:blosc_get_complib_info, libblosc), Cint,
                (Ptr{Cchar},Ptr{Ptr{Cchar}},Ptr{Ptr{Cchar}}),
                name, lib, ver)
    ret < 0 && error("Error retrieving compressor info for $name")
    lib_str = bytestring(lib[1]); c_free(lib[1])
    ver_str = bytestring(ver[1]); c_free(ver[1])
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
