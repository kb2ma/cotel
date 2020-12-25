## Application main and GUI for Cotel libcoap server and client.
##
## For the back end, uses [conet](conet.html) for CoAP neworking. Uses
## [gui_util](gui_util.html) to read configuration file.
##
## For the UI, uses:
##
##  * [gui_client](gui_client.html) for client request
##  * [gui_local_server](gui_local_server.html) for local server setup
##  * [gui_netlog](gui_netlog.html) for network log
##
## # Conet - GUI Communication
## Conet operates in its own thread to manage network communication. It
## communicates with the GUI via two channels, ctxChan and netChan. The use of
## channels simplies the application by synchronizing memory access across
## threads.
##
## # Application State Setup and Maintenance
## In general, state is initialized from configuration file properties. A
## window may allow modification of a property, like NoSec port. If a property
## is only useful to the GUI, then a window likely maintains the value of the
## property.
## 
## If a property is relevant to Conet networking, then the conet module
## maintains it. For example several properties of the local server, including
## NoSec port, may by modified by the gui_local_server window. However, these
## properties are passed to the conet module to implement and maintain via a
## ServerConfig object.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui, imgui/[impl_opengl, impl_glfw], nimgl/[opengl, glfw]
import json, logging, tables, threadpool, parseOpt, std/jsonutils
import conet, gui_client, gui_local_server, gui_netlog, gui_util

# Disables these warnings for gui_... module imports above. The modules actually
# *are* used, but code that generates this warning does not realize that.
{.warning[UnusedImport]:off.}

const TICK_FREQUENCY = 30
  ## For tick event, approx 0.5 sec based on main loop frequency of 60 Hz

var fixedFont: ptr ImFont

proc checkNetChannel() =
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    case msgTuple.msg.token
    of "local_server.open":
      gui_local_server.setConfig(jsonTo(parseJson(msgTuple.msg.payload),
                                 ServerConfig))
    of "local_server.update":
      if msgTuple.msg.subject == "config.server.RESP":
        # success
        gui_local_server.onConfigUpdate(jsonTo(parseJson(msgTuple.msg.payload),
                                        ServerConfig))
      elif msgTuple.msg.subject == "config.server.ERR":
        gui_local_server.onConfigError(jsonTo(parseJson(msgTuple.msg.payload),
                                        ServerConfig))
      else:
        doAssert(false, "Message not handled: " & msgTuple.msg.subject)
    else:
      if isRequestOpen:
        onNetMsgRequest(msgTuple.msg)

proc renderUi(w: GLFWWindow, width: int32, height: int32) =
  ## Renders UI windows/widgets.
  glViewport(0, 0, width, height)
  igOpenGL3NewFrame()
  igGlfwNewFrame()
  igNewFrame()

  if isRequestOpen:
    showRequestWindow(fixedFont)
  if isLocalServerOpen:
    gui_local_server.showWindow()
  if isNetlogOpen:
    showNetlogWindow()

  # Place menuing setup *below* window setup so menu can set particular window
  # options when selected. Then make first pass at displaying the window on the
  # next call to renderUI().
  if igBeginMainMenuBar():
    if igBeginMenu("CoAP"):
      igMenuItem("Client Request", nil, isRequestOpen.addr)
      if igMenuItem("Local Server", nil, isLocalServerOpen.addr):
        gui_local_server.setPendingOpen()
        ctxChan.send( CoMsg(subject: "config.server.GET",
                            token: "local_server.open") )
      igEndMenu()
    if igBeginMenu("Tools"):
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
  let serverConfig = ServerConfig(listenAddr: conf.serverAddr, nosecEnable: false,
                                  nosecPort: conf.nosecPort, secEnable: false,
                                  secPort: conf.secPort, pskKey: conf.pskKey,
                                  pskClientId: conf.pskClientId)
  spawn netLoop(serverConfig)

  # GLFW initialization
  assert glfwInit()
  glfwWindowHint(GLFWContextVersionMajor, 4)
  glfwWindowHint(GLFWContextVersionMinor, 1)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)

  let w = glfwCreateWindow(conf.windowSize[0].int32, conf.windowSize[1].int32,
                           "Cotel")
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
  fixedFont = addFontFromFileTTF(fAtlas, "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf", 16)

  # Provides default values for window from config
  gui_local_server.init(conf.pskFormat)
  gui_client.init(conf.tokenLen)

  var loopCount = 0
  while not w.windowShouldClose:
    glfwPollEvents()
    # Collect latest network data before rendering.
    checkNetChannel()

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
