## Server view
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ formatted_text, text_field, view ]
import times
import conet

type
  ServerView* = ref object of View
    inText*: TextField
  ServerState* = ref object
    view*: ServerView
    inText*: string

proc onChanMsg*(state: ServerState, msg: CoMsg) =
  if msg.req == "request.log":
    state.inText = now().format("H:mm:ss ") & msg.payload
    if state.view != nil:
      state.view.inText.text = state.inText

proc update*(v: ServerView, state: ServerState) =
  v.inText.text = state.inText

method init*(v: ServerView, r: Rect) =
  procCall v.View.init(r)

  let inLabel = newLabel(newRect(0, 10, 70, 20))
  let inLabelText = newFormattedText("Last req:")
  inLabelText.horizontalAlignment = haRight
  inLabel.formattedText = inLabelText
  v.addSubview(inLabel)

  v.inText = newLabel(newRect(80, 10, 500, 20))
  v.addSubview(v.inText)

registerClass(ServerView)
