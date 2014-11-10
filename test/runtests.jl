using Blosc
using Base.Test

x = rand(100)
@test decompress(eltype(x), compress(x)) == x
@test "blosclz" in Blosc.compressors()
@test Blosc.set_compressor("blosclz") != -1
