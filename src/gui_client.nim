## Client view
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ button, formatted_text, popup_button, text_field, view ]
import json, strutils
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

  # y-coordinate for current row of UI
  var rowY = 10.Coord

  let portLabel = newLabel(newRect(20, rowY, 100, 20))
  let portLabelText = newFormattedText("Port:")
  portLabelText.horizontalAlignment = haRight
  portLabel.formattedText = portLabelText
  v.addSubview(portLabel)

  let portTextField = newTextField(newRect(140, rowY, 80, 20))
  portTextField.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  portTextField.text = "5683"
  v.addSubview(portTextField)

  rowY += 30

  let pathLabel = newLabel(newRect(20, rowY, 100, 20))
  let pathLabelText = newFormattedText("URI Path:")
  pathLabelText.horizontalAlignment = haRight
  pathLabel.formattedText = pathLabelText
  v.addSubview(pathLabel)

  let pathTextField = newTextField(newRect(140, rowY, 300, 20))
  pathTextField.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  v.addSubview(pathTextField)

  rowY += 30

  let typeLabel = newLabel(newRect(20, rowY, 100, 20))
  let typeLabelText = newFormattedText("Msg type:")
  typeLabelText.horizontalAlignment = haRight
  typeLabel.formattedText = typeLabelText
  v.addSubview(typeLabel)

  let typeDd = PopupButton.new(newRect(140, rowY, 80, 20))
  typeDd.items = @["NON", "CON"]
  v.addSubview(typeDd)

  rowY += 30

  let button = newButton(newRect(20, rowY, 100, 22))
  button.title = "Send Msg"
  button.onAction do():
    var jNode = %*
      { "msgType": typeDd.selectedItem(), "uriPath": pathTextField.text,
        "remPort": parseInt(portTextField.text) }

    onSendClicked(jNode)
  v.addSubview(button)

  rowY += 30

  let respLabel = newLabel(newRect(20, rowY, 100, 20))
  let respLabelText = newFormattedText("Response:")
  respLabelText.horizontalAlignment = haRight
  respLabel.formattedText = respLabelText
  v.addSubview(respLabel)

  let respTextLabel = newLabel(newRect(140, rowY, 500, 80))
  v.respText = newFormattedText("")
  respTextLabel.formattedText = v.respText
  v.respText.verticalAlignment = vaTop
  v.addSubview(respTextLabel)

registerClass(ClientView)
