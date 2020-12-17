## Server handler module for ETSI CoAP plugtests. Provides an array of resources
## to exercise a client. See https://rawgit.com/cabo/td-coap4/master/base.html
## for test descriptions.
##
## Includes the /test, /validate resources.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import libcoap, nativesockets
import hashes, logging, strformat, strutils
import conet_ctx

type ValueBuffer = array[0..7, char]
  ## Holds arbitrary values for encoding/decoding with libcoap

#
# /test resource, for general GET, PUT, POST, DELETE access
#
var testContents = "A. Corelli"

proc handleTestGet(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_get", noconv.} =
  ## TD_COAP_CORE_01, TD_COAP_CORE_05, TD_COAP_CORE_12
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON
  if len(testContents) == 0:
    resp.code = COAP_RESPONSE_CODE_404  # Not Found
  else:
    resp.code = COAP_RESPONSE_CODE_205  # Content

    # add text/plain Content-Format
    var buf: ValueBuffer
    let valLen = encodeVarSafe(cast[ptr uint8](buf.addr), len(buf).csize_t,
                               0.uint)
    var optlist = newOptlist(COAP_OPTION_CONTENT_FORMAT.uint16, valLen,
                             cast[ptr uint8](buf.addr))
    discard addOptlistPdu(resp, addr optlist)

    discard addData(resp, len(testContents).csize_t, testContents)
    
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("GET /test from $#", remote))

proc handleTestPut(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_put", noconv.} =
  ## TD_COAP_CORE_03, TD_COAP_CORE_07
  ## Expects body with some text string
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON

  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(req, addr dataLen, addr dataPtr)

  if dataLen == 0:
    resp.code = COAP_RESPONSE_CODE_400
  else:
    if len(testContents) == 0:
      resp.code = COAP_RESPONSE_CODE_201  # Created
    else:
      resp.code = COAP_RESPONSE_CODE_204  # Changed

    var dataStr = newString(dataLen)
    copyMem(addr dataStr[0], dataPtr, dataLen)
    testContents = dataStr

  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("PUT /test from $#", remote))

proc handleTestPost(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_post", noconv.} =
  ## TD_COAP_CORE_04, TD_COAP_CORE_08
  ## Expects body with some text string
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON

  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(req, addr dataLen, addr dataPtr)

  if dataLen == 0:
    resp.code = COAP_RESPONSE_CODE_400
  else:
    if len(testContents) == 0:
      resp.code = COAP_RESPONSE_CODE_201  # Created
    else:
      resp.code = COAP_RESPONSE_CODE_204  # Changed

    var dataStr = newString(dataLen)
    copyMem(addr dataStr[0], dataPtr, dataLen)
    testContents = dataStr

  if resp.code == COAP_RESPONSE_CODE_201:
    # add Location-Path option
    var path = "test"
    var optlist = newOptlist(COAP_OPTION_LOCATION_PATH.uint16, len(path).csize_t,
                             cast[ptr uint8](path[0].addr))
    discard addOptlistPdu(resp, addr optlist)

  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("POST /test from $#", remote))

proc handleTestDelete(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_delete", noconv.} =
  ## TD_COAP_CORE_02, TD_COAP_CORE_06
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON
  if len(testContents) > 0:
    resp.code = COAP_RESPONSE_CODE_202  # Deleted
  else:
    resp.code = COAP_RESPONSE_CODE_404  # Not Found

  testContents = ""
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("DELETE /test from $#", remote))

#
# /validate resource, for ETag
#
# Recognized /validate resource values
var valSourceItems = ["Now is the time", "for all good men",
                      "to come to the aid", "of their country"]
# Index of currently selected item for resource
var valSourceIndex = 0

proc handleValidateGet(context: CContext, resource: CResource, session: CSession,
                       req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                      {.exportc: "hnd_validate_get", noconv.} =
  ## TD_COAP_CORE_21
  ## Uses 4-byte hash for ETag
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON
  resp.code = COAP_RESPONSE_CODE_205  # Content

  var chain: COptlist

  # add text/plain Content-Format
  var buf: ValueBuffer
  let valLen = encodeVarSafe(cast[ptr uint8](buf.addr), len(buf).csize_t,
                             0.uint)
  var optlist = newOptlist(COAP_OPTION_CONTENT_FORMAT.uint16, valLen,
                           cast[ptr uint8](buf.addr))
  discard insertOptlist(addr chain, optlist)

  # add ETag
  let contents = valSourceItems[valSourceIndex]
  let etag = hash(contents)
  var etagBytes = newSeq[char](4)
  for i in 0..3:
    # define etag bytes in big endian order
    etagBytes[3-i] = cast[char]((etag.uint and (0xFF'u shl (8*i))) shr (8*i))
    #echo(format("etag $#: $#", $(3-i), fmt"{etagBytes[3-i].uint8:02X}"))
  optlist = newOptlist(COAP_OPTION_ETAG.uint16, len(etagBytes).csize_t,
                       cast[ptr uint8](etagBytes[0].addr))
  discard insertOptlist(addr chain, optlist)
  discard addOptlistPdu(resp, addr chain)

  discard addData(resp, len(contents).csize_t, contents)
    
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("GET /validate from $#", remote))

proc initResources*(ctx: CContext) =
  var r = initResource(makeStringConst("test"), 0)
  registerHandler(r, COAP_REQUEST_GET, handleTestGet)
  registerHandler(r, COAP_REQUEST_PUT, handleTestPut)
  registerHandler(r, COAP_REQUEST_POST, handleTestPost)
  registerHandler(r, COAP_REQUEST_DELETE, handleTestDelete)
  addResource(ctx, r)

  var r2 = initResource(makeStringConst("validate"), 0)
  registerHandler(r2, COAP_REQUEST_GET, handleValidateGet)
  addResource(ctx, r2)
