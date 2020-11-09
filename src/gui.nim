## Cotel GUI
##
## GUI for libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ segmented_control, text_field, timer, view, window ]
import logging, tables, threadpool, parseOpt
import conet, gui_util

# Disables these warnings for gui_... module imports above. The modules actually
# *are* used, but code that generates this warning does not realize that.
{.warning[UnusedImport]:off.}

# subviews
import gui_client, gui_server

var
  clientState = ClientState(view: nil)
  serverState = ServerState(view: nil, inText: "")
  activeName = ""
    ## name of the active view/state

proc checkChan() =
  ## Handle any incoming message from the conet channel
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    serverState.onChanMsg(msgTuple.msg)
    if clientState.view != nil:
      clientState.onChanMsg(msgTuple.msg)

proc onSelectView(wnd: Window, scName: string) =
  ## Activate/Display the view for the selected name.
  var activeView: View

  # First detach the currently active view. On first selection there is not an
  # active view.
  case activeName
  of "Server":
    activeView = serverState.view
    serverState.view = nil
  of "Client":
    activeView = clientState.view
    clientState.view = nil

  # create/initialize the new view
  let nv = View(newObjectOfClass(scName & "View"))
  nv.init(newRect(0, 30, wnd.bounds.width, wnd.bounds.height - 30))
  nv.resizingMask = "wh"

  case scName
  of "Server":
    serverState.view = cast[ServerView](nv)
    serverState.view.update(serverState)
  of "Client":
    clientState.view = cast[ClientView](nv)

  # display the new view
  if activeName != "":
    wnd.replaceSubview(activeView, nv)
  else:
    wnd.addSubview(nv)
  activeName = scName


proc startApplication(conf: CotelConf) =
  # Initialize state from configuraton
  serverState.securityMode = conf.securityMode
  serverState.port = conf.serverPort

  # Initialize UI
  let wnd = newWindow(newRect(40, 40, 800, 600))
  wnd.title = "Cotel"
  let headerView = View.new(newRect(0, 0, wnd.bounds.width, 30))
  wnd.addSubview(headerView)

  let sc = SegmentedControl.new(newRect(10, 10, 160, 22))
  sc.segments = @["Client", "Server"]
  sc.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  # display selected view
  sc.onAction do():
    onSelectView(wnd, sc.segments[sc.selectedSegment])
  headerView.addSubview(sc)

  # periodically check for messages from conet channel
  discard newTimer(0.5, true, checkChan)

  # Configure CoAP networking and spawn in a new thread
  let conetState = ConetState(serverPort: conf.serverPort,
                              securityMode: conf.securityMode,
                              pskKey: conf.pskKey, pskClientId: conf.pskClientId)
  spawn netLoop(conetState)

  # Show client page initially
  onSelectView(wnd, "Client")


runApplication:
  # parse command line options
  var confName = ""
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if p.key == "c":
        if p.val == "":
          echo("Expected conf file name")
        else:
          confName = p.val
      else:
        echo("Option ", p.key, " not understood")
    of cmdArgument:
      echo("Argument ", p.key, " not understood")

  if confName == "":
    echo("Must provide configuration file")
    quit(QuitFailure)
  else:
    oplog = newFileLogger("gui.log", fmtStr="[$time] $levelname: ", bufSize=0)
    try:
      startApplication(readConfFile(confName))
    except:
      echo("Configuration file error: ", getCurrentExceptionMsg())
      quit(QuitFailure)
