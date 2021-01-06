Cotel provides a desktop GUI for exploration of CoAP messaging. The current release is v0.3, which includes these features:

* [Client requests](doc/snap-request.png)
* [PSK security](doc/snap-setup.png)
* [Networking log](doc/snap-netlog.png)
* [Experimental server for testing](doc/snap-server.png)

See the screenshots in the links above.

Cotel runs as a native executable. We have created an AppImage based installer for Linux, available from the [Releases](https://github.com/kb2ma/cotel/releases) page for the repository.

Of course you also may build and run from source. See *Development* below. We have not attempted to build for Windows or OSX.

Cotel uses [libcoap](https://libcoap.net/) for CoAP messaging, and [Dear ImGui](https://github.com/ocornut/imgui) for its UI library.

# Installation

The AppImage installer for Linux is a single file. Simply mark it executable and run it. AppImage is designed to be agnostic to a user's particular distro. It's also possible to integrate Cotel into the desktop environment. See the AppImage [Running](https://docs.appimage.org/user-guide/run-appimages.html) page for details.

See Cotel's user documentation for how to use it.

# Development

Required elements:

|Name   |Notes
|-----------|---------|
|libcoap| Use commit 1739507 of the library, from 2020-08. At time of writing, v4.2.1 from 2019-11 is the most recent tag, but we need the more recent commit.|
|Nim    | Use v1.4.2 of the language, or higher. See [install page](https://nim-lang.org/install.html).|
|imgui   | Nim module for GUI. Use v1.78 or higher. We currently build with v1.79. Also requires the shared library for cimgui. See details below.|
|parsetoml| Nim module to read TOML configuration file. v0.5.0|
|tempfile| Nim module to create temporary directory for logging. v0.1.7|

### libcoap
You must build libcoap from source for development, using either autotools or CMake. See [BUILDING](https://github.com/obgm/libcoap/blob/1739507a1eee6f8831ca7221adaa8d5413527b7f/BUILDING). libcoap supports several TLS libraries. We have tested only with [TinyDTLS](https://github.com/eclipse/tinydtls), which may be installed as a submodule of libcoap, as described in the build instructions.

### Nim

For Nim I find it easiest to install from the *choosenim* utility, as described on the Nim install page. For Nim modules, I use the *Nimble* installer, which is bundled with Nim.

### imgui

[imgui](https://github.com/nimgl/imgui) is the Nim binding module for the [Dear ImGui](https://github.com/ocornut/imgui) GUI library. See the imgui module [README.md](https://github.com/nimgl/imgui/blob/master/README.md) for installation.

In addition, you must compile the *cimgui* shared library, which provides a C interface to Dear ImGui, which itself is written in C++. The imgui module includes the required source. Simply run `make` in the imgui module `src/imgui/private/cimgui` directory.

Finally, make the cimgui library library visible to the generated Cotel executable -- via either copy/symlink to the same directory or with `ldconfig`.

## Building
To build Cotel, execute the command below from the top level directory. The compiled executable will be available in the `build/bin` directory.

```
   $ nim build src/gui
```

## Running
Install the generated `cotel` executable, the `cotel.conf` configuration file, and the `cimgui.so` shared library into a directory. Start Cotel in development mode with:

```
   $ ./cotel --dev
```

In development mode, all resources are in the startup directory. `cotel.conf` is generated with reasonable property defaults, but please review its contents for specifics.

## Hacking
If you'd like to make improvements to Cotel, see the [architecture](./doc/architecture.md) document to get started.