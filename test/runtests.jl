using Blosc
using Base.Test

x = rand(100)
@test decompress(eltype(x), compress(x)) == x
@test isempty(decompress(Int, compress(Int[])))

@test "blosclz" in Blosc.compressors()
@test Blosc.set_compressor("blosclz") != -1

s = convert(ASCIIString, rand('0':'z', 10000))
@test ASCIIString(decompress(Uint8, compress(s))) == s
@test isempty(decompress(Uint8, compress("")))
