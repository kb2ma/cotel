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
  listenAddr = "::" & newString(62)

proc onConfigUpdate*() =
  # display config updated OK
  discard

proc setConfig*(config: ServerConfig) =
  nosecEnable = config.nosecEnabled
  nosecPort = config.nosecPort.int32
  listenAddr = config.listenAddr
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
  igInputText("##listenAddr", listenAddr.cstring, 64);

  igItemSize(ImVec2(x:0,y:8))

  if igButton("Make it so"):
    let config = ServerConfig(listenAddr: listenAddr, nosecEnable: nosecEnable,
                              nosecPort: nosecPort, secEnable: false,
                              secPort: 0, pskKey: @[], pskClientId: "")
    var jNode = %* config
    ctxChan.send( CoMsg(subject: "config.server.PUT",
                        token: "local_server.update", payload: (%* config)) )
  igEnd()
