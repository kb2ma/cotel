## Cotel GUI
##
## GUI for libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ segmented_control, text_field, timer, view, window ]
import tables, threadpool, parseOpt
import conet, gui_util

# Disables these warnings for gui_... module imports above. The modules actually
# *are* used, but code that generates this warning does not realize that.
{.warning[UnusedImport]:off.}

# subviews
import gui_client, gui_server

var
  clientState = ClientState(view: nil)
  serverState = ServerState(view: nil, inText: "")

proc checkChan() =
  ## Handle any incoming message from the conet channel
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    serverState.onChanMsg(msgTuple.msg)
    if clientState.view != nil:
      clientState.onChanMsg(msgTuple.msg)

proc onSelectView(wnd: Window, scName: string) =
  ## Display the view for the selected view name. First saves the state of
  ## the current view. If the selected view already has been displayed,
  ## restore its state.
  var viewName: string
  var currentView: View

  case scName
  of "Server":
    viewName = "ServerView"
    if clientState.view != nil:
      currentView = clientState.view
    clientState.view = nil
  of "Client":
    viewName = "ClientView"
    if serverState.view != nil:
      currentView = serverState.view
    serverState.view = nil
  else:
    echo("View name unknown: " & scName)
    return

  let nv = View(newObjectOfClass(viewName))
  nv.init(newRect(0, 30, wnd.bounds.width, wnd.bounds.height - 30))
  nv.resizingMask = "wh"

  case scName
  of "Server":
    serverState.view = cast[ServerView](nv)
    serverState.view.inText.text = serverState.inText
  of "Client":
    clientState.view = cast[ClientView](nv)

  if currentView != nil:
    wnd.replaceSubview(currentView, nv)
  else:
    wnd.addSubview(nv)


proc startApplication(conf: CotelConf) =
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

  # Start network I/O (see conet.nim)
  spawn netLoop(conf.serverPort)

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

  let conf = readConfFile(confName)

  startApplication(conf)
