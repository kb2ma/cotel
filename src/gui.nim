## Application main and GUI for Cotel libcoap server and client.
##
## For the back end, uses [conet](conet.html) for CoAP neworking. Uses
## [gui_util](gui_util.html) to read configuration file.
##
## For the UI, uses [gui_client](gui_client.html) and
## [gui_server](gui_server.html) to provide those views.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui, imgui/[impl_opengl, impl_glfw]
import nimgl/[opengl, glfw]
import logging, tables, threadpool, parseOpt
import conet, gui_util

# Disables these warnings for gui_... module imports above. The modules actually
# *are* used, but code that generates this warning does not realize that.
{.warning[UnusedImport]:off.}

var isRequestOpen = false

proc showRequestWindow() =
  igSetNextWindowSize(ImVec2(x: 500, y: 440))
  if igBegin("Request", isRequestOpen.addr):
    igEnd()

proc renderScene(w: GLFWWindow, width: int32, height: int32) =
  glViewport(0, 0, width, height)
  igOpenGL3NewFrame()
  igGlfwNewFrame()
  igNewFrame()

  if isRequestOpen:
    showRequestWindow()

  if igBeginMainMenuBar():
    if igBeginMenu("Client"):
      igMenuItem("New Request", nil, isRequestOpen.addr)
      igEndMenu()
    igEndMainMenuBar()

  igRender()

  glClearColor(0.45f, 0.55f, 0.60f, 1.00f)
  glClear(GL_COLOR_BUFFER_BIT)

  igOpenGL3RenderDrawData(igGetDrawData())
  w.swapBuffers()

proc framebufferSizeCallback(w: GLFWWindow, width: int32, height: int32) {.cdecl.} =
  glfwSwapInterval(0)
  renderScene(w, width, height)
  glfwSwapInterval(1)

proc main(conf: CotelConf) =
  # Configure CoAP networking and spawn in a new thread
  let conetState = ConetState(listenAddr: conf.serverAddr,
                              serverPort: conf.serverPort,
                              securityMode: conf.securityMode,
                              pskKey: conf.pskKey, pskClientId: conf.pskClientId)
  spawn netLoop(conetState)

  # GLFW initialization
  assert glfwInit()
  glfwWindowHint(GLFWContextVersionMajor, 4)
  glfwWindowHint(GLFWContextVersionMinor, 1)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)

  let w = glfwCreateWindow(640, 480, "Cotel")
  if w == nil:
    quit(QuitFailure)
  discard setFramebufferSizeCallback(w, framebufferSizeCallback)
  w.makeContextCurrent()

  # OpenGL, ImGui (including for GLFW) initialization
  assert glInit()
  let context = igCreateContext()
  assert igGlfwInitForOpenGL(w, true)
  assert igOpenGL3Init()

  igStyleColorsClassic()

  let fAtlas = igGetIO().fonts
  discard addFontFromFileTTF(fAtlas, "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf", 16)

  while not w.windowShouldClose:
    glfwPollEvents()
    var fbWidth, fbHeight: int32
    getFramebufferSize(w, fbWidth.addr, fbHeight.addr)
    renderScene(w, fbWidth, fbHeight)

  igOpenGL3Shutdown()
  igGlfwShutdown()
  context.igDestroyContext()

  w.destroyWindow()
  glfwTerminate()


# Parse command line options.
var confName = ""
var p = initOptParser()
while true:
  p.next()
  case p.kind
  of cmdEnd: break
  of cmdShortOption, cmdLongOption:
    if p.key == "c":
      if p.val == "":
        echo("Expected configuration file name")
      else:
        confName = p.val
    else:
      echo("Option ", p.key, " not understood")
  of cmdArgument:
    echo("Argument ", p.key, " not understood")

if confName == "":
  echo("Must provide configuration file")
  quit(QuitFailure)

oplog = newFileLogger("gui.log", fmtStr="[$time] $levelname: ", bufSize=0)
try:
  main(readConfFile(confName))
except:
  oplog.log(lvlError, "App failure: ", getCurrentExceptionMsg())
  quit(QuitFailure)
