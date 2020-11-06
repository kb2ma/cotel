## Client view
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ button, formatted_text, popup_button, text_field, view ]
import json
import conet

type
  ClientView* = ref object of View
    respText: FormattedText
  ClientState* = ref object
    view*: ClientView

proc onChanMsg*(state: ClientState, msg: CoMsg) =
  if msg.req == "response.payload":
    state.view.respText.text = msg.payload

proc onSendClicked(jNode: JsonNode) =

  ctxChan.send( CoMsg(req: "send_msg", payload: $jNode) )

method init*(v: ClientView, r: Rect) =
  procCall v.View.init(r)

  let pathLabel = newLabel(newRect(20, 10, 100, 20))
  let pathLabelText = newFormattedText("URI Path:")
  pathLabelText.horizontalAlignment = haRight
  pathLabel.formattedText = pathLabelText
  v.addSubview(pathLabel)

  let pathTextField = newTextField(newRect(140, 10, 300, 20))
  pathTextField.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  v.addSubview(pathTextField)

  let typeLabel = newLabel(newRect(20, 40, 100, 20))
  let typeLabelText = newFormattedText("Msg type:")
  typeLabelText.horizontalAlignment = haRight
  typeLabel.formattedText = typeLabelText
  v.addSubview(typeLabel)

  let typeDd = PopupButton.new(newRect(140, 40, 80, 20))
  typeDd.items = @["NON", "CON"]
  v.addSubview(typeDd)

  let button = newButton(newRect(20, 70, 100, 22))
  button.title = "Send Msg"
  button.onAction do():
    var jNode = %*
      { "msgType": typeDd.selectedItem(), "uriPath": pathTextField.text }

    onSendClicked(jNode)
  v.addSubview(button)

  let respLabel = newLabel(newRect(20, 100, 100, 20))
  let respLabelText = newFormattedText("Response:")
  respLabelText.horizontalAlignment = haRight
  respLabel.formattedText = respLabelText
  v.addSubview(respLabel)

  let respTextLabel = newLabel(newRect(140, 100, 500, 80))
  v.respText = newFormattedText("")
  respTextLabel.formattedText = v.respText
  v.respText.verticalAlignment = vaTop
  v.addSubview(respTextLabel)

registerClass(ClientView)
