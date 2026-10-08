# Dev shell for `pip install -r requirements_linux.txt` inside ./venv and for
# running `venv/bin/python App.py` on NixOS.
# PyGObject and dbus-python ship no wheels, so pip builds their sdists and needs
# C headers/libs + gobject-introspection typelibs + a system dbus-daemon
# (dbus-python's setup probes `dbus-1 --libs` and runs dbus via dbus-run-session).
# evdev also builds from source and scans only CPATH/C_INCLUDE_PATH for headers.
# The pinned Python 3.11 matches release/linux/docker-linux.Dockerfile (3.11.15).
# PySide6 ships prebuilt manylinux wheels without RPATHs: its plugins/libs dlopen
# FHS-named system libs that NixOS keeps out of the loader path (LD_LIBRARY_PATH).
# Usage:
#   nix develop -c venv/bin/python App.py
#   nix develop -c bash -c 'source venv/bin/activate && pip install -r requirements_linux.txt'
#   nix develop            # interactive shell
#   (venv must exist: `uv venv --python 3.11 --seed venv` or `python3.11 -m venv venv`)
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs:
        let
          python = pkgs.python311;
        in
        {
          default = pkgs.mkShell {
            packages = [
              python
              pkgs.stdenv.cc

              # PyGObject build + runtime introspection
              pkgs.glib
              pkgs.gobject-introspection
              pkgs.cairo
              pkgs.pkg-config
              pkgs.libffi

              # PyGObject runtime: Gio/Gst portal capture
              pkgs.gst_all_1.gstreamer
              pkgs.gst_all_1.gst-plugins-base
              pkgs.gst_all_1.gst-plugins-good

              # pipewiresrc (libgstpipewire.so) ships in the pipewire package
              # itself, not in gst-plugins-bad; also provides libpipewire-0.3.
              pkgs.pipewire

              # dbus-python build
              pkgs.dbus
              pkgs.dbus-glib

              # evdev build: linux/input.h, linux/input-event-codes.h
              pkgs.linuxHeaders
            ];

            env = let
              gstPath = pkgs.lib.makeSearchPath "lib/gstreamer-1.0" [
                pkgs.gst_all_1.gstreamer
                pkgs.gst_all_1.gst-plugins-base
                pkgs.gst_all_1.gst-plugins-good
                pkgs.pipewire
              ];
            in {
              PYTHON = "${python}/bin/python3.11";
              # evdev's setup.py header scan only reads CPATH/C_INCLUDE_PATH (not compiler flags).
              CPATH = "${pkgs.linuxHeaders}/include";
              NIX_CFLAGS_COMPILE = "-Wno-error=incompatible-pointer-types";
              # Without this only the core plugin set is scanned: pipewiresrc
              # (pipewire pkg), videoconvert (base) and appsink are invisible.
              GST_PLUGIN_SYSTEM_PATH_1_0 = gstPath;
              LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
                glib
                dbus
                pipewire
                krb5
                libGL
                fontconfig
                freetype
                libxkbcommon
                wayland
                libx11
                libxext
                libxcb
                libxrender
                libxcb-cursor
                libxcb-image
                libxcb-keysyms
                libxcb-render-util
                libxcb-wm
              ]);
            };
          };
        });
    };
}
