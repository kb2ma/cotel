## Application main and GUI for Cotel libcoap server and client.
##
## For the back end, uses [conet](conet.html) for CoAP neworking. Uses
## [gui/util](gui/util.html) to read configuration file.
##
## For the UI, uses:
##
##  * [gui/client](gui/client.html) for client request
##  * [gui/local_server](gui/local_server.html) for local server setup
##  * [gui/netlog](gui/netlog.html) for network log
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
## ConetConfig object.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui, imgui/[impl_opengl, impl_glfw], nimgl/[opengl, glfw]
import json, logging, os, tables, threadpool, parseOpt, std/jsonutils, strutils,
       tempfile
import conet, gui/[client, localhost, netlog, util]

# Disables these warnings for gui_... module imports above. The modules actually
# *are* used, but code that generates this warning does not realize that.
{.warning[UnusedImport]:off.}

const
  TICK_FREQUENCY = 30
    ## For tick event, approx 0.5 sec based on main loop frequency of 60 Hz
  VERSION = "0.3"
  CONF_FILE = "cotel.conf"
  DATA_FILE = "cotel.dat"
  GUI_LOG_FILE = "gui.log"
  NET_LOG_FILE = "net.log"

var
  appConfig: CotelConf
    ## Application configuration, initialized from disk.
  monoFont: ptr ImFont
    ## Monospaced font, maintained as a global for use in a callback as well as
    ## from main run loop.
  isInfoOpen = false
    ## Is Info window open?
  confDir: string
    ## Name of directory containing configuration files like cotel.conf,
    ## including trailing separator.
  logDir: string
    ## Name of temporary directory containing log files, including trailing
    ## separator.
  cotelData: CotelData
    ## Runtime data object
  isDevMode = false
    ## Uses local config/data files
  imguiIniFile: string
    ## Name of ImGui window data file. Must us a static variable like this to
    ## pass to ImGui. We don't know the filename until runtime.

# Font definitions embedded in source code to avoid filesystem lookup issues.
# Definitions included separately due to size.
include gui/font


proc showInfoWindow*() =
  igSetNextWindowSize(ImVec2(x: 320, y: 140), Once)
  igBegin("Info", isInfoOpen.addr,
          (ImGuiWindowFlags.NoResize.uint or ImGuiWindowFlags.NoCollapse.uint).ImGuiWindowFlags)
  let labelColWidth = 90f

  #igAlignTextToFramePadding()
  igText("Log directory")
  igSameLine(labelColWidth + 20)
  igPushStyleColor(ImGuiCol.FrameBg, childBgColor[])
  igPushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(x:0f, y:0f))
  discard igInputTextCap("##logDir", logDir, len(logDir),
                         flags = ImGuiInputTextFlags.ReadOnly)
  igPopStyleVar()
  igPopStyleColor()
  igSeparator()

  igItemSize(ImVec2(x:0,y:5))
  igTextColored(headingColor, "About Cotel")
  igText("Version")
  igSameLine(labelColWidth)
  igText(format("v$#, January 2021", VERSION))
  igText("Home")
  igSameLine(labelColWidth)
  igText("github.com/kb2ma/cotel")
  igEnd()

proc checkNetChannel() =
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    case msgTuple.msg.token
    of "local_server.open":
      localhost.setConfig(jsonTo(parseJson(msgTuple.msg.payload),
                          ConetConfig))
    of "local_server.update":
      if msgTuple.msg.subject == "config.server.RESP":
        # success
        localhost.onConfigUpdate(jsonTo(parseJson(msgTuple.msg.payload),
                                 ConetConfig))
      elif msgTuple.msg.subject == "config.server.ERR":
        localhost.onConfigError(jsonTo(parseJson(msgTuple.msg.payload),
                                ConetConfig))
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
    showRequestWindow(monoFont)
  if isLocalhostOpen:
    localhost.showWindow(monoFont)
  if isNetlogOpen:
    showNetlogWindow()
  if isInfoOpen:
    showInfoWindow()

  # Place menuing setup *below* window setup so menu can set particular window
  # options when selected. Then make first pass at displaying the window on the
  # next call to renderUI().
  if igBeginMainMenuBar():
    if igBeginMenu("CoAP"):
      igMenuItem("Send Request", nil, isRequestOpen.addr)
      igEndMenu()
    if igBeginMenu("Tools"):
      if igMenuItem("Local Setup", nil, isLocalhostOpen.addr):
        localhost.setPendingOpen(appConfig, confDir & CONF_FILE)
        ctxChan.send( CoMsg(subject: "config.server.GET",
                            token: "local_server.open") )
      igMenuItem("View Network Log", nil, isNetlogOpen.addr)
      igMenuItem("Info", nil, isInfoOpen.addr)
      igEndMenu()
    # Display dev mode indicator
    if isDevMode:
      igSameLine(120)
      igTextColored(igGetStyleColorVec4(ImGuiCol.TextDisabled)[], "(dev mode)")
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
  cotelData.windowSize = @[width.int, height.int]
  cotelData.isChanged = true
  renderUi(w, width, height)
  glfwSwapInterval(1)

proc main(conf: CotelConf) =
  let logPathname = logDir & NET_LOG_FILE
  ## Initializes and runs display loop. The display mechanism here is idiomatic
  ## for a GLFW/OpenGL3 based ImGui.
  # Init before starting networking so it shows all messages from this session.
  initNetworkLog(logPathname)

  # Configure CoAP networking and spawn in a new thread
  let conetConfig = ConetConfig(logDir: logDir, listenAddr: conf.serverAddr,
                                nosecEnable: false, nosecPort: conf.nosecPort,
                                secEnable: false, secPort: conf.secPort,
                                pskKey: conf.pskKey, pskClientId: conf.pskClientId)
  spawn netLoop(conetConfig)

  appConfig = conf

  # GLFW initialization
  assert glfwInit()
  glfwWindowHint(GLFWContextVersionMajor, 4)
  glfwWindowHint(GLFWContextVersionMinor, 1)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)

  cotelData = readDataFile(confDir & DATA_FILE)

  let w = glfwCreateWindow(cotelData.windowSize[0].int32,
                           cotelData.windowSize[1].int32, "Cotel")
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
  imguiIniFile = confDir & "gui.dat"
  io.iniFilename = imguiIniFile
  igStyleColorsClassic()
  # Make window background opaque and lighten color so not pitch black.
  let bgColor = igGetStyleColorVec4(ImGuiCol.WindowBg)
  bgColor.w = 1.0
  bgColor.x = 35/255
  bgColor.y = 35/255
  bgColor.z = 35/255

  # Initialize default proportional font and monospaced font.
  let fAtlas = io.fonts
  discard addFontFromMemoryCompressedTTF(fAtlas, unsafeAddr propFontData, 236656, 16f)
  monoFont = addFontFromMemoryCompressedTTF(fAtlas, unsafeAddr monoFontData, 150389, 16f)

  # Provides default values for window from config
  client.init(conf.tokenLen)
  util.init()

  var loopCount = 0
  while not w.windowShouldClose:
    glfwPollEvents()
    # Collect latest network data before rendering.
    checkNetChannel()

    if loopCount >= TICK_FREQUENCY:
      loopCount = 0
      checkNetworkLog(logPathname)
      if cotelData.isChanged:
        saveDataFile(confDir & DATA_FILE, cotelData)

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
var p = initOptParser()
while true:
  p.next()
  case p.kind
  of cmdEnd: break
  of cmdShortOption, cmdLongOption:
    if p.key == "dev":
      # dev mode means all resources are in the startup directory (PWD)
      isDevMode = true
      confDir = "."
      normalizePathEnd(confDir, true)
      logDir = "."
      normalizePathEnd(logDir, true)
    else:
      echo("Option ", p.key, " not understood")
  of cmdArgument:
    echo("Argument ", p.key, " not understood")

if len(confDir) == 0:
  confDir = getConfigDir() & "cotel"
  normalizePathEnd(confDir, true)
  if not dirExists(confDir):
    echo("Config directory not found: " & confDir)
    quit(QuitFailure)

if len(logDir) == 0:
  logDir = mkdtemp("cotel")
  normalizePathEnd(logDir, true)
  echo("logDir " & logDir)

oplog = newFileLogger(logDir & GUI_LOG_FILE,
                      fmtStr="[$time] $levelname: ", bufSize=0)
try:
  main(readConfFile(confDir & CONF_FILE))
except:
  oplog.log(lvlError, "App failure: ", getCurrentExceptionMsg())
  quit(QuitFailure)
