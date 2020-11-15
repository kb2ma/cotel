Cotel provides a GUI for exploration of CoAP messaging.

# Development

Required elements:

|Name   |Notes
|-----------|---------|
|libcoap| Use commit 1739507 of the library, from 2020-08. At time of writing, v4.2.1 from 2019-11 is the most recent tag, but we need the more recent commit.|
|Nim    | Use v1.2.6 of the language, more recent should be OK. See [install page](https://nim-lang.org/install.html).|
|nimx   | Nim module for SDL/OpenGL based GUI. Use commit add6b39 (0.1?)|
|parsetoml| Nim module to read TOML configuration file. v0.5.0|

You must build libcoap from source for development, using either autotools or CMake. See [BUILDING](https://github.com/obgm/libcoap/blob/1739507a1eee6f8831ca7221adaa8d5413527b7f/BUILDING).

For Nim I find it easiest to install from the *choosenim* utility, as described on the Nim install page. For Nim modules, I use the *Nimble* installer, which is bundled with Nim.
