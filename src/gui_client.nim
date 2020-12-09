## View to generate client request and show response
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import json, strutils, std/jsonutils
import conet, gui_util

type
  NamedId = tuple[id: int, name: string]

const
  reqHostCapacity = 64
  reqPathCapacity = 255
    ## No need to validate user entry for this path length
  optValueCapacity = 1034
    ## Length of the string used to edit option value; the longest possible
    ## option value.

let
  protoItems = ["coap", "coaps"]
  typeItems = ["NON", "CON"]
  cfList = [(id: 0, name: "text/plain"), (id: 60, name: "app/cbor"),
            (id: 50 , name: "app/json"), (id: 40, name: "app/link-format"),
            (id: 110, name: "app/senml+json"), (id: 112, name: "app/senml+cbor"),
            (id: 111, name: "app/sensml+json"), (id: 113, name: "app/sensml+cbor"),
            (id: 42, name: "octet-stream")]
  headingColor = ImVec4(x: 154f/256f, y: 152f/256f, z: 80f/256f, w: 230f/256f)
    ## dull gold color
  optListHeight = 120f

var
  isRequestOpen* = false
    ## Enclosing context sets this value
  isNewOption = false
    ## True if editing a new option

  # widget contents
  reqProtoIndex = 0
  reqPort = 5683'i32
  reqHost = newStringOfCap(reqHostCapacity)
  reqTypeIndex = 0
  reqPath = newStringOfCap(reqPathCapacity)
  respCode = ""
  respText = ""
  errText = ""

  # for options
  reqOptions = newSeq[MessageOption]()
  optionIndex = -1
    ## active index into reqOptions listbox
  optNameIndex = 0
    ## active index into optionNameItems
  cfNameIndex = 0
    ## active index into cfNameItems
  optValue = newStringOfCap(optValueCapacity)
  optErrText = ""


proc onNetMsgRequest*(msg: CoMsg) =
  if msg.subject == "response.payload":
    let msgJson = parseJson(msg.payload)
    respCode = msgJson["code"].getStr()
    respText = msgJson["payload"].getStr()
  elif msg.subject == "send_msg.error":
    errText = "Error sending, see log"

proc igComboNamedObj[T](label: string, currentIndex: var int,
                    idList: openArray[T]): bool =
  ## Combo box to display a list of NamedIds, like option types.
  result = false
  if igBeginCombo(label, idList[currentIndex].name):
    for i in 0 ..< len(idList):
      let isSelected = (i == currentIndex)
      if igSelectable(idList[i].name, isSelected):
        currentIndex = i
      if isSelected:
        igSetItemDefaultFocus()
        result = true
    igEndCombo()

proc resetContents() =
  ## Resets many vars to blank/empty state.
  reqPath = newString(reqPathCapacity)
  reqOptions = newSeq[MessageOption]()
  optionIndex = -1
  optNameIndex = 0
  cfNameIndex = 0
  optValue = newStringofCap(optValueCapacity)
  optErrText = ""
  respCode = ""
  respText = ""

proc readNewOption(optType: OptionType): MessageOption =
  ## Reads the option type and value for a new user-entered option.
  ## Returns the new option, or nil on the first failure. If nil, also sets
  ## 'optErrText'.
  result = MessageOption(optNum: optType.id, typesIndex: optNameIndex)
  if optType.id == OPTION_CONTENT_FORMAT.int:
    result.valueInt = cfList[cfNameIndex].id
    result.valueText = cfList[cfNameIndex].name
  else:
    if len(optValue) == 0:
      optErrText = "Empty value"
      return nil
    elif optType.dataType == TYPE_UINT:
      try:
        result.valueInt = parseInt(optValue)
      except ValueError:
        optErrText = "Expecting integer value"
        return nil
      let maxval = 1 shl (optType.maxlen * 8) - 1
      if result.valueInt > maxval:
        optErrText = "Value exceeds option maximum " & $maxval
        return nil
    elif optType.dataType == TYPE_OPAQUE:
      result.valueInt = -1
      if len(optValue) mod 2 != 0:
        optErrText = "Expecting hex digits, but length not a multiple of two"
        return nil
      let seqLen = (len(optValue) / 2).int
      if seqLen > optType.maxlen:
        optErrText = format("Byte length $# exceeds option maximum $#", $seqLen,
                     $optType.maxlen)
        return nil
      result.valueChars = newSeq[char](seqLen)
      try:
        for i in 0 ..< seqLen:
          result.valueChars[i] = cast[char](fromHex[int](optValue.substr(i*2, i*2+1)))
      except ValueError:
        optErrText = "Expecting hex digits"
        return nil
    else:  # TYPE_STRING
      if len(optValue) > optType.maxlen:
        optErrText = format("Length $# exceeds option maximum $#", $len(optValue),
                     $optType.maxlen)
        return nil
      result.valueInt = -1
      result.valueText = optValue

proc showRequestWindow*() =
  # Depending on UI state, the handler for isEnterPressed() may differ. Ensure
  # it's handled only once.
  var isEnterHandled = false

  igSetNextWindowSize(ImVec2(x: 500, y: 300), FirstUseEver)
  igBegin("Request", isRequestOpen.addr)
  let labelColWidth = 90f

  igText("Protocol")
  igSameLine(labelColWidth)
  igSetNextItemWidth(100)
  discard igComboString("##proto", reqProtoIndex, protoItems)

  igSameLine(250)
  igText("Port")
  igSameLine()
  igSetNextItemWidth(100)
  igInputInt("##port", reqPort.addr);

  igText("Host")
  igSameLine(labelColWidth)
  igSetNextItemWidth(300)
  discard igInputTextCap("##host", reqHost, reqHostCapacity)

  igText("URI Path")
  igSameLine(labelColWidth)
  igSetNextItemWidth(300)
  discard igInputTextCap("##path", reqPath, reqPathCapacity)

  igText("Msg Type")
  igSameLine(labelColWidth)
  igSetNextItemWidth(100)
  discard igComboString("##msgType", reqTypeIndex, typeItems)

  igItemSize(ImVec2(x:0,y:8))
  if igCollapsingHeader("Options"):
    igBeginChild("OptListChild",
                 ImVec2(x:igGetWindowContentRegionWidth() * 0.8f, y:optListHeight))
    igColumns(2, "optcols", false)
    igSeparator()
    igSetColumnWidth(-1, 150)
    igTextColored(headingColor, "Type")
    igNextColumn()
    igTextColored(headingColor, "Value")
    igSeparator()

    for i in 0 ..< len(reqOptions):
      let o = reqOptions[i]
      igNextColumn()
      #echo("i, optionIndex " & $i & ", " & $optionIndex)
      if igSelectable(format("$#($#)##opt$#", optionTypes[o.typesIndex].name, $o.optNum, $i),
                      i == optionIndex, ImGuiSelectableFlags.SpanAllColumns):
        optionIndex = i;
        optErrText = ""
        isNewOption = false

      igNextColumn()
      if o.valueInt > -1:
        if len(o.valueText) > 0:
          igText(format("$#($#)", o.valueText, $o.valueInt))
        else:
          igText($o.valueInt)
      elif len(o.valueChars) > 0:
        var charText: string
        for i in o.valueChars:
          charText.add(toHex(cast[int](i), 2))
        igText(charText)
      else:
        igText(o.valueText)
    igEndChild()

    # buttons for option list
    igSameLine()
    igBeginChild("OptButtonsChild",
                 ImVec2(x:igGetWindowContentRegionWidth() * 0.2f, y:optListHeight))
    igItemSize(ImVec2(x:0,y:32))
    if igButton("New"):
      isNewOption = true
      optionIndex = -1
      optValue = newStringofCap(optValueCapacity)
    if igButton("Delete") and optionIndex >= 0:
      reqOptions.delete(optionIndex)
      #optionIndex = -1
    igEndChild()

    # new option entry
    if isNewOption:
      igSetNextItemWidth(140)
      discard igComboNamedObj[OptionType]("##optName", optNameIndex, optionTypes)
      igSameLine()
      igSetNextItemWidth(150)
      let optType = optionTypes[optNameIndex]
      case optType.id
      of OPTION_CONTENT_FORMAT.int:
        discard igComboNamedObj[NamedId]("##optValue", cfNameIndex, cfList)
      else:
        discard igInputTextCap("##optValue", optValue, optValueCapacity)

      igSameLine(350)
      if igButton("OK") or (isEnterPressed() and not isEnterHandled):
        optErrText = ""
        let reqOption = readNewOption(optType)
        if reqOption != nil:
          reqOptions.add(reqOption)
          # clear for next entry
          optValue = newStringOfCap(optValueCapacity)
        isEnterHandled = true

      igSameLine()
      if igButton("Done"):
        optErrText = ""
        isNewOption = false

      if optErrText != "":
        igTextColored(ImVec4(x: 1f, y: 0f, z: 0f, w: 1f), optErrText)

  igItemSize(ImVec2(x:0,y:8))
  if igButton("Send Request") or (isEnterPressed() and not isEnterHandled):
    errText = ""
    respCode = ""
    var jNode = %*
      { "msgType": $typeItems[reqTypeIndex], "uriPath": $reqPath.cstring,
        "proto": $protoItems[reqProtoIndex], "remHost": $reqHost.cstring,
        "remPort": reqPort, "reqOptions": toJson(reqOptions) }
    ctxChan.send( CoMsg(subject: "send_msg", payload: $jNode) )
    isEnterHandled = true
  igSameLine(150)
  if igButton("Reset"):
    resetContents()

  if len(errText) > 0:
    igSetNextItemWidth(400)
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
