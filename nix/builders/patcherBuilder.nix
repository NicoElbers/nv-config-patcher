{ lib, stdenvNoCC, makeWrapper, callPackage }:
{ patcher , nixpkgs }:
{
  luaPath
  , plugins
  , name
  , withNodeJs
  , withRuby
  , rubyEnv ? null
  , withPerl
  , perlEnv ? null
  , withPython3
  , python3Env ? null
  , extraPython3WrapperArgs ? []
  , extraConfig ? []
  , customSubs ? [] 
}:
let
  nixpkgsOutPath = nixpkgs.outPath;

  inputBlob = [(builtins.concatStringsSep ";"
    (builtins.map (plugin: "${plugin.pname}|${plugin.version}|${plugin}") plugins))];

  inputBlobEscaped = (if inputBlob == [""] 
    then "'a'"
    else lib.escapeShellArgs inputBlob);

  subBlob = [(builtins.concatStringsSep ";"
    (map (s: "${s.from}|${s.to}") customSubs))];

  subBlobEscaped = (if subBlob == [""] 
    then "'b'"
    else lib.escapeShellArgs subBlob);

  providers = (callPackage ./providerBuilder.nix {}) {
    inherit name;
    inherit withNodeJs;
    inherit withRuby rubyEnv;
    inherit withPerl perlEnv;
    inherit withPython3 python3Env extraPython3WrapperArgs;
  };

  hostprog_check_table = {
    node = withNodeJs;
    python = false;
    python3 = withPython3;
    ruby = withRuby;
    perl = withPerl;
  };

  genProviderCmd = prog: withProg: 
    if withProg 
    then "vim.g.${prog}_host_prog='${providers}/bin/${name}-${prog}'"
    else "vim.g.loaded_${prog}_provider=0";

  # TODO: pass these in as extra config later
  hostProviderLua = lib.mapAttrsToList genProviderCmd hostprog_check_table;

  finalExtraConfig = builtins.concatStringsSep "\n" (
        [ "-- Config generated by ${name}"]
        # Advertise providers to your config
        ++ hostProviderLua
        # Advertise to your config that this is nixos
        ++ [ "vim.g.nixos = true"]
        # Make sure nvim looks at the correct config
        ++ [ '' 
           vim.g.configdir = vim.fn.stdpath('config')
           vim.opt.packpath:remove(vim.g.configdir)
           vim.opt.runtimepath:remove(vim.g.configdir)
           vim.opt.runtimepath:remove(vim.g.configdir .. "/after")
           vim.g.configdir = [[${placeholder "out"}]]
           vim.opt.packpath:prepend(vim.g.configdir)
           vim.opt.runtimepath:prepend(vim.g.configdir)
           vim.opt.runtimepath:append(vim.g.configdir .. "/after") 
        '']
        ++ [ "-- Extra config provided by user"]
        ++ (if (builtins.isList extraConfig) then extraConfig else [extraConfig])
        ++ [ "-- Lua config"]
        ++ [ "\n" ]);

  finalExtraConfigEscaped = lib.escapeShellArgs [finalExtraConfig];
in 
stdenvNoCC.mkDerivation {
  name = "nvim-config-patched";
  version = "0";
  src = luaPath;

  dontConfigure = true;
  dontInstall = true;

  buildPhase = /* bash */ ''
  ${lib.getExe patcher} \
    ${nixpkgsOutPath} \
    $(pwd) \
    $out \
    ${inputBlobEscaped} \
    ${subBlobEscaped} \
    ${finalExtraConfigEscaped} 
  '';
}
