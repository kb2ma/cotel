Cotel provides a GUI for exploration of CoAP messaging.

# Development

Required elements:

|Name   |Notes
|-----------|---------|
|libcoap| Use commit 1739507 of the library, from 2020-08. At time of writing, v4.2.1 from 2019-11 is the most recent tag, but we need the more recent commit.|
|Nim    | Use v1.2.6 of the language, more recent should be OK. See [install page](https://nim-lang.org/install.html).|
|imgui / nimgl   | Nim modules for GUI. Also requires the shared library for cimgui. See details below.|
|parsetoml| Nim module to read TOML configuration file. v0.5.0|

### libcoap
You must build libcoap from source for development, using either autotools or CMake. See [BUILDING](https://github.com/obgm/libcoap/blob/1739507a1eee6f8831ca7221adaa8d5413527b7f/BUILDING).

### Nim

For Nim I find it easiest to install from the *choosenim* utility, as described on the Nim install page. For Nim modules, I use the *Nimble* installer, which is bundled with Nim.

### imgui / nimgl

[imgui](https://github.com/nimgl/imgui) is the Nim binding module for the [Dear ImGui](https://github.com/ocornut/imgui) GUI library. [nimgl](https://github.com/nimgl/nimgl) is a structural module required for use of Dear ImGui and other graphics libraries. See the imgui module [README.md](https://github.com/nimgl/imgui/blob/master/README.md) for installation of these modules.

In addition, you must compile the *cimgui* shared library, which provides a C interface to Dear ImGui, which itself is written in C++. The imgui module includes the required source. Simply run `make` in the imgui module `src/imgui/private/cimgui` directory.

Finally, copy the cimgui library so it is visible to the generated Cotel executable. It's easiest to simply copy it to the same directory as the executable.
