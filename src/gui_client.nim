## Client view
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ button, formatted_text, text_field, view ]
import conet

type
  ClientState = ref object
  ClientView* = ref object of View
    state: ClientState

var outText: TextField

method onChanMsg(v: ClientView, msg: CoMsg) =
  if msg.req == "response.payload":
    outText.text = msg.payload

method init*(v: ClientView, r: Rect) =
  procCall v.View.init(r)
  v.name = "ClientView"

  let outLabel = newLabel(newRect(20, 10, 35, 20))
  let outLabelText = newFormattedText("Out:")
  outLabelText.horizontalAlignment = haRight
  outLabel.formattedText = outLabelText
  v.addSubview(outLabel)

  let button = newButton(newRect(80, 10, 100, 22))
  button.title = "Send Msg"
  button.onAction do():
      ctxChan.send( CoMsg(req: "send_msg") )
  v.addSubview(button)

  outText = newLabel(newRect(60, 40, 700, 20))
  v.addSubview(outText)

registerClass(ClientView)
