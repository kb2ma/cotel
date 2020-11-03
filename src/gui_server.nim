## Server view
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ formatted_text, text_field, view ]
import times
import conet

type
  ServerState = ref object
    inText: string
  ServerView* = ref object of View
    state: ServerState

var
  inText: TextField

method onChanMsg(v: ServerView, msg: CoMsg) =
  if msg.req == "request.log":
    inText.text = now().format("H:mm:ss ") & msg.payload
    v.state.inText = inText.text

#method onShow(v: ServerView) =
#  inText.text = v.state.inText

#method onHide(v: ServerView) =
#  v.state.inText = inText.text

method init*(v: ServerView, r: Rect) =
  procCall v.View.init(r)
  v.name = "ServerView"
  if v.state == nil:
    v.state = ServerState(inText: "<not yet>")

  let inLabel = newLabel(newRect(0, 10, 70, 20))
  let inLabelText = newFormattedText("Last req:")
  inLabelText.horizontalAlignment = haRight
  inLabel.formattedText = inLabelText
  v.addSubview(inLabel)

  inText = newLabel(newRect(80, 10, 500, 20))
  inText.text = v.state.inText
  v.addSubview(inText)

registerClass(ServerView)
