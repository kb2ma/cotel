## View to generate client request and show response
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import json
import conet, gui_util


var
  isRequestOpen* = false
    ## Enclosing context sets this value
  # must encode as 'var' rather than 'let' to find address for cstring
  protoItems = ["coap".cstring, "coaps".cstring]
  typeItems = ["NON".cstring, "CON".cstring]

  # widget contents
  reqProtoIndex = 0'i32
  reqPort = 5683'i32
  reqHost = newString(64)
  reqTypeIndex = 0'i32
  reqPath = newString(64)
  respCode = ""
  respText = ""
  errText = ""

proc onNetMsgRequest*(msg: CoMsg) =
  if msg.subject == "response.payload":
    let msgJson = parseJson(msg.payload)
    respCode = msgJson["code"].getStr()
    respText = msgJson["payload"].getStr()
  elif msg.subject == "send_msg.error":
    errText = "Error sending, see log"

proc showRequestWindow*() =
  igSetNextWindowSize(ImVec2(x: 500, y: 300), FirstUseEver)
  igBegin("Request", isRequestOpen.addr)
  let labelColWidth = 90f

  igText("Protocol")
  igSameLine(labelColWidth)
  igSetNextItemWidth(100)
  discard igCombo("##proto", reqProtoIndex.addr, protoItems[0].addr, 2)

  igSameLine(250)
  igText("Port")
  igSameLine()
  igSetNextItemWidth(100)
  igInputInt("##port", reqPort.addr);

  igText("Host")
  igSameLine(labelColWidth)
  igSetNextItemWidth(300)
  igInputText("##host", reqHost.cstring, 64);

  igText("URI Path")
  igSameLine(labelColWidth)
  igSetNextItemWidth(300)
  igInputText("##path", reqPath.cstring, 64);

  igText("Msg Type")
  igSameLine(labelColWidth)
  igSetNextItemWidth(100)
  discard igCombo("##msgType", reqTypeIndex.addr, typeItems[0].addr, 2)

  if igButton("Send Req") or isEnterPressed():
    errText = ""
    respCode = ""
    var jNode = %*
      { "msgType": $typeItems[reqTypeIndex], "uriPath": $reqPath.cstring,
        "proto": $protoItems[reqProtoIndex], "remHost": $reqHost.cstring,
        "remPort": reqPort }
    ctxChan.send( CoMsg(subject: "send_msg", payload: $jNode) )
  igSameLine(labelColWidth)
  igSetNextItemWidth(300)
  igTextColored(ImVec4(x: 1f, y: 0f, z: 0f, w: 1f), errText)

  # only display if response available
  if respCode.len > 0:
    igSeparator()
    igTextColored(ImVec4(x: 1f, y: 1f, z: 0f, w: 1f), "Code")
    igSameLine(labelColWidth)
    igSetNextItemWidth(500)
    igText(respCode)
    igSetNextItemWidth(500)
    igTextWrapped(respText)

  igEnd()
