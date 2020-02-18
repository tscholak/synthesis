# error building hasktorch-signatures-partial: Backpack typechecking not supported with -j

{ compiler ? "ghc865" }:

let
  # TODO: figure out how to use this
  hasktorch_path = "/run/media/kiara/meltan/downloads/repos/hasktorch";
  libtorch_src = pkgs:
    let src = pkgs.fetchFromGitHub {
          owner  = "stites";
          repo   = "pytorch-world";
          rev    = "4447758bf67c3370bdb622b19f34348723e3a028";
          sha256 = "06al1fiqw43d2y658l5vywr1n3sja5basbd0dyhjvjcfj9hm4zi4";
    };
    in (pkgs.callPackage "${src}/libtorch/release.nix" { });

  overlayShared = pkgsNew: pkgsOld: {
    inherit (libtorch_src pkgsOld)
      libtorch_cpu
      # libtorch_cudatoolkit_9_2
      # libtorch_cudatoolkit_10_1
    ;

    haskell = pkgsOld.haskell // {
      packages = pkgsOld.haskell.packages // {
        "${compiler}" = pkgsOld.haskell.packages."${compiler}".override (old: {
            overrides =
              let
                appendConfigureFlag = pkgsNew.haskell.lib.appendConfigureFlag;
                dontCheck = pkgsNew.haskell.lib.dontCheck;
                failOnAllWarnings = pkgsNew.haskell.lib.failOnAllWarnings;
                overrideCabal = pkgsNew.haskell.lib.overrideCabal;
                optionalString = pkgsNew.stdenv.lib.optionalString;
                isDarwin = pkgsNew.stdenv.isDarwin;

                mkHasktorchExtension = postfix:
                  haskellPackagesNew: haskellPackagesOld: {
                    "libtorch-ffi_${postfix}" =
                        appendConfigureFlag
                          (overrideCabal
                            (haskellPackagesOld.callCabal2nix
                              "libtorch-ffi"
                              /run/media/kiara/meltan/downloads/repos/hasktorch/libtorch-ffi
                              { c10 = pkgsNew."libtorch_${postfix}"
                              ; torch = pkgsNew."libtorch_${postfix}"
                              ; }
                            )
                            (old: {
                                preConfigure = (old.preConfigure or "") + optionalString isDarwin ''
                                  sed -i -e 's/-optc-std=c++11 -optc-xc++/-optc-xc++/g' ../libtorch-ffi/libtorch-ffi.cabal;
                                '';
                              }
                            )
                          )
                        "--extra-include-dirs=${pkgsNew."libtorch_${postfix}"}/include/torch/csrc/api/include";
                    "hasktorch_${postfix}" =
                      overrideCabal
                        (haskellPackagesOld.callCabal2nix
                          "hasktorch"
                          /run/media/kiara/meltan/downloads/repos/hasktorch/hasktorch
                          { libtorch-ffi = haskellPackagesNew."libtorch-ffi_${postfix}"; }
                        )
                        (old: {
                              preConfigure = (old.preConfigure or "") + optionalString (!isDarwin) ''
                                export LD_PRELOAD=${pkgs.mkl}/lib/libmkl_rt.so
                              '';
                            }
                        );
                    # "hasktorch-examples_${postfix}" =
                    #   # failOnAllWarnings
                    #     (haskellPackagesOld.callCabal2nix
                    #       "examples"
                    #       /run/media/kiara/meltan/downloads/repos/hasktorch/examples
                    #       { libtorch-ffi = haskellPackagesNew."libtorch-ffi_${postfix}"
                    #       ; hasktorch = haskellPackagesNew."hasktorch_${postfix}"
                    #       ; }
                    #     );
                  };

                extension =
                  haskellPackagesNew: haskellPackagesOld: {
                    hasktorch-codegen =
                      # failOnAllWarnings
                        (haskellPackagesNew.callCabal2nix
                          "codegen"
                          /run/media/kiara/meltan/downloads/repos/hasktorch/codegen
                          { }
                        );
                    inline-c =
                      # failOnAllWarnings
                        (haskellPackagesNew.callHackageDirect
                          {
                            pkg = "inline-c";
                            ver = "0.9.0.0";
                            sha256 = "07i75g55ffggj9n7f5y6cqb0n17da53f1v03m9by7s4fnipxny5m";
                          }
                          { }
                        );
                    inline-c-cpp =
                      # failOnAllWarnings
                      dontCheck
                        (overrideCabal
                          (haskellPackagesNew.callHackageDirect
                            {
                              pkg = "inline-c-cpp";
                              ver = "0.4.0.0";
                              sha256 = "15als1sfyp5xwf5wqzjsac3sswd20r2mlizdyc59jvnc662dcr57";
                            }
                            { }
                          )
                          (old: {
                              preConfigure = (old.preConfigure or "") + optionalString isDarwin ''
                                sed -i -e 's/-optc-std=c++11//g' inline-c-cpp.cabal;
                              '';
                            }
                          )
                        );
                    synthesis =
                      overrideCabal
                        (haskellPackagesOld.callCabal2nix
                          "synthesis"
                          # TODO: relative path?
                          # ../
                          /run/media/kiara/meltan/school/thesis/synthesis
                          {
                            # libtorch-ffi = haskellPackagesNew."libtorch-ffi_${postfix}";
                          }
                        )
                        (old: {
                              # add extra commands in the string
                              preConfigure = (old.preConfigure or "") + ''
                              '';
                            }
                        );
                  };

              in
                pkgsNew.lib.fold
                  pkgsNew.lib.composeExtensions
                  (old.overrides or (_: _: {}))
                  [ (pkgsNew.haskell.lib.packagesFromDirectory { directory = ./haskellExtensions/.; })
                    extension
                    (mkHasktorchExtension "cpu")
                    # (mkHasktorchExtension "cudatoolkit_9_2")
                    # (mkHasktorchExtension "cudatoolkit_10_1")
                  ];
          }
        );
      };
    };
  };

  bootstrap = import <nixpkgs> { };

  nixpkgs = builtins.fromJSON (builtins.readFile ./nixpkgs.json);

  src = bootstrap.fetchFromGitHub {
    owner = "NixOS";
    repo  = "nixpkgs";
    inherit (nixpkgs) rev sha256;
  };

  pkgs = import src {
    config = {
      allowUnsupportedSystem = true;
      allowUnfree = true;
      allowBroken = true;
    };
    overlays = [ overlayShared ];
  };

  nullIfDarwin = arg: if pkgs.stdenv.hostPlatform.system == "x86_64-darwin" then null else arg;

  fixmkl = old: old // {
      shellHook = ''
        export LD_PRELOAD=${pkgs.mkl}/lib/libmkl_rt.so
      '';
    };
  fixcpath = libtorch: old: old // {
      shellHook = ''
        export CPATH=${libtorch}/include/torch/csrc/api/include
      '';
    };
  altdev-announce = libtorch: old: with builtins; with pkgs.lib.strings; with pkgs.lib.lists;
    let
      echo = str: "echo \"${str}\"";
      nl = echo "";
      findFirstPrefix = pre: def: xs: findFirst (x: hasPrefix pre x) def xs;
      removeStrings = strs: xs: replaceStrings strs (map (x: "") strs) xs;

      # findAndReplaceLTS :: [String] -> String -- something like "lts-14.7"
      findAndReplaceLTS = xs:
        let pre = "resolver:";
        in removeStrings [" " "\n" pre] (findFirstPrefix pre "resolver: lts-14.7" xs);
    in
      old // {
        shellHook = old.shellHook + concatStringsSep "\n" [
          # nl
          # (echo "Suggested NixOS development uses cabal v1-*. If you plan on developing on NixOS")
          # (echo "with stack, you may still need to add the following to your stack.yaml:")
          # nl
          # (echo "  extra-lib-dirs:")
          # (echo "    - ${libtorch}/lib")
          # (echo "  extra-include-dirs:")
          # (echo "    - ${libtorch}/include")
          # (echo "    - ${libtorch}/include/torch/csrc/api/include")
          # nl
          # (echo "cabal v2-* development on NixOS may also need an updated cabal.project.local:")
          # nl
          # (echo "  package libtorch-ffi")
          # (echo "    extra-lib-dirs:     ${libtorch}/lib")
          # (echo "    extra-include-dirs: ${libtorch}/include")
          # (echo "    extra-include-dirs: ${libtorch}/include/torch/csrc/api/include")
          # # zlib.out and zlib.dev are strictly for developing with a nix-shell using stack- or cabal v2- based builds.
          # # this is a similar patch to https://github.com/commercialhaskell/stack/issues/2975
          # (echo "  package zlib")
          # (echo "    extra-lib-dirs: ${pkgs.zlib.dev}/lib")
          # (echo "    extra-lib-dirs: ${pkgs.zlib.out}/lib")
          # nl
          # (echo "as well as a freeze file from stack's resolver:")
          # # $(which curl) is used to bypass an alias to 'curl'. This is safe so long as we use gnu's which
          # (echo ''$(which curl) https://www.stackage.org/${findAndReplaceLTS (splitString "\n" (readFile ../stack.yaml))}/cabal.config \\ '')
          # (echo ("   "+''  | sed -e 's/inline-c ==.*,/inline-c ==0.9.0.0,/g' -e 's/inline-c-cpp ==.*,/inline-c-cpp ==0.4.0.0,/g' \\ ''))
          # (echo ("   "+''  > cabal.project.freeze''))
          # nl
        ];
        buildInputs = with pkgs; old.buildInputs ++ [ zlib.dev zlib.out ];
      };
  doBenchmark = pkgs.haskell.lib.doBenchmark;
  dontBenchmark = pkgs.haskell.lib.dontBenchmark;
  base-compiler = pkgs.haskell.packages."${compiler}";
in
  rec {
    inherit nullIfDarwin overlayShared;

    inherit (base-compiler)
      hasktorch-codegen
      inline-c
      inline-c-cpp
      libtorch-ffi_cpu
      # libtorch-ffi_cudatoolkit_9_2
      # libtorch-ffi_cudatoolkit_10_1
      hasktorch_cpu
      # hasktorch_cudatoolkit_9_2
      # hasktorch_cudatoolkit_10_1
      # hasktorch-examples_cpu
      # hasktorch-examples_cudatoolkit_9_2
      # hasktorch-examples_cudatoolkit_10_1
      synthesis
    ;
    # hasktorch-docs = (
    #   (import ./haddock-combine.nix {
    #     runCommand = pkgs.runCommand;
    #     lib = pkgs.lib;
    #     haskellPackages = pkgs.haskellPackages;
    #   }) {hspkgs = [
    #         base-compiler.hasktorch_cpu
    #         base-compiler.libtorch-ffi_cpu
    #       ];
    #      }
    # );
    shell-hasktorch-codegen                   = (dontBenchmark base-compiler.hasktorch-codegen).env;
    shell-inline-c                            = (dontBenchmark base-compiler.inline-c).env;
    shell-inline-c-cpp                        = (dontBenchmark base-compiler.inline-c-cpp).env;
    shell-libtorch-ffi_cpu                    = (dontBenchmark base-compiler.libtorch-ffi_cpu                   ).env.overrideAttrs(fixcpath pkgs.libtorch_cpu);
    # shell-libtorch-ffi_cudatoolkit_9_2        = (dontBenchmark base-compiler.libtorch-ffi_cudatoolkit_9_2       ).env.overrideAttrs(fixcpath pkgs.libtorch_cudatoolkit_9_2);
    # shell-libtorch-ffi_cudatoolkit_10_1       = (dontBenchmark base-compiler.libtorch-ffi_cudatoolkit_10_1      ).env.overrideAttrs(fixcpath pkgs.libtorch_cudatoolkit_10_1);
    shell-hasktorch_cpu                       = (dontBenchmark base-compiler.hasktorch_cpu                      ).env.overrideAttrs(old: altdev-announce pkgs.libtorch_cpu (fixmkl old));
    # shell-hasktorch_cudatoolkit_9_2           = (dontBenchmark base-compiler.hasktorch_cudatoolkit_9_2          ).env.overrideAttrs(old: altdev-announce pkgs.libtorch_cudatoolkit_9_2 (fixmkl old));
    # shell-hasktorch_cudatoolkit_10_1          = (dontBenchmark base-compiler.hasktorch_cudatoolkit_10_1         ).env.overrideAttrs(old: altdev-announce pkgs.libtorch_cudatoolkit_10_1 (fixmkl old));
    # shell-hasktorch-examples_cpu              = (dontBenchmark base-compiler.hasktorch-examples_cpu             ).env.overrideAttrs(fixmkl);
    # shell-hasktorch-examples_cudatoolkit_9_2  = (dontBenchmark base-compiler.hasktorch-examples_cudatoolkit_9_2 ).env.overrideAttrs(fixmkl);
    # shell-hasktorch-examples_cudatoolkit_10_1 = (dontBenchmark base-compiler.hasktorch-examples_cudatoolkit_10_1).env.overrideAttrs(fixmkl);
    shell-synthesis                            = (doBenchmark base-compiler.synthesis).env;
  }