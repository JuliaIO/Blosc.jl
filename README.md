# The Blosc Module for Julia
[![Build Status](https://travis-ci.org/stevengj/Blosc.jl.png)](https://travis-ci.org/stevengj/Blosc.jl) [![Coverage Status](https://coveralls.io/repos/stevengj/Blosc.jl/badge.png)](https://coveralls.io/r/stevengj/Blosc.jl)

This module provides fast lossless compression for the [Julia
language](http://julialang.org/) by interfacing the [Blosc
Library](http://www.blosc.org/).

(Due to an unfortunate oversight, there are actually two Blosc
packages for Julia.  This package is the one in the official Julia
package listing, i.e. the one that will be installed by
`Pkg.add("Blosc")`.  The other package is [Blosc.jl by Jake
Bolewski](https://github.com/jakebolewski/Blosc.jl); please [file an
issue](https://github.com/stevengj/Blosc.jl/issues) if there is any
functionality in the latter that you would like to see ported to this
package.)

Note that Blosc is currently [limited to 32-bit buffer sizes](https://github.com/Blosc/c-blosc/issues/67).

## Installation

To install, simply run `Pkg.add("Blosc")` in Julia.  Precompiled
binaries are provided for Mac and Windows systems, while on other
systems the Blosc library will be downloaded and compiled.

## Usage

The basic functions provided are:

* `compress(src::Array{T}; level=5, shuffle=true, itemsize=sizeof(T))`: returns a `Vector{Uint8}` consisting of `src` in compressed form.  `level` is the compression level (between `0`=no compression and `9`=max), `shuffle` indicates whether to use Blosc's shuffling preconditioner, which is optimized for arrays of binary items of size `itemsize`.

* `compress!(dest::Vector{Uint8}, src; ...)`: as `compress`, but uses a pre-allocated destination buffer `dest`.  Returns the size (in bytes) of the compressed data, or `0` if the buffer was too small.

* `decompress(T::Type, src::Vector{Uint8})`: return the compressed buffer `src` as an array of element type `T`.

* `decompress!(dest::Vector{T}, src::Vector{Uint8})`: like `decompress`, but uses a pre-allocated destination buffer, which is resized as needed to store the decompressed data.

* `Blosc.set_num_threads(n=CPU_CORES)`: tells Blosc to use `n` threads (initially `1`).

* `Blosc.compressors()`: returns an array of strings for the available compression algorithms.

* `Blosc.set_compressor(s::String)`: set the current compression algorithm

## Author

This module was written by [Steven G. Johnson](http://math.mit.edu/~stevenj/).
