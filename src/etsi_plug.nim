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
import hashes, logging, strutils
import comsg, conet_ctx

type ValueBuffer = array[0..7, char]
  ## Holds arbitrary values for encoding/decoding with libcoap

#
# /test resource, for general GET, PUT, POST, DELETE access
#
var testContents = "A. Corelli"

proc logHandled(`method`: string, path: string, session: CSession, req: CPdu,
                token: CCoapString) =
  ## Convenience function for handlers.
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  var tokenSeq = newSeq[char](token.length)
  copyMem(tokenSeq[0].addr, token.s, token.length)
  var tokenHex: string
  for c in tokenSeq:
    tokenHex.add(toHex(cast[int](c), 2))
    tokenHex.add(' ')
  oplog.log(lvlInfo, format("Handled $# $# from $#, ID $#, token $#", `method`,
            path, remote, req.tid, if len(tokenHex) > 0: tokenHex else: "<none>"))

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

  logHandled("GET", "/test", session, req, token)

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

  logHandled("PUT", "/test", session, req, token)

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

  logHandled("POST", "/test", session, req, token)

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
  logHandled("DELETE", "/test", session, req, token)

#
# /validate resource, for ETag
#
# Recognized /validate resource values
const ETAG_LEN = 4

var
  valSourceItems = ["Now is the time", "for all good people",
                    "to come to the aid", "of their country"]
  # Index of currently selected item for resource
  valSourceIndex = 1

var valSourceEtag = newSeq[char](ETAG_LEN)
let etag = hash(valSourceItems[valSourceIndex])
for i in 0..(ETAG_LEN-1):
  # define etag bytes in big endian order
  valSourceEtag[(ETAG_LEN-1)-i] = cast[char]((etag.uint and (0xFF'u shl (8*i))) shr (8*i))

proc handleValidateGet(context: CContext, resource: CResource, session: CSession,
                       req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                      {.exportc: "hnd_validate_get", noconv.} =
  ## TD_COAP_CORE_21
  ## Uses 4-byte hash for ETag
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON

  # Don't send payload if ETag indicates client already has it
  var isReqEtagValid = false
  for opt in readOptions(req):
    if opt.optNum == COAP_OPTION_ETAG and opt.valueChars == valSourceEtag:
      isReqEtagValid = true

  var chain: COptlist
  # add ETag
  var optlist = newOptlist(COAP_OPTION_ETAG.uint16, len(valSourceEtag).csize_t,
                           cast[ptr uint8](valSourceEtag[0].addr))
  discard insertOptlist(addr chain, optlist)

  if not isReqEtagValid:
    # add text/plain Content-Format
    var buf: ValueBuffer
    let valLen = encodeVarSafe(cast[ptr uint8](buf.addr), len(buf).csize_t, 0.uint)
    optlist = newOptlist(COAP_OPTION_CONTENT_FORMAT.uint16, valLen,
                         cast[ptr uint8](buf.addr))
    discard insertOptlist(addr chain, optlist)

  discard addOptlistPdu(resp, addr chain)

  # Return payload only if request does not include ETag for contents
  if isReqEtagValid:
    resp.code = COAP_RESPONSE_CODE_203  # Valid
  else:
    resp.code = COAP_RESPONSE_CODE_205  # Content
    let contents = valSourceItems[valSourceIndex]
    discard addData(resp, len(contents).csize_t, contents)
    
  logHandled("GET", "/validate", session, req, token)

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
