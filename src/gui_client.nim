## View to generate client request and show response
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import json, strutils
import conet, gui_util

type
  NamedId = tuple[id: int, name: string]
  RequestOption = ref object
    optType: NamedId
    # only one of the following is used, based on coapOption
    valueText: string
    valueInt: int

# (id: , name: "")
let optionTypeList = [(id: 12, name: "Content-Format"), (id: 15, name: "Uri-Query")]
let cfList = [(id: 0, name: "text/plain"), (id: 60, name: "app/cbor"),
              (id: 50 , name: "app/json"), (id: 40, name: "app/link-format"),
              (id: 110, name: "app/senml+json"), (id: 112, name: "app/senml+cbor"),
              (id: 111, name: "app/sensml+json"), (id: 113, name: "app/sensml+cbor"),
              (id: 42, name: "octet-stream")]

#type
#  OptionNameArray = array[0..len(optionTypeList)-1, cstring]
#  CfNameArray = array[0..len(cfList)-1, cstring]

var
  isRequestOpen* = false
    ## Enclosing context sets this value
  # must encode as 'var' rather than 'let' to find address for cstring
  protoItems = ["coap".cstring, "coaps".cstring]
  typeItems = ["NON".cstring, "CON".cstring]
  isNewOption = false
  #optionNameItems: OptionNameArray
  optionNameItems = newSeq[cstring](len(optionTypeList))
    ## names of option types, for dropdown
  #cfNameItems: CfNameArray
  cfNameItems = newSeq[cstring](len(cfList))

for i, opt in pairs(optionTypeList):
  GC_ref(opt.name)
  optionNameItems[i] = opt.name.cstring
for i, opt in pairs(cfList):
  GC_ref(opt.name)
  cfNameItems[i] = opt.name.cstring

# widget contents
var
  reqProtoIndex = 0'i32
  reqPort = 5683'i32
  reqHost = newString(64)
  reqTypeIndex = 0'i32
  reqPath = newString(64)
  respCode = ""
  respText = ""
  errText = ""

  # for options
  reqOptions = newSeq[RequestOption]()
  optNameIndex = 0'i32
    ## active index into optionNameItems
  cfNameIndex = 0'i32
    ## active index into cfNameItems
  optValue = newString(50)

#proc igComboCotel*(label: cstring, current_item: ptr int32, items_getter: proc(data: pointer, idx: int32, out_text: var ptr string): bool, data: pointer, items_count: int32, popup_max_height_in_items: int32 = -1): bool {.noconv.}

proc onNetMsgRequest*(msg: CoMsg) =
  if msg.subject == "response.payload":
    let msgJson = parseJson(msg.payload)
    respCode = msgJson["code"].getStr()
    respText = msgJson["payload"].getStr()
  elif msg.subject == "send_msg.error":
    errText = "Error sending, see log"

#[
proc getOptionName(data: pointer, idx: int32, out_text: var ptr cstring): bool =
  if idx < len(optionTypeList):
    out_text = optionTypeList[idx].name.cstring.addr
    return true
  return false

proc getCfName(data: pointer, idx: int32, out_text: var ptr cstring): bool =
  if idx < len(cfList):
    out_text = cfList[idx].name.cstring.addr
    return true
  return false
]#

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

  igItemSize(ImVec2(x:0,y:8))
  if igCollapsingHeader("Options"):
    igBeginChild("OptListChild",
                 ImVec2(x:igGetWindowContentRegionWidth() * 0.8f, y:100))
    igColumns(2, "optcols", false)
    igSeparator()
    igSetColumnWidth(-1, 150)
    igText("Type")
    igNextColumn()
    igText("Value")
    igSeparator()

    for o in reqOptions:
      igNextColumn()
      igText(format("$#($#)", o.optType.name, $o.optType.id))
      igNextColumn()
      if o.valueInt > -1:
        if len(o.valueText) > 0:
          igText(format("$#($#)", o.valueText, $o.valueInt))
        else:
          igText($o.valueInt)
      else:
        igText(o.valueText)
    igEndChild()

    igSameLine()
    igBeginChild("OptButtonsChild",
                 ImVec2(x:igGetWindowContentRegionWidth() * 0.2f, y:150))
    igItemSize(ImVec2(x:0,y:32))
    if igButton("New"):
      isNewOption = true
    discard igButton("Delete")
    igEndChild()

    if isNewOption:
      igSetNextItemWidth(140)
      #echo("optionNameItems[0] " & repr(optionNameItems[0]))
      discard igCombo("##optName", optNameIndex.addr, optionNameItems[0].addr,
                      len(optionTypeList).int32)
      #discard igComboCotel("##optName", optNameIndex.addr, getOptionName, nil,
      #                len(optionTypeList).int32)
      igSameLine()
      igSetNextItemWidth(150)
      case optNameIndex
      of 0:
        discard igCombo("##optValue", cfNameIndex.addr, cfNameItems[0].addr,
                        len(cfList).int32)
        #discard igComboCotel("##optValue", cfNameIndex.addr, getCfName, nil,
        #                len(cfList).int32)
      else:
        discard igInputTextCap("##optValue", optValue, 20)

      igSameLine(350)
      if igButton("OK"):
        var reqOption = RequestOption(optType: optionTypeList[optNameIndex])
        case optNameIndex
        of 0:
          reqOption.valueInt = cfList[cfNameIndex].id
          reqOption.valueText = cfList[cfNameIndex].name
        else:
          reqOption.valueInt = -1
          reqOption.valueText = optValue
        reqOptions.add(reqOption)
        isNewOption = false

      igSameLine()
      if igButton("Drop"):
        isNewOption = false


  igItemSize(ImVec2(x:0,y:8))
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
