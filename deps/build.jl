using BinaryProvider # requires BinaryProvider 0.3.0 or later

# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))
products = [
    LibraryProduct(prefix, String["libblosc"], :libblosc),
]

# Download binaries from hosted location
bin_prefix = "https://github.com/stevengj/BloscBuilder/releases/download/v1.14.3+2"

# Listing of files generated by BinaryBuilder:
download_info = Dict(
    Linux(:aarch64, :glibc) => ("$bin_prefix/Blosc.aarch64-linux-gnu.tar.gz", "30a38c90dca3d9631ba9db63fad6051fa672642665e11e0cad13543c03aaec08"),
    Linux(:aarch64, :musl) => ("$bin_prefix/Blosc.aarch64-linux-musl.tar.gz", "ea01150f116d3b5eb98a891f5acac1dd27f1924c1c471209a5762a80acdbc48f"),
    Linux(:armv7l, :glibc, :eabihf) => ("$bin_prefix/Blosc.arm-linux-gnueabihf.tar.gz", "0ec066568605143651742a4bbbb5fa267d9f90ee98780c65bbdad7534910f9cc"),
    Linux(:armv7l, :musl, :eabihf) => ("$bin_prefix/Blosc.arm-linux-musleabihf.tar.gz", "39b7bbb06da98de29a7e8555ab0d482971426035a7c8e7dfe7701d5981e08eaa"),
    Linux(:i686, :glibc) => ("$bin_prefix/Blosc.i686-linux-gnu.tar.gz", "b440ae3ec9e60f8503a53d5cbcb9d0db778050de4b6362cd9b1f249eeec67d3f"),
    Linux(:i686, :musl) => ("$bin_prefix/Blosc.i686-linux-musl.tar.gz", "f42a44e6b2b9593c63b9037ccdcfe77caa2ffef3815b9900c5528bb474a9d37e"),
    Windows(:i686) => ("$bin_prefix/Blosc.i686-w64-mingw32.tar.gz", "a666cdf3778ad1592809bfe6ccfdb1c2e8023fdbc01dcd8f9a57615d31169681"),
    Linux(:powerpc64le, :glibc) => ("$bin_prefix/Blosc.powerpc64le-linux-gnu.tar.gz", "ce64825cbe5256484b464731ca6936e336a77908f19d777589811ef1f7ae4ebb"),
    MacOS(:x86_64) => ("$bin_prefix/Blosc.x86_64-apple-darwin14.tar.gz", "7b4f3d4afd5660ed51efbb098c59d95540d83d4f1c5aab05bd05f30589a1f5ea"),
    Linux(:x86_64, :glibc) => ("$bin_prefix/Blosc.x86_64-linux-gnu.tar.gz", "abc375a56aa4be8ebbb138346fb1f8fa558f50126011a6c6fbda97062b69629e"),
    Linux(:x86_64, :musl) => ("$bin_prefix/Blosc.x86_64-linux-musl.tar.gz", "cc69854101cb9d71a66b1245fcb7864c0f96554b8e781b18be41e213d381ea8e"),
    Windows(:x86_64) => ("$bin_prefix/Blosc.x86_64-w64-mingw32.tar.gz", "a72e6791350f6118af88fb302ec09f3a48cef9d6836b16c231286b1aeda09aea"),
)

# Install unsatisfied or updated dependencies:
unsatisfied = any(!satisfied(p; verbose=verbose) for p in products)
if haskey(download_info, platform_key())
    url, tarball_hash = download_info[platform_key()]
    if unsatisfied || !isinstalled(url, tarball_hash; prefix=prefix)
        # Download and install binaries
        install(url, tarball_hash; prefix=prefix, force=true, verbose=verbose)
    end
elseif unsatisfied
    # If we don't have a BinaryProvider-compatible .tar.gz to download, complain.
    # Alternatively, you could attempt to install from a separate provider,
    # build from source or something even more ambitious here.
    error("Your platform $(triplet(platform_key())) is not supported by this package!")
end

# Write out a deps.jl file that will contain mappings for our products
write_deps_file(joinpath(@__DIR__, "deps.jl"), products)
