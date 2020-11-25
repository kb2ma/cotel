## Application main and GUI for Cotel libcoap server and client.
##
## For the back end, uses [conet](conet.html) for CoAP neworking. Uses
## [gui_util](gui_util.html) to read configuration file.
##
## For the UI, uses:
##
##  * [gui_client](gui_client.html) for client request
##  * [gui_netlog](gui_netlog.html) for network log.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui, imgui/[impl_opengl, impl_glfw]
import nimgl/[opengl, glfw]
import logging, tables, threadpool, parseOpt
import conet, gui_util, gui_client, gui_netlog

# Disables these warnings for gui_... module imports above. The modules actually
# *are* used, but code that generates this warning does not realize that.
{.warning[UnusedImport]:off.}

const TICK_FREQUENCY = 30
  ## For tick event, approx 0.5 sec based on main loop frequency of 60 Hz

proc checkNetChannel() =
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    if isRequestOpen:
      onNetMsgRequest(msgTuple.msg)

proc renderUi(w: GLFWWindow, width: int32, height: int32) =
  ## Renders UI windows/widgets.
  glViewport(0, 0, width, height)
  igOpenGL3NewFrame()
  igGlfwNewFrame()
  igNewFrame()

  if isRequestOpen:
    showRequestWindow()
  if isNetlogOpen:
    showNetlogWindow()

  if igBeginMainMenuBar():
    if igBeginMenu("Tools"):
      igMenuItem("Client Request", nil, isRequestOpen.addr)
      igMenuItem("Network Log", nil, isNetlogOpen.addr)
      igEndMenu()
    igEndMainMenuBar()

  igRender()

  glClearColor(0.45f, 0.55f, 0.60f, 1.00f)
  glClear(GL_COLOR_BUFFER_BIT)

  igOpenGL3RenderDrawData(igGetDrawData())
  w.swapBuffers()

proc framebufferSizeCallback(w: GLFWWindow, width: int32, height: int32) {.cdecl.} =
  ## Callback from GLFW that uses updated width/height of FB. Helps prevent
  ## window jumpiness when user vertically resizes OS window frame.
  glfwSwapInterval(0)
  renderUi(w, width, height)
  glfwSwapInterval(1)

proc main(conf: CotelConf) =
  ## Initializes and runs display loop. The display mechanism here is idiomatic
  ## for a GLFW/OpenGL3 based ImGui.
  # Init before starting networking so it shows all messages from this session.
  initNetworkLog()

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

  let w = glfwCreateWindow(750, 650, "Cotel")
  if w == nil:
    quit(QuitFailure)
  discard setFramebufferSizeCallback(w, framebufferSizeCallback)
  w.makeContextCurrent()

  # OpenGL, ImGui (including for GLFW) initialization
  assert glInit()
  let context = igCreateContext()
  assert igGlfwInitForOpenGL(w, true)
  assert igOpenGL3Init()
  
  let io = igGetIO()
  # Not using keyboard nav; as is it doesn't mark a listbox item as selected.
  # seems like a bug to require manual cast of NavEnableKeyboard
  #io.configFlags = (io.configFlags.int or cast[int](NavEnableKeyboard)).ImGuiConfigFlags
  igStyleColorsClassic()

  let fAtlas = io.fonts
  discard addFontFromFileTTF(fAtlas, "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf", 16)

  var loopCount = 0
  while not w.windowShouldClose:
    glfwPollEvents()
    checkNetChannel()
    # 
    if loopCount >= TICK_FREQUENCY:
      loopCount = 0
      checkNetworkLog()

    var fbWidth, fbHeight: int32
    getFramebufferSize(w, fbWidth.addr, fbHeight.addr)
    renderUi(w, fbWidth, fbHeight)
    loopCount += 1

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
