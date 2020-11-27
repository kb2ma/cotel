## View to setup and enable a local CoAP server
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import conet


var
  isPendingOpen = false
  nosecEnable = false
  nosecPort = 5683'i32
  nosecListenAddr = "::" & newString(62)

proc setConfig*(config: ServerConfig) =
  nosecEnable = config.nosecEnabled
  nosecPort = config.nosecPort.int32
  nosecListenAddr = config.nosecListenAddr
  isPendingOpen = false

proc setPendingOpen*() =
  isPendingOpen = true

proc showWindow*(isActivePtr: ptr bool) =
  if isPendingOpen:
    return

  igSetNextWindowSize(ImVec2(x: 600, y: 300), FirstUseEver)
  igBegin("Local Server", isActivePtr)
  var colPos = 0f
  let colWidth = 90f
  let shim = 10f

  # headers
  igText("Enable")
  colPos += colWidth - shim
  igSameLine(colPos)
  igText("Protocol")
  colPos += colWidth - shim*2
  igSameLine(colPos)
  igText("Port")
  colPos += colWidth
  igSameLine(colPos + shim*3)
  igText("Listen Address")

  # nosec
  colPos = 0f
  igCheckbox("##nosecEnable", nosecEnable.addr);
  colPos += colWidth - shim
  igSameLine(colPos)
  igText("coap")
  colPos += colWidth - shim*2
  igSameLine(colPos)
  igSetNextItemWidth(100)
  igInputInt("##nosecPort", nosecPort.addr);
  colPos += colWidth + shim*3
  igSameLine(colPos)
  igSetNextItemWidth(250)
  igInputText("##nosecListenAddr", nosecListenAddr.cstring, 64);

  igItemSize(ImVec2(x:0,y:8))
  #igSpacing()
  if igButton("Make it so"):
    discard
    # reset error text for this send
#[    errText = ""
    var jNode = %*
      { "msgType": $typeItems[reqTypeIndex], "uriPath": $reqPath.cstring,
        "proto": $protoItems[reqProtoIndex], "remHost": $reqHost.cstring,
        "remPort": reqPort }
    ctxChan.send( CoMsg(req: "send_msg", payload: $jNode) )
]#
  igEnd()
