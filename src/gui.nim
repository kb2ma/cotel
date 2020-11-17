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

import nimx / [ button, image, menu, segmented_control, table_view, text_field,
                timer, view, window ]
import logging, tables, threadpool, parseOpt
import conet, gui_util

# Disables these warnings for gui_... module imports above. The modules actually
# *are* used, but code that generates this warning does not realize that.
{.warning[UnusedImport]:off.}

# subviews
import gui_client, gui_server

var
  clientState = ClientState(userCtx: nil, showsLog: false)
    ## view independent aspects of client requests
  serverState = ServerState(userCtx: nil, inText: "")
    ## view independent aspects of server handling
  activeName = ""
    ## name of the active view

proc handleTimerTick() =
  ## Timer tick from nimx. Handle any incoming message from the conet channel.
  ## Also displays additions to conet operation log in the UI.
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    serverState.onChanMsg(msgTuple.msg)
    if clientState.userCtx != nil:
      clientState.onChanMsg(msgTuple.msg)

  if clientState.userCtx != nil:
    let v = clientState.userCtx
    if v.logScroll != nil:
      # only update when client log is visible
      var f: File
      if not open(f, "net.log"):
        oplog.log(lvlError, "Unable to open net.log")
        return

      let pos = f.getFileSize()
      if pos > v.logPos:
        f.setFilePos(v.logPos)
        var lineText: string
        while true:
          if not f.readLine(lineText):
            break
          v.logLines.add(lineText)

        v.logPos = pos
        let tv = cast[TableView](v.logScroll.findSubviewWithName("logTable"))
        tv.reloadData()
      f.close()


proc onSelectView(wnd: Window, selName: string) =
  ## Activate/Display the view for the selected name.
  var activeView: View

  if activeName == selName:
    # already visible
    return

  # First detach the currently active view. On first selection there is not an
  # active view.
  case activeName
  of "Server":
    activeView = serverState.userCtx
    serverState.userCtx = nil
  of "Client":
    activeView = clientState.userCtx
    clientState.userCtx = nil

  # create/initialize the new view
  let nv = View(newObjectOfClass(selName & "View"))
  nv.init(newRect(0, 30, wnd.bounds.width, wnd.bounds.height - 30))
  nv.resizingMask = "wh"

  case selName
  of "Server":
    serverState.userCtx = cast[ServerView](nv)
    serverState.userCtx.update(serverState)
    wnd.title = "Cotel - Server"
  of "Client":
    let cv = cast[ClientView](nv)
    clientState.userCtx = cv
    cv.state = clientState
    if clientState.showsLog:
      cv.showLogView(wnd.bounds)
    wnd.title = "Cotel - Client"

  # display the new view
  if activeName != "":
    wnd.replaceSubview(activeView, nv)
  else:
    wnd.addSubview(nv)
  activeName = selName


proc startApplication(conf: CotelConf) =
  # Initialize state from configuraton
  serverState.securityMode = conf.securityMode
  serverState.listenAddr = conf.serverAddr
  serverState.port = conf.serverPort

  # Initialize UI
  let wnd = newWindow(newRect(40, 40, 800, 540))
  wnd.title = "Cotel"
  let headerView = View.new(newRect(0, 0, wnd.bounds.width, 40))
  wnd.addSubview(headerView)

  # Create menu
  let mItem = makeMenu("Cotel"):
    - "Client":
        onSelectView(wnd, "Client")
    - "Server":
        onSelectView(wnd, "Server")
    - "-"
    - "Toggle log":
        if clientState.userCtx != nil:
          if clientState.showsLog:
            hideLogView(clientState.userCtx)
          else:
            showLogView(clientState.userCtx, wnd.bounds)

  let imgBtn = newImageButton(newRect(10, 4, 32, 32))
  imgBtn.image = imageWithContentsOfFile("menu.png")
  imgBtn.onAction do():
    mItem.popupAtPoint(imgBtn, newPoint(0, 25))
  headerView.addSubview(imgBtn)

  # Periodically check for messages from conet channel
  discard newTimer(0.5, true, handleTimerTick)

  # Configure CoAP networking and spawn in a new thread
  let conetState = ConetState(listenAddr: conf.serverAddr,
                              serverPort: conf.serverPort,
                              securityMode: conf.securityMode,
                              pskKey: conf.pskKey, pskClientId: conf.pskClientId)
  spawn netLoop(conetState)

  # Show client page initially
  onSelectView(wnd, "Client")


runApplication:
  # nimx entry point. Parse command line options.
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
    startApplication(readConfFile(confName))
  except:
    oplog.log(lvlError, "App failure: ", getCurrentExceptionMsg())
    quit(QuitFailure)
