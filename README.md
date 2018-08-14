# The Blosc Module for Julia
[![Build Status](https://travis-ci.org/stevengj/Blosc.jl.svg)](https://travis-ci.org/stevengj/Blosc.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/xecc7ef70usxy4d5?svg=true)](https://ci.appveyor.com/project/StevenGJohnson/blosc-jl)

This module provides fast lossless compression for the [Julia
language](http://julialang.org/) by interfacing the [Blosc
Library](http://www.blosc.org/).

Note that Blosc is currently [limited to 32-bit buffer
sizes](https://github.com/Blosc/c-blosc/issues/67).  Blosc *does* run
just fine on 64-bit systems; it just can't compress arrays bigger than
2GB.  Note also that this limitation does *not affect* the use of Blosc
compression [for HDF5](https://github.com/timholy/HDF5.jl), since HDF5
breaks up large arrays into small chunks before compressing them.  So,
don't worry about this if you are just using Blosc within the HDF5 package.

## Installation

To install, simply run `Pkg.add("Blosc")` in Julia.  Precompiled
binaries are provided for Mac and Windows systems, while on other
systems the Blosc library will be downloaded and compiled.

## Usage

The functions provided are:

* `compress(src::Array{T}; level=5, shuffle=true, itemsize=sizeof(T))`: returns a `Vector{UInt8}` consisting of `src` in compressed form.  `level` is the compression level (between `0`=no compression and `9`=max), `shuffle` indicates whether to use Blosc's shuffling preconditioner, which is optimized for arrays of binary items of size `itemsize`.

* `compress!(dest::Vector{UInt8}, src; ...)`: as `compress`, but uses a pre-allocated destination buffer `dest`.  Returns the size (in bytes) of the compressed data, or `0` if the buffer was too small.

* `decompress(T::Type, src::Vector{UInt8})`: return the compressed buffer `src` as an array of element type `T`.

* `decompress!(dest::Vector{T}, src::Vector{UInt8})`: like `decompress`, but uses a pre-allocated destination buffer, which is resized as needed to store the decompressed data.

* `Blosc.set_num_threads(n=CPU_CORES)`: tells Blosc to use `n` threads (initially `1`).

* `Blosc.compressors()`: returns an array of strings for the available compression algorithms.  (Currently, only the `blosclz`, `lz4`, and `lz4hc` algorithms are included.)

* `Blosc.set_compressor(s::AbstractString)`: set the current compression algorithm

## Author

This module was written by [Steven
G. Johnson](http://math.mit.edu/~stevenj/) and [Jake
Bolewski](https://github.com/jakebolewski/) (who had independently
written his own Blosc.jl package which is now merged with this one).
