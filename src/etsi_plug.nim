## Server handler module for ETSI CoAP plugtests. Provides an array of resources
## to exercise a client. See https://rawgit.com/cabo/td-coap4/master/base.html
## for test descriptions.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import libcoap, nativesockets
import logging, strutils
import conet_ctx

type ValueBuffer = array[0..7, char]
  ## Holds arbitrary values for encoding/decoding with libcoap

var testContents = "A. Corelli"

proc handleTestGet(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_get", noconv.} =
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
    var optlist = newOptlist(OPTION_CONTENT_FORMAT.uint16, valLen,
                             cast[ptr uint8](buf.addr))
    discard addOptlistPdu(resp, addr optlist)

    discard addData(resp, len(testContents).csize_t, testContents)
    
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("GET /test from $#", remote))

proc handleTestPut(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_put", noconv.} =
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON
  if len(testContents) == 0:
    resp.code = COAP_RESPONSE_CODE_201  # Created
  else:
    resp.code = COAP_RESPONSE_CODE_204  # Changed

  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(req, addr dataLen, addr dataPtr)
  var dataStr = newString(dataLen)
  copyMem(addr dataStr[0], dataPtr, dataLen)
  testContents = dataStr

  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("PUT /test from $#", remote))

proc handleTestDelete(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_delete", noconv.} =
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


proc initResources*(ctx: CContext) =
  var r = initResource(makeStringConst("test"), 0)
  registerHandler(r, COAP_REQUEST_GET, handleTestGet)
  registerHandler(r, COAP_REQUEST_PUT, handleTestPut)
  registerHandler(r, COAP_REQUEST_DELETE, handleTestDelete)
  addResource(ctx, r)
