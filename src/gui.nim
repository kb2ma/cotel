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
  echo("default restoreState")

method saveState(v: View) {.base.} =
  echo("default saveState")

# subviews
import gui_client, gui_server

type
  CachedViews = tuple[server: View, client: View]

var
  wnd: Window
  currentView: View
  cachedViews: CachedViews

proc checkChan() =
  ## Handle any incoming message from the conet channel
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    currentView.onChanMsg(msgTuple.msg)

proc selectView(scName: string) =
  var
    selName: string
    selView: View
    isNew = false

  currentView.saveState()

  case scName
  of "Server":
    selName = "ServerView"
    if cachedViews.server != nil:
      selView = cachedViews.server
      echo("cached server")
    else:
      cachedViews.server = View(newObjectOfClass(selName))
      selView = cachedViews.server
      isNew = true
      echo("new server")
  of "Client":
    selName = "ClientView"
    if cachedViews.client != nil:
      selView = cachedViews.client
    else:
      cachedViews.client = View(newObjectOfClass(selName))
      selView = cachedViews.client
      isNew = true
  else:
    echo("View name unknown: " & scName)
    return

  selView.init(currentView.frame)
  if not isNew:
    selView.restoreState()
    
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
      selectView(sc.segments[sc.selectedSegment])
    headerView.addSubview(sc)

    # periodically check for messages from conet channel
    discard newTimer(0.5, true, checkChan)

    # Start network I/O (see conet.nim)
    spawn netLoop()

runApplication:
    startApplication()
