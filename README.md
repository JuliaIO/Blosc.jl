# The Blosc Module for Julia

This module provides fast lossless compression for the [Julia
language](http://julialang.org/) by interfacing the [Blosc
Library](http://www.blosc.org/).

## Installation

To install, simply run `Pkg.add("Blosc")` in Julia.  Precompiled
binaries are provided for Mac and Windows system, while on other
systems the Blosc library will be downloaded and compiled.

## Usage

The basic functions provided are:

* `compress(src::Array{T}; level=6, shuffle=true, typesize=sizeof(T))`: returns a `Vector{Uint8}` consisting of `src` in compressed form.  `level` is the compression level (between `0`=no compression and `9`=max), `shuffle` indicates whether to use Blosc's shuffling preconditioner, which is optimized for arrays of binary blobs of size `typesize`.

* `compress!(dest::Vector{Uint8}, src; ...)`: as `compress`, but uses a pre-allocated destination buffer `dest`.  Returns the size (in bytes) of the compressed data, or `0` if the buffer was too small.

* `decompress(T::Type, src::Vector{Uint8})`: return the compressed buffer `src` as an array of element type `T`.

* `decompress!(dest::Vector{T}, src::Vector{Uint8})`: like `decompress`, but uses a pre-allocated destination buffer, which is resized as needed to store the decompressed data.

* `Blosc.set_num_threads(n=CPU_CORES)`: tells Blosc to use `n` threads (initially `1`).

* `Blosc.compressors()`: returns an array of strings for the available compression algorithms.

* `Blosc.set_compressor(s::String)`: set the current compression algorithm

## Author

This module was written by [Steven G. Johnson](http://math.mit.edu/~stevenj/).
