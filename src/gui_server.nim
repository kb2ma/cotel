## Server view
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ formatted_text, text_field, view ]
import times
import conet

type
  ServerView* = ref object of View
    inText: TextField
    localText: TextField

  ServerState* = ref object
    # Data useful for management of CoAP server view
    view*: ServerView
    securityMode*: SecurityMode
    port*: int
    inText*: string

proc onChanMsg*(state: ServerState, msg: CoMsg) =
  if msg.req == "request.log":
    state.inText = msg.payload & " at " & now().format("H:mm:ss ")
    if state.view != nil:
      state.view.inText.text = state.inText

proc update*(v: ServerView, state: ServerState) =
  case state.securityMode
  of SECURITY_MODE_NOSEC:
    v.localText.text = "NoSec"
  of SECURITY_MODE_PSK:
    v.localText.text = "PSK"
  v.localText.text = v.localText.text & " on " & $state.port

  v.inText.text = state.inText

method init*(v: ServerView, r: Rect) =
  procCall v.View.init(r)

  # y-coordinate for current row of UI
  var rowY = 20.Coord

  let localLabel = newLabel(newRect(0, rowY, 90, 20))
  let localLabelText = newFormattedText("Endpoint:")
  localLabelText.horizontalAlignment = haRight
  localLabel.formattedText = localLabelText
  v.addSubview(localLabel)

  v.localText = newLabel(newRect(100, rowY, 200, 20))
  v.addSubview(v.localText)

  rowY += 30

  let inLabel = newLabel(newRect(0, rowY, 90, 20))
  let inLabelText = newFormattedText("Last req:")
  inLabelText.horizontalAlignment = haRight
  inLabel.formattedText = inLabelText
  v.addSubview(inLabel)

  v.inText = newLabel(newRect(100, rowY, 500, 20))
  v.addSubview(v.inText)

registerClass(ServerView)
