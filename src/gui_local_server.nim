## View to setup and enable a local CoAP server. Includes endpoints and
## security.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import json
import conet

type
  LocalServerStatus = enum
    ## Window and editing status
    STATUS_INIT
      ## before first use
    STATUS_PENDING_OPEN
      ## waiting for config data to display UI
    STATUS_OPEN

var
  status = STATUS_INIT
  statusText = ""
  config: ServerConfig

  nosecEnable = false
  nosecPort = 5683'i32
  secEnable = false
  secPort = 5684'i32
  listenAddr = "::" & newString(64)

proc setStatus(status: LocalServerStatus, text: string = "") =
  gui_local_server.status = status
  statusText = text

proc updateVars(srcConfig: ServerConfig) =
  ## Convenience method for common actions when config is updated
  config = srcConfig
  nosecEnable = config.nosecEnable
  nosecPort = config.nosecPort.int32
  secEnable = config.secEnable
  secPort = config.secPort.int32
  listenAddr = config.listenAddr & newString(64)

proc onConfigUpdate*(config: ServerConfig) =
  ## Assumes provided config reflects the actual state of conet endpoints. So,
  ## if the UI requested NoSec to enable, then config.nosecEnable will be true
  ## here if in fact the server endpoint now is listening.
  updateVars(config)
  setStatus(status, "OK")

proc setConfig*(config: ServerConfig) =
  ## Sets configuration data when opening the window.
  updateVars(config)
  setStatus(STATUS_OPEN)

proc setPendingOpen*() =
  ## Window will be opened; waiting for config data in setConfig()
  setStatus(STATUS_PENDING_OPEN)

proc showWindow*(isActivePtr: ptr bool) =
  if status == STATUS_PENDING_OPEN:
    # don't have config data yet
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

  # NoSec
  colPos = 0f
  igCheckbox("##nosecEnable", nosecEnable.addr);
  colPos += colWidth - shim
  igSameLine(colPos)
  igText("coap")
  colPos += colWidth - shim*2
  igSameLine(colPos)
  igSetNextItemWidth(100)
  if config.nosecEnable:
    igText($nosecPort)
  else:
    igInputInt("##nosecPort", nosecPort.addr);
  colPos += colWidth + shim*3
  igSameLine(colPos)
  igSetNextItemWidth(250)
  if config.nosecEnable or config.secEnable:
    igText(listenAddr)
  else:
    igInputText("##listenAddr", listenAddr.cstring, 64);

  # Secure
  colPos = 0f
  igCheckbox("##secEnable", secEnable.addr);
  colPos += colWidth - shim
  igSameLine(colPos)
  igText("coaps")
  colPos += colWidth - shim*2
  igSameLine(colPos)
  igSetNextItemWidth(100)
  if config.secEnable:
    igText($secPort)
  else:
    igInputInt("##nosecPort", secPort.addr);
  colPos += colWidth + shim*3
  igSameLine(colPos)
  igText("same")

  igItemSize(ImVec2(x:0,y:8))

  colPos = 0
  if igButton("Make it so"):
    let config = ServerConfig(listenAddr: listenAddr, nosecEnable: nosecEnable,
                              nosecPort: nosecPort, secEnable: secEnable,
                              secPort: secPort, pskKey: @[], pskClientId: "")
    ctxChan.send( CoMsg(subject: "config.server.PUT",
                        token: "local_server.update", payload: $(%* config)) )
  if statusText != "":
    colPos += colWidth + shim
    igSameLine(colPos)
    igTextColored(ImVec4(x: 0f, y: 1f, z: 0f, w: 1f), statusText)
  igEnd()
