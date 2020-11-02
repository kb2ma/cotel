## Cotel GUI
##
## GUI for libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import nimx / [ button, formatted_text, text_field, timer, window ]
import times
import threadpool, conet

var inText: TextField

proc checkChan() =
  ## Handle any incoming message from the conet channel
  var msgTuple = netChan.tryRecv()
  if msgTuple.dataAvailable:
    case msgTuple.msg.req
    of "result":
      inText.text = now().format("H:mm:ss ") & msgTuple.msg.payload
    else:
      echo("msg not understood: " & msgTuple.msg.req & ", len: " & $msgTuple.msg.req.len)

proc startApplication() =
    var wnd = newWindow(newRect(40, 40, 800, 600))
    wnd.title = "Cotel"

    let inLabel = newLabel(newRect(20, 10, 35, 20))
    let inLabelText = newFormattedText("In:")
    inLabelText.horizontalAlignment = haRight
    inLabel.formattedText = inLabelText

    inText = newLabel(newRect(60, 10, 500, 20))
    inText.text = "<not yet>"
    wnd.addSubview(inLabel)
    wnd.addSubview(inText)

    let outLabel = newLabel(newRect(20, 40, 35, 50))
    let outLabelText = newFormattedText("Out:")
    outLabelText.horizontalAlignment = haRight
    outLabel.formattedText = outLabelText
    wnd.addSubview(outLabel)

    let button = newButton(newRect(80, 40, 100, 22))
    button.title = "Send Msg"
    button.onAction do():
        ctxChan.send( CoMsg(req: "send_msg") )
    wnd.addSubview(button)

    # periodically check for messages from conet channel
    discard newTimer(0.5, true, checkChan)

    # Start network I/O (see conet.nim)
    spawn netLoop()

runApplication:
    startApplication()
