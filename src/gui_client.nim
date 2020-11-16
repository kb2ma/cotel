## View to generate client request and show response
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import nimx / [ button, font, formatted_text, popup_button, scroll_view,
                table_view, table_view_cell, text_field, view ]
import json, os, strutils
import conet

type
  ClientView* = ref object of View
    state*: ClientState
    respText: FormattedText
    bottomY: Coord
      ## y-value for the bottom of the last control in the view, which makes
      ## it easy to dynamically add another control below it
    logLabel: TextField
    logScroll*: ScrollView
    logPos*: int64
    logLines*: seq[string]
      ## log lines collected from 'logFile'

  ClientState* = ref object
    userCtx*: ClientView
      ## User context for the state -- the view
    showsLog*: bool
      ## Show the log in the user context if true


proc onChanMsg*(state: ClientState, msg: CoMsg) =
  if msg.req == "response.payload":
    state.userCtx.respText.text = msg.payload

proc onSendClicked(v: ClientView, jNode: JsonNode) =
  ctxChan.send( CoMsg(req: "send_msg", payload: $jNode) )

proc showLogView*(v: ClientView, wndBounds: Rect) =
  ## Shows the log table, and sets up infrastructure to read net.log as needed.
  ## Assumes view 'logLines' already initialized.
  ## Must provide enclosing window bounds since client view may not have been
  ## added to the window yet.

  if v.logPos < 0:
    # initialize file position on first use
    v.logPos = os.getFileSize("net.log")

  # build log label, list
  v.logLabel = newLabel(newRect(20, wndBounds.height - 220, 100, 20))
  let labelText = newFormattedText("Log")
  #labelText.horizontalAlignment = haRight
  v.logLabel.formattedText = labelText
  v.addSubview(v.logLabel)

  let logTable = newTableView(newRect(6, wndBounds.height - 200,
                                      wndBounds.width, wndBounds.height))
  logTable.name = "logTable"
  logTable.autoresizingMask = {afFlexibleWidth}
  v.logScroll = newScrollView(logTable)
  v.addSubview(v.logScroll)

  # Use smaller font, and use same Font instance for all cells
  let cellFont = systemFontOfSize(12)
  logTable.numberOfRows = proc: int = v.logLines.len
  logTable.createCell = proc (): TableViewCell =
    let label = newLabel(newRect(0, 0, wndBounds.width - 8, 16))
    label.font = cellFont
    result = newTableViewCell(label)
  logTable.configureCell = proc (c: TableViewCell) =
    let tf = TextField(c.subviews[0])
    tf.font = cellFont
    tf.text = v.logLines[c.row]
    tf.selectable = true
  logTable.heightOfRow = proc (row: int): Coord =
    result = 16
  v.state.showsLog = true

proc hideLogView*(v: ClientView) =
  ## Hides the log table.
  if v.logLabel != nil:
    v.logLabel.removeFromSuperview()
    v.logLabel = nil
    v.logScroll.removeFromSuperview()
    v.logScroll = nil
    v.state.showsLog = false


method init*(v: ClientView, r: Rect) =
  procCall v.View.init(r)

  v.logPos = -1
  v.logLines = newSeqOfCap[string](5)

  # y-coordinate for current row of UI
  var rowY = 20.Coord

  let remoteLabel = newLabel(newRect(20, rowY, 100, 20))
  let remoteLabelText = newFormattedText("Protocol:")
  remoteLabelText.horizontalAlignment = haRight
  remoteLabel.formattedText = remoteLabelText
  v.addSubview(remoteLabel)

  let protoDd = PopupButton.new(newRect(140, rowY, 80, 20))
  protoDd.items = @["coap", "coaps"]
  v.addSubview(protoDd)

  let portLabel = newLabel(newRect(240, rowY, 60, 20))
  let portLabelText = newFormattedText("Port:")
  portLabelText.horizontalAlignment = haRight
  portLabel.formattedText = portLabelText
  v.addSubview(portLabel)

  let portTextField = newTextField(newRect(320, rowY, 80, 20))
  #portTextField.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  portTextField.text = "5683"
  v.addSubview(portTextField)

  rowY += 30

  let hostLabel = newLabel(newRect(20, rowY, 100, 20))
  let hostLabelText = newFormattedText("Host:")
  hostLabelText.horizontalAlignment = haRight
  hostLabel.formattedText = hostLabelText
  v.addSubview(hostLabel)

  let hostTextField = newTextField(newRect(140, rowY, 300, 20))
  #hostTextField.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  v.addSubview(hostTextField)

  rowY += 30

  let pathLabel = newLabel(newRect(20, rowY, 100, 20))
  let pathLabelText = newFormattedText("URI Path:")
  pathLabelText.horizontalAlignment = haRight
  pathLabel.formattedText = pathLabelText
  v.addSubview(pathLabel)

  let pathTextField = newTextField(newRect(140, rowY, 300, 20))
  #pathTextField.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
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

  # forward declare err text for use in button callback
  var errTextLabel: TextField
  var errText: FormattedText
  
  let button = newButton(newRect(20, rowY, 100, 30))
  button.title = "Send Msg"
  button.onAction do():
    # clear response
    v.respText.text = ""
    # verify input
    errText.text = ""
    if portTextField.text == "":
      errText.text = "Port can't be blank"
      errText.setTextColorInRange(0, len(errText.text), newColor(1, 0, 0))
      return

    var jNode = %*
      { "msgType": typeDd.selectedItem(), "uriPath": pathTextField.text,
        "proto": protoDd.selectedItem, "remHost": hostTextField.text,
        "remPort": parseInt(portTextField.text) }
    onSendClicked(v, jNode)

  v.addSubview(button)

  # error text -- blank unless error
  # Move down just a little due to send button height
  errTextLabel = newLabel(newRect(140, rowY + 5, 500, 80))
  errText = newFormattedText("")
  errTextLabel.formattedText = errText
  v.addSubview(errTextLabel)

  rowY += 35

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

  v.bottomY = rowY.Coord + 80

registerClass(ClientView)
