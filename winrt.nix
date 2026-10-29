# What .NET Framework needs to call WinRT under Wine:
# - windows.winmd and windows.foundation.winmd: WinRT metadata from the Windows SDK's API contracts.
#   Wine's RoResolveNamespace picks files by name prefix, so the universal contract is named after
#   the root namespace and the foundation contract (TypedEventHandler, collections) after its own.
# - System.Runtime.WindowsRuntime(.UI.Xaml).dll from the Windows 10 update package inside the .NET
#   4.8 installer; installing on Windows 7 skips them.
{ runCommand, fetchurl, _7zz, dotnet }:

let
  contracts = fetchurl {
    url = "https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.contracts/10.0.28000.2957/microsoft.windows.sdk.contracts.10.0.28000.2957.nupkg";
    hash = "sha256-n6TvDpBG0X3tVnzGlDGST/4Nw57thsrqVDvjvCOruXE=";
  };
in
runCommand "fork-winrt" { nativeBuildInputs = [ _7zz ]; } ''
  mkdir -p $out
  7zz x -bso0 -ocontracts ${contracts} 'ref/netstandard2.0/Windows.Foundation.*Contract.winmd'
  install -m 644 contracts/ref/netstandard2.0/Windows.Foundation.UniversalApiContract.winmd $out/windows.winmd
  install -m 644 contracts/ref/netstandard2.0/Windows.Foundation.FoundationContract.winmd $out/windows.foundation.winmd

  7zz x -bso0 -ondp48 ${dotnet}/ndp48-x86-x64-allos-enu.exe x64-Windows10.0-KB4486153-x64.cab
  7zz x -bso0 -okb ndp48/x64-Windows10.0-KB4486153-x64.cab
  install -m 644 kb/msil_system.runtime.windowsruntime_b77a5c561934e089_*/system.runtime.windowsruntime.dll \
    $out/System.Runtime.WindowsRuntime.dll
  install -m 644 kb/msil_system.runtime.windowsruntime.ui.xaml_b77a5c561934e089_*/system.runtime.windowsruntime.ui.xaml.dll \
    $out/System.Runtime.WindowsRuntime.UI.Xaml.dll
''
