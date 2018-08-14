VERSION < v"0.7.0-beta2.199" && __precompile__()

module Blosc
using Compat
import Compat.Libdl
export compress, compress!, decompress, decompress!

# Load blosc libraries from our deps.jl
const depsjl_path = joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")
if !isfile(depsjl_path)
    error("Blosc not installed properly, run Pkg.build(\"Blosc\"), restart Julia and try again")
end
include(depsjl_path)

function __init__()
    check_deps()
    ccall((:blosc_init,libblosc), Cvoid, ())
    atexit() do
        ccall((:blosc_destroy,libblosc), Cvoid, ())
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

if isdefined(Compat.GC, Symbol("@preserve"))
    import Compat.GC: @preserve
else
    macro preserve(args...)
        esc(args[end])
    end
end

# low-level functions:
blosc_compress(level, shuffle, itemsize, srcsize, src, dest, destsize) =
    ccall((:blosc_compress,libblosc), Cint,
          (Cint,Cint,Csize_t, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
          level, shuffle, itemsize, srcsize, src, dest, destsize)

blosc_decompress(src, dest, destsize) =
    ccall((:blosc_decompress,libblosc), Cint,
          (Ptr{Cvoid},Ptr{Cvoid},Csize_t), src, dest, destsize)

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
function compress!(dest::DenseVector{UInt8},
                   src::Ptr{T},
                   src_size::Integer;
                   level::Integer=5,
                   shuffle::Bool=true,
                   itemsize::Integer=sizeof(T)) where {T}
    iscontiguous(dest) || throw(ArgumentError("dest must be contiguous array"))
    if !isbitstype(T)
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
    @preserve src compress!(dest, pointer(src), sizeof(src); kws...)

function compress!(dest::DenseVector{UInt8}, src::DenseArray; kws...)
    iscontiguous(src) || throw(ArgumentError("src must be a contiguous array"))
    return @preserve src compress!(dest, pointer(src), sizeof(src); kws...)
end

function compress(src::Ptr{T}, src_size::Integer; kws...) where {T}
    dest = Vector{UInt8}(undef, src_size + MAX_OVERHEAD)
    sz = compress!(dest,src,src_size; kws...)
    @assert(sz > 0 || src_size == 0)
    return resize!(dest, sz)
end
function compress(src::DenseArray; kws...)
    iscontiguous(src) || throw(ArgumentError("src must be a contiguous array"))
    @preserve src compress(pointer(src), sizeof(src); kws...)
end
compress(src::AbstractString; kws...) = @preserve src compress(pointer(src), sizeof(src); kws...)

"""
    compress(data; level=5, shuffle=true, itemsize)

Return a `Vector{UInt8}` of the Blosc-compressed `data`, where `data`
is an array or a string.

The `level` keyword indicates the compression level
(between `0`=no compression and `9`=max), `shuffle` indicates whether to use
Blosc's shuffling preconditioner, and the shuffling preconditioner
is optimized for arrays of binary items of size (in bytes) `itemsize` (defaults
to `sizeof(eltype(data))` for arrays and the size of the code units for strings).
"""
compress

"""
    compress!(dest::Vector{UInt8}, src; kws...)

Like `compress(src; kws...)`, but writes to a pre-allocated array `dest`
of bytes.   The return value is the size in bytes of the data written
to `dest`, or `0` if the buffer was too small.
"""
compress!

# this unexported function is used by the HDF5.jl blosc filter
function cbuffer_sizes(buf)
    s1 = Ref{Csize_t}()
    s2 = Ref{Csize_t}()
    s3 = Ref{Csize_t}()
    ccall((:blosc_cbuffer_sizes,libblosc), Cvoid,
          (Ptr{UInt8}, Ref{Csize_t}, Ref{Csize_t}, Ref{Csize_t}),
          buf, s1, s2, s3)
    return (s1[], s2[], s3[])
end

"""
    sizes(buf::Vector{UInt8})

Given a compressed buffer `buf`, return a tuple
of the `(uncompressed, compressed, block)` sizes in bytes.
"""
sizes(buf::DenseVector{UInt8}) = cbuffer_sizes(buf)

"""
    decompress!(dest::Vector{T}, src::Vector{UInt8})

Like `decompress`, but uses a pre-allocated destination buffer `dest`,
which is resized as needed to store the decompressed data from `src`.
"""
function decompress!(dest::DenseVector{T}, src::DenseVector{UInt8}) where {T}
    if !iscontiguous(dest) || !iscontiguous(src)
        throw(ArgumentError("src and dest must be contiguous arrays"))
    end
    if !isbitstype(T)
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
"""
    decompress(T::Type, src::Vector{UInt8})

Return the compressed buffer `src` as an array of element type `T`.
"""
decompress(::Type{T}, src::DenseVector{UInt8}) where {T} =
    decompress!(Vector{T}(undef, 0), src)

# Initialize a pool of threads for compression / decompression.
# If `nthreads` is 1, the the serial version is chosen and a possible previous existing pool is ended.
# If this function is not callled, `nthreads` is set to 1 internally.
"""
    set_num_threads(n=Sys.CPU_CORES)

Tells Blosc to use `n` threads for compression/decompression.   If this
function is never called, the default is `1` (serial).
"""
function set_num_threads(n::Integer=Sys.CPU_CORES)
    1 <= n <= MAX_THREADS || throw(ArgumentError("must have 1 ≤ nthreads ≤ $MAX_THREADS"))
    return ccall((:blosc_set_nthreads,libblosc), Cint, (Cint,), n)
end

"""
    set_compressor(s::AbstractString)

Set the current compression algorithm to `s`.  The currently supported
algorithms in the default Blosc module build are `"blosclz"`, `"lz4"`,
and `"l4hc"`.   (Throws an `ArgumentError` if `s` is not the name
of a supported algorithm.)  Returns a nonnegative integer code used
internally by Blosc to identify the compressor.
"""
function set_compressor(s::AbstractString)
    compcode = ccall((:blosc_set_compressor,libblosc), Cint, (Cstring,), s)
    compcode == -1 && throw(ArgumentError("unrecognized compressor $s"))
    return compcode
end

"""
    set_blocksize(blocksize=0)

Force the use of a specific compression `blocksize`. If `0` (the default), an
appropriate blocksize will be chosen automatically by blosc.
"""
function set_blocksize(blocksize::Integer=0)
    blocksize >= 0 || throw(ArgumentError("n must be ≥ 0 (default)"))
    ccall((:blosc_set_blocksize,libblosc), Cvoid, (Csize_t,), blocksize)
end
@deprecate set_default_blocksize() set_blocksize()

"""
    compressor_name(src::Vector{UInt8})

Given a compressed array `src`, returns the name (string) of the
compression library that was used to generate it.  (This is not
the same as the name of the compression algorithm.)
"""
function compressor_library(src::DenseVector{UInt8})
    iscontiguous(src) || throw(ArgumentError("src must be a contiguous array"))
    nptr = ccall((:blosc_cbuffer_complib,libblosc), Ptr{UInt8}, (Ptr{UInt8},), src)
    nptr == convert(Ptr{UInt8}, 0) && error("unknown compression library")
    name = unsafe_string(nptr)
    return name
end
@deprecate compression_library(src::DenseVector{UInt8}) compressor_library(src)

struct CompressionInfo
    library::String
    typesize::Int
    pure_memcopy::Bool
    shuffled::Bool
end

"""
    compressor_info(src::Vector{UInt8})

Given a compressed array `src`, returns the information about the
compression algorithm used in a `CompressionInfo` data structure.
"""
function compressor_info(cbuf::DenseVector{UInt8})
    iscontiguous(cbuf) || throw(ArgumentError("cbuf must be contiguous array"))
    flag, typesize = Cint[0], Csize_t[0]
    ccall((:blosc_cbuffer_metainfo, libblosc), Cvoid,
          (Ptr{Cvoid},Ptr{Csize_t},Ptr{Cint}), cbuf, typesize, flag)
    pure_memcopy = flag[1] & MEMCPYED != 0
    shuffled = flag[1] & DOSHUFFLE != 0
    return CompressionInfo(compressor_library(cbuf),
                           typesize[1],
                           pure_memcopy,
                           shuffled)
end

"""
    compressors()

Return the list of compression algorithms in the Blosc library build
as an array of strings.
"""
compressors() = split(unsafe_string(ccall((:blosc_list_compressors, libblosc), Ptr{UInt8}, ())), ',')

if isdefined("", :data)
    take_cstring(ptr) = unsafe_wrap(String, ptr, true)
else
    function take_cstring(ptr)
        str = unsafe_string(ptr)
        ccall(:free, Cvoid, (Ptr{Cvoid},), ptr)
        return str
    end
end

"""
    compressor_info(name::AbstractString)

Given the `name` of a compressor in the Blosc library, return a tuple
`(compressor name, library name, version number)`.
"""
function compressor_info(name::AbstractString)
    lib, ver = Ref{Ptr{UInt8}}(), Ref{Ptr{UInt8}}()
    ret = ccall((:blosc_get_complib_info, libblosc), Cint,
                (Cstring,Ptr{Ptr{UInt8}},Ptr{Ptr{UInt8}}),
                name, lib, ver)
    ret < 0 && error("Error retrieving compressor info for $name")
    lib_str = take_cstring(lib[])
    ver_str = take_cstring(ver[])
    return (name, lib_str, ver_str == "unknown" ? v"0.0.0" : VersionNumber(ver_str))
end

"""
    compressors_info()

Return an array of tuples `(compressor name, library name, version number)`
for all of the compression libraries included in the Blosc library build.
"""
compressors_info() = map(compressor_info, compressors())

"""
    free_resources!()

Free possible memory temporaries and thread resources.
Use this when you are not going to use Blosc for a long while.
In case of problems releasing resources, it returns `false`,
whereas it returns `true` on success.
"""
free_resources!() = ccall((:blosc_free_resources,libblosc), Cint, ()) == 0

end # module
