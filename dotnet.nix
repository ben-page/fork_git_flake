# .NET Framework 4.8's offline installer, plus the mscoree.dll shim and its message DLL from the
# .NET 4.0 installer. The 4.8 installer leaves the shim to Windows, and Wine's own mscoree loads
# Wine Mono, not Microsoft's runtime.
{ runCommand, fetchurl, _7zz }:

let
  ndp48 = fetchurl {
    url = "https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe";
    hash = "sha256-lYidbePyBwwHeQrWzyAA0z2aG9/Go4FyWrgqscMU/VM=";
  };
  ndp40 = fetchurl {
    url = "https://download.microsoft.com/download/9/5/A/95A9616B-7A37-4AF6-BC36-D6EA96C8DAAE/dotNetFx40_Full_x86_x64.exe";
    hash = "sha256-ZeBkJY8uQYgWswT2Rv+eh68QHkyVUqsGS7dNKBw4ZZ8=";
  };
in
runCommand "fork-dotnet48" { nativeBuildInputs = [ _7zz ]; } ''
  7zz x -bso0 -ondp40 ${ndp40} netfx_Core.mzz
  7zz x -bso0 -ocore ndp40/netfx_Core.mzz \
    _003_mscoree_dll_amd64 _003_mscoree_dll_x86 _017_mscorees_dll_amd64 _017_mscorees_dll_x86
  install -D -m 644 core/_003_mscoree_dll_amd64 $out/x86_64/mscoree.dll
  install -D -m 644 core/_017_mscorees_dll_amd64 $out/x86_64/mscorees.dll
  install -D -m 644 core/_003_mscoree_dll_x86 $out/i386/mscoree.dll
  install -D -m 644 core/_017_mscorees_dll_x86 $out/i386/mscorees.dll
  ln -s ${ndp48} $out/ndp48-x86-x64-allos-enu.exe
''
