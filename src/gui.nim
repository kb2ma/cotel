## Cotel GUI
##
## GUI for libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ segmented_control, timer, view, window ]
import tables, threadpool, conet

method onChanMsg(v: View, msg: CoMsg) {.base.} =
  ## A View handles channel messages from the network. A subclass handles
  ## a message it is interested in.
  ##
  ## Must define this base method before GUI views because they are expected to
  ## override it.
  echo("checkChan msg: " & msg.req)

method restoreState(v: View) {.base.} =
  ## no action by default

method saveState(v: View) {.base.} =
  ## no action by default

# subviews
import gui_client, gui_server

var
  wnd: Window
    ## top level UI object
  currentView: View
    ## subview currently being displayed, for example server view or client view
  cachedViews = new Table[string, View]
    ## cache of displayed views, for reuse if reselected

proc checkChan() =
  ## Handle any incoming message from the conet channel
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    currentView.onChanMsg(msgTuple.msg)

proc onSelectView(scName: string) =
  ## Display the view for the selected view name. First saves the state of
  ## the current view. If the selected view already has been displayed,
  ## restore its state.
  var
    viewName: string
    selView: View

  currentView.saveState()

  case scName
  of "Server":
    viewName = "ServerView"
  of "Client":
    viewName = "ClientView"
  else:
    echo("View name unknown: " & scName)
    return

  if cachedViews.hasKey(viewName):
    selView = cachedViews[viewName]
    selView.init(currentView.frame)
    selView.restoreState()
  else:
    selView = View(newObjectOfClass(viewName))
    selView.init(currentView.frame)
    cachedViews.add(viewName, selView)

  selView.resizingMask = "wh"
  wnd.replaceSubview(currentView, selView)
  currentView = selView


proc startApplication() =
    wnd = newWindow(newRect(40, 40, 800, 600))
    wnd.title = "Cotel"
    let headerView = View.new(newRect(0, 0, wnd.bounds.width, 30))
    wnd.addSubview(headerView)

    # add an empty body view at startup
    currentView = View.new(newRect(0, 30, wnd.bounds.width,
                                   wnd.bounds.height - headerView.bounds.height))
    currentView.name = "empty"
    wnd.addSubview(currentView)

    let sc = SegmentedControl.new(newRect(10, 10, 160, 22))
    sc.segments = @["Client", "Server"]
    sc.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
    # display selected view
    sc.onAction do():
      onSelectView(sc.segments[sc.selectedSegment])
    headerView.addSubview(sc)

    # periodically check for messages from conet channel
    discard newTimer(0.5, true, checkChan)

    # Start network I/O (see conet.nim)
    spawn netLoop()

    # UI selects client in selection control, so sync the displayed view
    onSelectView("Client")

runApplication:
    startApplication()
