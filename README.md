Cotel provides a desktop GUI for exploration of CoAP messaging. The current release is v0.1, which includes these features:

* Client GET request
* Server with a simple read-only resource
* PSK security
* Display of networking log

See a [screenshot](./doc/screenshot.png) with all of the application windows open.

Cotel runs as a native executable, and is known to work on Ubuntu Linux. Presently you must build from source, as described below. It also should be possible to build for Mac and Windows, but we have not tried this yet.

Cotel uses libcoap for CoAP messaging, and Dear ImGui for its UI library.

# Development

Required elements:

|Name   |Notes
|-----------|---------|
|libcoap| Use commit 1739507 of the library, from 2020-08. At time of writing, v4.2.1 from 2019-11 is the most recent tag, but we need the more recent commit.|
|Nim    | Use v1.4.2 of the language, or higher. See [install page](https://nim-lang.org/install.html).|
|imgui   | Nim module for GUI. Use v1.78 or higher. Also requires the shared library for cimgui. See details below.|
|parsetoml| Nim module to read TOML configuration file. v0.5.0|

### libcoap
You must build libcoap from source for development, using either autotools or CMake. See [BUILDING](https://github.com/obgm/libcoap/blob/1739507a1eee6f8831ca7221adaa8d5413527b7f/BUILDING). libcoap supports several TLS libraries. We have tested only with [TinyDTLS](https://github.com/eclipse/tinydtls), which may be installed as a submodule of libcoap, as described in the build instructions.

### Nim

For Nim I find it easiest to install from the *choosenim* utility, as described on the Nim install page. For Nim modules, I use the *Nimble* installer, which is bundled with Nim.

### imgui

[imgui](https://github.com/nimgl/imgui) is the Nim binding module for the [Dear ImGui](https://github.com/ocornut/imgui) GUI library. See the imgui module [README.md](https://github.com/nimgl/imgui/blob/master/README.md) for installation.

In addition, you must compile the *cimgui* shared library, which provides a C interface to Dear ImGui, which itself is written in C++. The imgui module includes the required source. Simply run `make` in the imgui module `src/imgui/private/cimgui` directory.

Finally, copy the cimgui library so it is visible to the generated Cotel executable. It's easiest to simply copy it to the same directory as the executable.

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

`cotel.conf` uses reasonable property defaults, but please review its contents for specifics.

## Hacking
If you'd like to make improvements to Cotel, see the [architecture](./doc/architecture.md) document to get started. 