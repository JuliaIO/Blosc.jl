using Blosc
using Base.Test

@test_throws ArgumentError Blosc.set_num_threads(0)
@test_throws ArgumentError Blosc.set_num_threads(Blosc.MAX_THREADS + 1)
@test Blosc.set_num_threads(1) == 1

@test_throws ArgumentError Blosc.set_compressor("does_not_exist")
for comp in Blosc.compressors()
    Blosc.set_compressor(comp)
end
@test "blosclz" in Blosc.compressors()
@test Blosc.set_compressor("blosclz") != -1

Blosc.set_blocksize(16)
Blosc.set_blocksize(256)
Blosc.set_blocksize(0)
Blosc.set_default_blocksize()
@test_throws ArgumentError Blosc.set_blocksize(-1)

s = convert(ASCIIString, rand('0':'z', 10000))
@test ASCIIString(decompress(Uint8, compress(s))) == s
@test isempty(decompress(Uint8, compress("")))

x = rand(100)
@test decompress(eltype(x), compress(x)) == x
@test isempty(decompress(Int, compress(Int[])))

# round trip test
roundtrip(orig) = Blosc.decompress(eltype(orig), Blosc.compress(orig)) == orig
for ty in [Float16, Float32, Float64,
           Int8, Int16, Int32, Int64, Int128,
           Uint8, Uint16, Uint32, Uint64, Uint128]
    for i=1:2048
        a = rand(ty, i)
        @test roundtrip(a)
    end
end
# cannot compress element types that are not isbits
@test_throws ArgumentError Blosc.compress([BigInt(1)])

# test that we actually are compressing
a = ones(Float64, 1000)
ac = Blosc.compress(a)
@test sizeof(ac) < sizeof(a)
@test Blosc.decompress(Float64, ac) == a

# test all compressors
for (comp, name, _) in Blosc.compressors(libversion=true)
    for level=0:9
        for shuffle in (true, false)
            for i=1:2048
                a = rand(Uint8, i)
                ac = Blosc.compress(a, level=level, shuffle=shuffle)
                info = Blosc.metainfo(ac)
                @test info.library == name
                @test info.typesize == sizeof(Uint8)
                @test info.shuffled == shuffle
                @test Blosc.decompress(Uint8, ac) == a
            end
        end
    end
end

# test compress invalid args
@test_throws ArgumentError Blosc.compress([BigInt(1)])
@test_throws ArgumentError Blosc.compress(ones(Uint8, 256), level=-1)
@test_throws ArgumentError Blosc.compress(ones(Uint8, 256), level=11)

@test Blosc.free_resources!()
