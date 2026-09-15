{
  description = "hull-form-dev — pinned MDO analysis stack (PETSc/ADflow/pyHyp/pyGeo)";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
  };

  outputs =
    { self, ... }@inputs:
    let
      inherit (inputs.nixpkgs) lib;

      # SNOPT is a licensed optimizer whose sources cannot be fetched, so the
      # flake cannot detect whether you have it. Leave true if the zip is in
      # your store (nix-store --add-fixed sha256 /path/to/snopt7.7.7.zip);
      # set false to build pyoptsparse without SNOPT (IPOPT via cyipopt,
      # SLSQP, etc. still work).
      enableSnopt = true;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [
                (final: prev: {
                  # ADflow imports every public PETSc name via its `constants`
                  # module (`use petsc` with no `only`). PETSc >= 3.22 turned
                  # Fortran type-name macros (TSALPHA, PCMAT, ...) into module
                  # parameters, which collide with ADflow's own identifiers, so
                  # pin 3.21.6 — the last release with macro-style bindings.
                  # Lean build: ADflow only needs Vec/Mat/KSP + MPI + Fortran,
                  # none of the external solver packages.
                  petscForAdflow =
                    (prev.petsc.override {
                      withCommonDeps = false;
                      # 3.21's configure imports xdrlib, removed in python 3.13;
                      # run it with the 3.11 interpreter this flake already uses.
                      python3Packages = prev.python311Packages;
                    }).overrideAttrs
                      (old: rec {
                        version = "3.21.6";
                        src = prev.fetchzip {
                          url = "https://web.cels.anl.gov/projects/petsc/download/release-snapshots/petsc-${version}.tar.gz";
                          hash = "sha256-0povSwwSx15VjlidzELorThfDYmZLrHswUygh7ElVrQ=";
                        };
                        # 3.24's petsc4py install-prefix patch; python bindings
                        # are disabled here and it does not apply to 3.21.
                        patches = [ ];
                      });

                  # Pin CGNS to 4.5.0 to match the hand-built stack in
                  # ~/packages on the mac host, so both environments run the
                  # same library version. The only change in 4.5.1 is an
                  # HDF5 2.0 CMake/parallel build fix this stack doesn't need.
                  cgns = prev.cgns.overrideAttrs (old: {
                    version = "4.5.0";
                    src = prev.fetchFromGitHub {
                      owner = "CGNS";
                      repo = "CGNS";
                      tag = "v4.5.0";
                      hash = "sha256-lPbXIC+O4hTtacxUcyNjZUWpEwo081MjEWhfIH3MWus=";
                    };
                    # nixpkgs carries a loongarch64 crash fix written against
                    # the 4.5.1 tree; drop it for 4.5.0.
                    patches = [ ];
                  });

                  python311 = prev.python311.override {
                    packageOverrides = pfinal: pprev: {
                      # numpy < 2 is required by the analysis stack. numpy_1 is
                      # already 1.26.4 in the pin, so alias it as the set's numpy
                      # so every downstream package resolves to 1.26.4.
                      numpy = pprev.numpy_1;

                      # scipy pinned to 1.15.*, the last series supporting
                      # numpy 1.26 at runtime.
                      scipy = pprev.scipy.overridePythonAttrs (old: rec {
                        version = "1.15.3";
                        src = prev.fetchPypi {
                          pname = "scipy";
                          inherit version;
                          hash = "sha256-6uPPUivH32S0LK05Jch24bC2w1wTN8k+EsDzZvVbDq8=";
                        };
                        patches = [ ]; # 1.17.1 patches do not apply to 1.15.3
                        # 1.15.3's pyproject pins numpy "<2.5" where 1.17.1
                        # pins "<2.7"; retarget the substituteInPlace pattern
                        # so --replace-fail finds it (Darwin part unchanged).
                        # Also drop the pre-emptive build-tool caps (pypa build
                        # enforces build-system.requires even without
                        # isolation, and the pin ships Cython 3.2 / pybind11
                        # 3.0 / pythran 0.18); scipy's own meson checks only
                        # enforce the lower bounds.
                        postPatch =
                          builtins.replaceStrings [ "numpy>=2.0.0,<2.7" ] [ "numpy>=2.0.0,<2.5" ] old.postPatch
                          + ''
                            substituteInPlace pyproject.toml \
                              --replace-fail "Cython>=3.0.8,<3.1.0" "Cython>=3.0.8" \
                              --replace-fail "pybind11>=2.13.2,<2.14.0" "pybind11>=2.13.2" \
                              --replace-fail "pythran>=0.14.0,<0.18.0" "pythran>=0.14.0"
                          '';
                        # use-system-libraries only exists in scipy >= 1.16;
                        # the 1.15.3 sdist builds its vendored copies instead.
                        mesonFlags = builtins.filter (flag: flag != "-Duse-system-libraries=all") old.mesonFlags;
                        doCheck = false;
                      });

                      # sphinx sits in the build closure of most packages
                      # (pip's man/doc build, sphinxHook), which kills eval of
                      # the whole 3.11 set: the pinned 9.1 declares Python >=
                      # 3.12 and uses PEP 695 syntax, so it cannot even import
                      # on 3.11. Pin 8.2.*, the last series supporting 3.11,
                      # and skip the runtime-deps metadata check (8.2 caps
                      # docutils <0.22 while the pin ships newer).
                      sphinx = pprev.sphinx.overridePythonAttrs (old: rec {
                        version = "8.2.3";
                        src = prev.fetchPypi {
                          pname = "sphinx";
                          inherit version;
                          hash = "sha256-OYrSne5/Y6dYiDFOlCTUD1LOWmqHrojnBx6Aryluw0g=";
                        };
                        disabled = false;
                        dontCheckRuntimeDeps = true;
                        # the 9.1 test selection does not apply to 8.2
                        doCheck = false;
                      });

                      # the pinned 3.10.2 declares sphinx >= 9.1; 3.2.0 is the
                      # release line matched to sphinx 8.2.
                      sphinx-autodoc-typehints = pprev.sphinx-autodoc-typehints.overridePythonAttrs (old: rec {
                        version = "3.2.0";
                        src = prev.fetchPypi {
                          pname = "sphinx_autodoc_typehints";
                          inherit version;
                          hash = "sha256-EHrJi8i0g3ICyIwHNtWdbaRAduZaDX19VDp4Yx9mKps=";
                        };
                      });

                      # tornado's timing-sensitive tests (request timeout,
                      # linear-performance assertions) flake under parallel
                      # build load; 3.11 builds from source, so skip them.
                      tornado = pprev.tornado.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # narwhals' test suite drags in sqlframe ->
                      # pytest-postgresql -> mirakuru, whose sandbox-hostile
                      # timing tests fail. Skipping it prunes that subtree.
                      narwhals = pprev.narwhals.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # folium's test suite drags in the geo/array stack
                      # (geopandas, xarray -> rtree, numba, zarr, numcodecs),
                      # several of which build-require numpy >= 2 and cannot
                      # build under the numpy-1 pin. Skipping checks prunes
                      # that whole subtree; folium's runtime deps are pure
                      # python (branca, jinja2, requests, xyzservices).
                      folium = pprev.folium.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # netcdf4 build-requires numpy >= 2 only to emit
                      # numpy-2-ABI wheels; compiling against the pinned
                      # numpy 1.26 is fine for a numpy-1 runtime.
                      netcdf4 = pprev.netcdf4.overridePythonAttrs (old: {
                        postPatch = (old.postPatch or "") + ''
                          substituteInPlace pyproject.toml \
                            --replace-fail "numpy>=2.0.0rc1" "numpy"
                        '';
                      });

                      # sh (python-dotenv test dependency) has a deadlock-
                      # timeout test that flakes in the build sandbox.
                      sh = pprev.sh.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # psygnal's throttler/debounce tests are timing-
                      # sensitive and flake under parallel build load.
                      psygnal = pprev.psygnal.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # uvloop's event-loop deadline and process-stdio tests
                      # assert wall-clock bounds that flake under build load.
                      uvloop = pprev.uvloop.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # python-utils' async batcher tests race 80 ms delays
                      # against 100 ms intervals; flakes under build load.
                      python-utils = pprev.python-utils.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # twisted's reactor tests hit their 120 s watchdog under
                      # build load (10-minute suite, 11k tests).
                      twisted = pprev.twisted.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # dunamai (poetry-dynamic-versioning backend) asserts a
                      # git commit is < 60 s old; slow sandboxed builds exceed
                      # that window.
                      dunamai = pprev.dunamai.overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # pybind11 (scipy/pillow/contourpy build dependency)
                      # fails its multiprocess GIL tests in the sandbox.
                      # buildTests = false skips compiling the suite, but the
                      # derivation still runs `ninja check` unless doCheck is
                      # also off — without the target, ninja errors out.
                      pybind11 = (pprev.pybind11.override { buildTests = false; }).overridePythonAttrs (old: {
                        doCheck = false;
                      });

                      # >= 2.0 exposes colormaps as module attributes (tc.rainbow_PuBr),
                      # which the ShipRes plotting scripts use.
                      tol-colors = pfinal.buildPythonPackage {
                        pname = "tol-colors";
                        version = "2.2.0";
                        format = "wheel";
                        src = prev.fetchurl {
                          url = "https://files.pythonhosted.org/packages/py3/t/tol_colors/tol_colors-2.2.0-py3-none-any.whl";
                          hash = "sha256-+aE++73JRp7nOktJfC57Ks1+Nq14z6WiJ8FYmCaudPU=";
                        };
                        dependencies = with pfinal; [
                          numpy
                          matplotlib
                        ];
                      };
                      # pretty plot settings
                      niceplots = pfinal.buildPythonPackage {
                        pname = "niceplots";
                        version = "2.6.2";
                        format = "wheel";
                        src = prev.fetchurl {
                          url = "https://files.pythonhosted.org/packages/py3/n/niceplots/niceplots-2.6.2-py3-none-any.whl";
                          hash = "sha256-UozwuRKrYwcKdhdAfOfhsDHLjrlYgEvzrLCi+L5BQRY=";
                        };
                        dependencies = with pfinal; [
                          matplotlib
                          scipy
                        ];
                        doCheck = false;
                      };
                      swig4 = pfinal.buildPythonPackage {
                        pname = "swig";
                        version = "4.4.1";
                        format = "wheel";
                        # per-arch manylinux wheels; the lookup only evaluates on
                        # Linux because swig4 is instantiated solely as a build
                        # dep of pyoptsparse, whose meta.platforms is Linux-only.
                        src =
                          prev.fetchurl
                            {
                              x86_64-linux = {
                                url = "https://files.pythonhosted.org/packages/py3/s/swig/swig-4.4.1-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.whl";
                                hash = "sha256-rj2iv2eaTJQqLBAHiTldTRZ+fagoYBgSTkZl9e/0PjE=";
                              };
                              aarch64-linux = {
                                url = "https://files.pythonhosted.org/packages/c0/4d/860e5475fe38b9c7dc36f61d0c370a62b6cc725d2bd11ada1d22a60ff5f7/swig-4.4.1-py3-none-manylinux2014_aarch64.manylinux_2_17_aarch64.whl";
                                hash = "sha256-Ug/eiAW0d17zgUV2kpuMRNZmIgsG2NpiXykhkvnnT+g=";
                              };
                            }
                            .${prev.stdenv.hostPlatform.system};
                        nativeBuildInputs = [ prev.autoPatchelfHook ];
                        buildInputs = [ prev.stdenv.cc.cc.lib ];
                        doCheck = false;
                        meta.platforms = [
                          "x86_64-linux"
                          "aarch64-linux"
                        ];
                      };
                      # ===============================================
                      #  MDO Packages
                      # ===============================================
                      # the pinned pygeo (feat/ship) declares >= 1.9
                      mdolab-baseclasses = pfinal.buildPythonPackage {
                        pname = "mdolab-baseclasses";
                        version = "1.9.0";
                        format = "wheel";
                        src = prev.fetchurl {
                          url = "https://files.pythonhosted.org/packages/py3/m/mdolab_baseclasses/mdolab_baseclasses-1.9.0-py3-none-any.whl";
                          hash = "sha256-UEb5y8r9BCTrZcjzPFUPzGx4dafB6GotmfgNIeLseFw=";
                        };
                        dependencies = with pfinal; [
                          numpy
                          packaging
                        ];
                      };
                      # multi condition package
                      multipoint = pfinal.buildPythonPackage {
                        pname = "multipoint";
                        version = "1.4.2";
                        src = prev.fetchFromGitHub {
                          owner = "mdolab";
                          repo = "multipoint";
                          tag = "v1.4.2";
                          hash = "sha256-tbM+WTC+h2KwIMvrqzPr7b4XV+HvqscXfph66Wa6J9E=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        dependencies = with pfinal; [
                          numpy
                          mpi4py
                          mdolab-baseclasses
                        ];
                        doCheck = false; # tests need pyoptsparse + a live MPI launcher
                      };
                      pyoptsparse =
                        let
                          snoptSource = prev.requireFile {
                            name = "snopt7.7.7.zip";
                            hash = "sha256-G/oeBF6dndJBX09e0D+WFlnNRa+ylXFsV4kD5aWRxGs=";
                            message = ''
                              SNOPT is licensed and cannot be downloaded. Add the distribution zip with:
                                nix-store --add-fixed sha256 /path/to/snopt7.7.7.zip
                              or set enableSnopt = false in flake.nix to build pyoptsparse without it.
                            '';
                          };
                        in
                        pfinal.buildPythonPackage {
                          pname = "pyoptsparse";
                          version = "2.14.2";
                          src = prev.fetchFromGitHub {
                            owner = "mdolab";
                            repo = "pyoptsparse";
                            tag = "v2.14.2";
                            hash = "sha256-92M5G5F1BtaiYVUNO8zyCMpBwEQHYR8h/YQNSV9Cbnw=";
                          };
                          pyproject = true;
                          # like netcdf4 above: upstream build-requires numpy >= 2
                          # only to emit numpy-2-ABI wheels; compiling against the
                          # pinned numpy 1.26 is fine for a numpy-1 runtime.
                          postPatch = ''
                            substituteInPlace pyproject.toml \
                              --replace-fail "numpy>=2.0" "numpy"
                          ''
                          + lib.optionalString enableSnopt ''
                            # meson only builds the snopt module when the licensed sources are present
                            unzip -j ${snoptSource} 'snopt7/src/*.f' -d pyoptsparse/pySNOPT/source
                            # the file-collection helper has a /usr/bin/env shebang, which the sandbox lacks
                            patchShebangs pyoptsparse/pySNOPT/source/grab-all-fortran-files.py
                          '';
                          build-system = with pfinal; [
                            meson-python
                            setuptools
                            swig4
                            ninja
                          ];
                          dontUseMesonConfigure = true;
                          nativeBuildInputs = [
                            prev.gfortran
                            prev.ninja
                            prev.pkg-config
                            prev.swig
                          ]
                          ++ lib.optional enableSnopt prev.unzip;
                          dependencies = with pfinal; [
                            numpy
                            scipy
                            sqlitedict
                            mdolab-baseclasses
                          ];
                          doCheck = false;
                          meta.platforms = [
                            "x86_64-linux"
                            "aarch64-linux"
                          ];
                        };
                      # spline package
                      pyspline = pfinal.buildPythonPackage {
                        pname = "pyspline";
                        version = "1.5.4";
                        src = prev.fetchFromGitHub {
                          owner = "mdolab";
                          repo = "pyspline";
                          tag = "v1.5.4";
                          hash = "sha256-7YG1T0u3rYZIWrNBBF5/viWAP1vhvxC7zbmtsjcFFyU=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        # numpy here (not just in dependencies) puts bin/f2py on
                        # the build PATH for the Makefile's wrapper-gen step.
                        nativeBuildInputs = [
                          prev.gfortran
                          pfinal.numpy
                        ];
                        # mdolab Makefile build: stage the gfortran config, then
                        # compile the f2py extension (.so) into pyspline/ so that
                        # setuptools' package_data ("*.so") ships it in the wheel.
                        # Serial make: the Makefile compiles adtProjections.F90
                        # alongside precision.f90 without declaring its
                        # dependency on precision.mod, so -j races.
                        preBuild = ''
                          cp config/defaults/config.LINUX_GFORTRAN.mk config/config.mk
                          make
                        '';
                        dependencies = with pfinal; [
                          numpy
                          scipy
                        ];
                        doCheck = false;
                        meta.platforms = [
                          "x86_64-linux"
                          "aarch64-linux"
                        ];
                      };
                      # pure python, but pyspline (fortran) limits it to linux
                      prefoil = pfinal.buildPythonPackage {
                        pname = "prefoil";
                        version = "2.0.2";
                        src = prev.fetchFromGitHub {
                          owner = "mdolab";
                          repo = "prefoil";
                          tag = "v2.0.2";
                          hash = "sha256-q8Mj0K+sSZ6+y64amdgqHNwR5HA2s3kBOUYtXNc7MWk=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        dependencies = with pfinal; [
                          numpy
                          scipy
                          pyspline
                        ];
                        doCheck = false;
                        meta.platforms = [
                          "x86_64-linux"
                          "aarch64-linux"
                        ];
                      };
                      # vendored mdolab/postprocessing (TecplotFileParser etc.), pure python.
                      # Lives in this repo, so the directory must be git-tracked for the
                      # flake to see it.
                      postprocessing = pfinal.buildPythonPackage {
                        pname = "postprocessing";
                        version = "1.2.0";
                        src = ./src/Util/postprocessing;
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        dependencies = with pfinal; [
                          numpy
                          matplotlib
                        ];
                        doCheck = false; # tests shell out to CLI scripts and need parameterized
                      };
                      pygeo = pfinal.buildPythonPackage {
                        pname = "pygeo";
                        # "/" is not allowed in a store path name, so the branch
                        # is spelled with a dash
                        version = "1.16.0-feat-ship";
                        src = prev.fetchFromGitHub {
                          owner = "mdolab";
                          repo = "pygeo";
                          # gwn-saronic/pygeo feat/ship head, open as mdolab/pygeo PR #291
                          rev = "c42804fb199e0c9382be3a1d7a236f01a365d2f7";
                          hash = "sha256-0zfkUlI2P1R5zambS9UCoH27K+LCghLUz6uKdyzp1kI=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        dependencies = with pfinal; [
                          numpy
                          scipy
                          mpi4py
                          packaging
                          pyspline
                          mdolab-baseclasses
                        ];
                        doCheck = false;
                        meta.platforms = [
                          "x86_64-linux"
                          "aarch64-linux"
                        ];
                      };
                      # mdolab Makefile build like pyspline; links only CGNS
                      # (plain gcc/gfortran, no MPI wrappers, no PETSc).
                      cgnsutilities = pfinal.buildPythonPackage {
                        pname = "cgnsutilities";
                        version = "2.9.0";
                        src = prev.fetchFromGitHub {
                          owner = "mdolab";
                          repo = "cgnsutilities";
                          tag = "v2.9.0";
                          hash = "sha256-ep5kJFobKqb9eGgn9NdQEtR0Y2arRMO4HCHLzJhPANg=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        # numpy here (not just in dependencies) puts bin/f2py on
                        # the build PATH for the Makefile's wrapper-gen step.
                        nativeBuildInputs = [
                          prev.gfortran
                          pfinal.numpy
                        ];
                        buildInputs = [ final.cgns ];
                        preBuild = ''
                          export CGNS_HOME=${final.cgns}
                          cp config/defaults/config.LINUX_GFORTRAN.mk config/config.mk
                          make
                        '';
                        dependencies = with pfinal; [
                          numpy
                          scipy
                        ];
                        doCheck = false;
                        meta.platforms = [
                          "x86_64-linux"
                          "aarch64-linux"
                        ];
                      };
                      # hyperbolic volume-mesh extrusion; mdolab Makefile build
                      # like adflow (mpifort/mpicc against PETSc + CGNS).
                      pyhyp = pfinal.buildPythonPackage {
                        pname = "pyhyp";
                        version = "2.6.3";
                        src = prev.fetchFromGitHub {
                          owner = "mdolab";
                          repo = "pyhyp";
                          tag = "v2.6.3";
                          hash = "sha256-P2odDLBwsZLQp1+Mr7O9czzgWkMyZHHArT/JJGJmK7U=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        # numpy here (not just in dependencies) puts bin/f2py on
                        # the build PATH for the Makefile's wrapper-gen step;
                        # mpi provides the mpifort/mpicc wrappers the config
                        # expects, which resolve gfortran from PATH.
                        nativeBuildInputs = [
                          prev.gfortran
                          prev.mpi
                          pfinal.numpy
                        ];
                        buildInputs = [
                          final.petscForAdflow
                          final.cgns
                        ];
                        # The config locates PETSc/CGNS through these env vars
                        # (PETSC_ARCH empty = prefix install).
                        preBuild = ''
                          export PETSC_DIR=${final.petscForAdflow} PETSC_ARCH="" CGNS_HOME=${final.cgns}
                          cp config/defaults/config.LINUX_GFORTRAN.mk config/config.mk
                          make
                        '';
                        dependencies = with pfinal; [
                          numpy
                          mpi4py
                          mdolab-baseclasses
                          cgnsutilities
                          tabulate
                        ];
                        doCheck = false;
                        meta.platforms = [
                          "x86_64-linux"
                          "aarch64-linux"
                        ];
                      };
                      # RANS CFD solver with adjoint
                      adflow = pfinal.buildPythonPackage {
                        pname = "adflow";
                        version = "2.13.1";
                        src = prev.fetchFromGitHub {
                          owner = "mdolab";
                          repo = "adflow";
                          tag = "v2.13.1";
                          hash = "sha256-meHwfm0m78EuoKkg2GSnRRfa1gc2in6g138Ha75aGy4=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        # numpy here (not just in dependencies) puts bin/f2py on
                        # the build PATH for the Makefile's wrapper-gen step;
                        # mpi provides the mpifort/mpicc wrappers the config
                        # expects, which resolve gfortran from PATH.
                        nativeBuildInputs = [
                          prev.gfortran
                          prev.mpi
                          pfinal.numpy
                        ];
                        buildInputs = [
                          final.petscForAdflow
                          final.cgns
                        ];
                        # mdolab Makefile build like pyspline: stage the gfortran
                        # config, then compile the f2py extension (.so) into
                        # adflow/ so that setuptools' package_data ("*.so") ships
                        # it in the wheel. The config locates PETSc/CGNS through
                        # these env vars (PETSC_ARCH empty = prefix install).
                        # -march=native is impure and poisons binary-cache
                        # sharing across machines, so strip it.
                        preBuild = ''
                          export PETSC_DIR=${final.petscForAdflow} PETSC_ARCH="" CGNS_HOME=${final.cgns}
                          cp config/defaults/config.LINUX_GFORTRAN.mk config/config.mk
                          substituteInPlace config/config.mk --replace-fail " -march=native" ""
                          make
                        '';
                        dependencies = with pfinal; [
                          numpy
                          scipy
                          mpi4py
                          mdolab-baseclasses
                        ];
                        doCheck = false;
                        meta.platforms = [
                          "x86_64-linux"
                          "aarch64-linux"
                        ];
                      };
                      # inverse distance weighted mesh warper
                      idwarp = pfinal.buildPythonPackage {
                        pname = "idwarp";
                        version = "2.6.4";
                        src = prev.fetchFromGitHub {
                          owner = "mdolab";
                          repo = "idwarp";
                          tag = "v2.6.4";
                          hash = "sha256-1WPFMyqZDfRt79b21QLYAO3vnLjMDoZ/vOSpO2Ggr20=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        # numpy here (not just in dependencies) puts bin/f2py on
                        # the build PATH for the Makefile's wrapper-gen step;
                        # mpi provides the mpifort/mpicc wrappers the config
                        # expects, which resolve gfortran from PATH.
                        nativeBuildInputs = [
                          prev.gfortran
                          prev.mpi
                          pfinal.numpy
                        ];
                        buildInputs = [
                          final.petscForAdflow
                          final.cgns
                        ];
                        # mdolab Makefile build like pyspline: stage the gfortran
                        # config, then compile the f2py extension (.so) into
                        # idwarp/ so that setuptools' package_data ("*.so") ships
                        # it in the wheel. The config locates PETSc/CGNS through
                        # these env vars (PETSC_ARCH empty = prefix install).
                        # Unlike adflow's, idwarp's config has no -march=native
                        # to strip.
                        preBuild = ''
                          export PETSC_DIR=${final.petscForAdflow} PETSC_ARCH="" CGNS_HOME=${final.cgns}
                          cp config/defaults/config.LINUX_GFORTRAN.mk config/config.mk
                          make
                        '';
                        dependencies = with pfinal; [
                          numpy
                          mpi4py
                          mdolab-baseclasses
                        ];
                        doCheck = false;
                        meta.platforms = [
                          "x86_64-linux"
                          "aarch64-linux"
                        ];
                      };
                      # OpenMDAO's test runner, used by CI for hull-form-dev
                      # tests; not packaged in nixpkgs.
                      testflo = pfinal.buildPythonPackage {
                        pname = "testflo";
                        version = "1.4.22";
                        format = "wheel";
                        src = prev.fetchurl {
                          url = "https://files.pythonhosted.org/packages/py2.py3/t/testflo/testflo-1.4.22-py2.py3-none-any.whl";
                          hash = "sha256-MEzu6J3plGoWgcS6TpVTw3Rx7fSkbQiIYs2qpyvPSNQ=";
                        };
                        dependencies = [ pfinal.coverage ];
                      };
                      # ===============================================
                      #  ShipD (Saronic fork) + Julia bridge
                      # ===============================================
                      # Julia installer/environment manager used by juliacall;
                      # not in nixpkgs.
                      juliapkg = pfinal.buildPythonPackage {
                        pname = "juliapkg";
                        version = "0.1.26";
                        format = "wheel";
                        src = prev.fetchurl {
                          url = "https://files.pythonhosted.org/packages/fb/58/82e005defc459a31b1a6583c7fefaa69340d42bb98bf1ced13b972ff3e86/juliapkg-0.1.26-py3-none-any.whl";
                          hash = "sha256-v41ZEOtqvH23uJn8IfknJzBwjgONWKdha9BCD+HN+cw=";
                        };
                        dependencies = with pfinal; [
                          filelock
                          semver
                          tomli
                          tomlkit
                        ];
                      };
                      # Python side of PythonCall.jl; not in nixpkgs.
                      juliacall = pfinal.buildPythonPackage {
                        pname = "juliacall";
                        version = "0.9.35";
                        format = "wheel";
                        src = prev.fetchurl {
                          url = "https://files.pythonhosted.org/packages/10/3b/ce7b39f8572f78f8946380e7cf53477f8cffbb8085e49fc54ad34124cc62/juliacall-0.9.35-py3-none-any.whl";
                          hash = "sha256-/VjnhYsSqOGqRPn57q6gX/gCndmhnZhSGlRRypTy+Bo=";
                        };
                        dependencies = [ pfinal.juliapkg ];
                      };
                      # Saronic fork of the MIT DeCoDE ShipD hull dataset /
                      # parameterization, with Michell + hydrostatics in Julia.
                      # No tags upstream, so pin by commit.
                      shipd = pfinal.buildPythonPackage rec {
                        pname = "shipd";
                        version = "0.0.1";
                        src = prev.fetchFromGitHub {
                          owner = "gwn-saronic";
                          repo = "ShipD";
                          rev = "22935b5d39a8da5d117ab0d743acf1bf4dd83af0";
                          hash = "sha256-9yMPji3oPuOiubQbFpVgMZz2YLfKIKVqA8yiaOSdv3w=";
                        };
                        pyproject = true;
                        build-system = [ pfinal.setuptools ];
                        # setup.py only declares numpy, but the code also
                        # imports matplotlib and stl (numpy-stl).
                        dependencies = with pfinal; [
                          numpy
                          matplotlib
                          numpy-stl
                          juliacall
                        ];
                        postPatch = ''
                          # shipdjl2py resolves the .jl sources relative to the
                          # repo root, which doesn't exist under site-packages;
                          # point it at the store copy of the source tree.
                          substituteInPlace shipd/shipdjl2py.py \
                            --replace-fail 'f"{Path(__file__).parent.parent}/src/"' '"${src}/src/"'
                          # Julia deps mirror Project.toml [deps]; juliapkg
                          # finds this file in site-packages and resolves them
                          # on first import (replaces setup_juliapkg.py).
                          cat > shipd/juliapkg.json <<'JSON'
                          {
                            "julia": "1.11",
                            "packages": {
                              "ChainRulesCore": { "uuid": "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4" },
                              "FiniteDifferences": { "uuid": "26cc04aa-876d-5657-8c51-4c34ba976000" },
                              "ForwardDiff": { "uuid": "f6369f11-7733-5829-9624-2563aa707210" },
                              "Plots": { "uuid": "91a5bcdd-55d7-5caf-9e0b-520d859cae80" },
                              "ReverseDiff": { "uuid": "37e2e3b7-166d-5795-8a7a-e32c996b4267" }
                            }
                          }
                          JSON
                          # setup.py passes no package_data, so ship
                          # juliapkg.json via setup.cfg (setuptools merges).
                          cat > setup.cfg <<'CFG'
                          [options.package_data]
                          shipd = juliapkg.json
                          CFG
                        '';
                        doCheck = false; # tests/ are Julia tests, run via Pkg
                      };
                    };
                  };
                })
              ];
            };
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = pkgs.mkShellNoCC {
            packages = [
              (pkgs.python311.withPackages (
                ps:
                builtins.filter (p: lib.meta.availableOn pkgs.stdenv.hostPlatform p) (
                  with ps;
                  [
                    adflow
                    boto3
                    cgnsutilities
                    # pyoptsparse >= 2.10 drives IPOPT through cyipopt rather
                    # than its own compiled wrapper; nixpkgs' ipopt ships with
                    # MUMPS and SPRAL linear solvers.
                    cyipopt
                    folium
                    idwarp
                    matplotlib
                    mdolab-baseclasses
                    mpi4py
                    multipoint
                    niceplots
                    numpy
                    numpy-financial
                    pandas
                    pip
                    postprocessing # pip install from armada/hull-form-dev/src/Util folder
                    prefoil
                    pygeo
                    pyhyp
                    pyoptsparse
                    pyspline
                    scipy
                    shipd
                    tabulate
                    testflo
                    tol-colors
                    zstandard
                  ]
                )
              ))
              pkgs.texliveFull
            ]
            # juliapkg's auto-downloaded Julia binary can't run on NixOS, so
            # put a nix-built julia on PATH for it to find (shipd's
            # juliapkg.json requires >= 1.11).
            ++ lib.optionals (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.julia) [
              pkgs.julia
            ];

            shellHook = ''
              # Auto-activate venv if one exists
              if [ -f .venv/bin/activate ]; then
                source .venv/bin/activate
              fi

              echo ""
              echo "hull-form-dev shell (pinned MDO stack)"
              echo "  Python: $(python --version 2>&1 | cut -d' ' -f2)"
              echo "  SNOPT:  ${if enableSnopt then "enabled" else "disabled (enableSnopt = false)"}"
              echo "  TeX:    $(xelatex --version 2>&1 | head -n 1)"
              echo ""
            '';
          };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);
    };
}

