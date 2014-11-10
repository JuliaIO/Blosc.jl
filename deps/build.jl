using BinDeps

vers = "1.5.0"

tagfile = "installed_vers"
target = "libblosc.$(Sys.dlext)"
if !isfile(tagfile) || readchomp(tagfile) != vers
    if OS_NAME == :Windows
        run(download_cmd("http://ab-initio.mit.edu/blosc/libblosc$WORD_SIZE-$vers.dll", target))
    elseif OS_NAME == :Darwin
        run(download_cmd("http://ab-initio.mit.edu/blosc/libblosc$WORD_SIZE-$vers.dylib", target))
    else
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
            run(`gcc -shared -o ../../$target blosc.o blosclz.o shuffle.o`)
        end
    end
    run(`echo $vers` |> tagfile)
end
