using BinDeps

vers = "1.5.0"

tagfile = "installed_vers"
if !isfile(tagfile) || readchomp(tagfile) != vers
    tarball = "c-blosc-$vers.tar.gz"
    srcdir = "c-blosc-$vers/blosc"
    if !isfile(tarball)
        run(download_cmd("https://github.com/Blosc/c-blosc/archive/v$vers.tar.gz", tarball))
    end
    run(unpack_cmd(tarball, ".", ".gz", ".tar"))
    cd(srcdir) do
        println("Compiling libblosc...")
        for f in ("blosc.c", "blosclz.c", "shuffle.c")
            println("   CC $f")
            run(`gcc -fPIC -O3 -msse2 -I. -c $f`)
        end
        println("   LINK libblosc")
        run(`gcc -shared -o ../../libblosc.$(Sys.dlext) blosc.o blosclz.o shuffle.o`)
    end
    run(`echo $vers` |> tagfile)
end
