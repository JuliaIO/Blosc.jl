using BinDeps
using Compat

vers = "1.8.1"

tagfile = "installed_vers"
target = "libblosc.$(Libdl.dlext)"
url = "https://bintray.com/artifact/download/julialang/generic/"
if !isfile(target) || !isfile(tagfile) || readchomp(tagfile) != "$vers $(Sys.WORD_SIZE)"
    if Compat.KERNEL == :NT
        run(download_cmd(url*"libblosc$(Sys.WORD_SIZE)-$vers.dll", target))
    elseif Compat.KERNEL == :Darwin
        run(download_cmd(url*"libblosc$(Sys.WORD_SIZE)-$vers.dylib", target))
    else
        tarball = "c-blosc-$vers.tar.gz"
        srcdir = "c-blosc-$vers/blosc"
        if !isfile(tarball)
            run(download_cmd("https://github.com/Blosc/c-blosc/archive/v$vers.tar.gz", tarball))
        end
        run(unpack_cmd(tarball, ".", ".gz", ".tar"))
        cd(srcdir) do
            println("Compiling libblosc...")
            # TODO: enable AVX for gcc >= 4.9
            run(`make -f ../../make.blosc HAVE_AVX=0 LIB=../../$target`)
        end
    end
    open(tagfile, "w") do f
        println(f, "$vers $(Sys.WORD_SIZE)")
    end
end
