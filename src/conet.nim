## Cotel networking
##
## Runs libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import libcoap, posix, nativesockets
import logging

type
  CoMsg* = object
    ## A REST-like message for use in a channel with the enclosing context
    req*: string
    payload*: string

var netChan*: Channel[CoMsg]
  ## Communication channel from conet to enclosing context
var ctxChan*: Channel[CoMsg]
  ## Communication channel from enclosing context to conet


proc handleHi(context: CContext, resource: CResource, session: CSession,
              req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
              {.exportc: "hnd_hi", noconv.} =
  ## server /hi GET handler; greeting
  resp.`type` = COAP_MESSAGE_ACK
  resp.code = COAP_RESPONSE_CODE_205
  discard addData(resp, 5, "Howdy")
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  netChan.send( CoMsg(req: "request.log", payload: remote & " GET /hi") )

proc handleResponse(context: CContext, session: CSession, sent: CPdu,
                    received: CPdu, id: CTxid) {.exportc: "hnd_response",
                    noconv.} =
  ## client response handler
  #log.log(lvlDebug, "Response received")
  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(received, addr dataLen, addr dataPtr)

  var dataStr = newString(dataLen)
  copyMem(addr dataStr[0], dataPtr, dataLen)
  netChan.send( CoMsg(req: "response.payload", payload: dataStr) )


proc sendMessage(ctx: CContext) =
  ## Send a message to exercise client flow with a server

  # init server address/port
  let address = create(CSockAddr)
  initAddress(address)
  try:
    let info = getAddrInfo("127.0.0.1", 5685.Port, Domain.AF_INET,
                           SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP)
    address.`addr`.sin = cast[SockAddr_in](info.ai_addr[])
    freeaddrinfo(info)
  except OSError:
    error("Can't resolve server address")
    return

  #init session
  var session = newClientSession(ctx, nil, address, COAP_PROTO_UDP)
  if session == nil:
    error("Can't create client session")
    return

  # init PDU, including type and code
  var pdu = initPdu(COAP_MESSAGE_CON, COAP_REQUEST_GET.uint8, 1000'u16,
                    maxSessionPduSize(session))
  if pdu == nil:
    error("Can't create client PDU")
    releaseSession(session)
    return

  # add Uri-Path option
  var optlist = newOptlist(COAP_OPTION_URI_PATH, 4.csize_t, cast[ptr uint8]("time"))
  if optlist == nil:
    error("Can't create option list")
    return
  if addOptlistPdu(pdu, addr(optlist)) == 0:
    error("Can't create option list")
    deleteOptlist(optlist)
    releaseSession(session)
    deletePdu(pdu)
    return
  deleteOptlist(optlist)

  # send
  if send(session, pdu) == COAP_INVALID_TXID:
    deletePdu(pdu)

  # clean up
  #releaseSession(session)


proc netLoop*() =
  ## Setup server and run event loop
  var log = newFileLogger("net.log", fmtStr="[$time] $levelname: ", bufSize=0)
  open(netChan)
  open(ctxChan)

  # init context, listen port/endpoint
  var ctx = newContext(nil)

  # CoAP server setup
  var address = create(CSockAddr)
  initAddress(address)
  address.`addr`.sin.sin_family = Domain.AF_INET.cushort
  address.`addr`.sin.sin_port = posix.htons(5683)

  discard newEndpoint(ctx, address, COAP_PROTO_UDP)

  log.log(lvlInfo, "Cotel networking started on port ",
          posix.ntohs(address.`addr`.sin.sin_port))

  # Establish server resources and request handlers, and also the client
  # response handler.
  var r = initResource(makeStringConst("hi"), 0)
  registerHandler(r, COAP_REQUEST_GET, handleHi)
  addResource(ctx, r)
  registerResponseHandler(ctx, handleResponse)

  # Serve resources until quit
  while true:
    discard processIo(ctx, 500'u32)

    var msgTuple = ctxChan.tryRecv()
    if msgTuple.dataAvailable:
      case msgTuple.msg.req
      of "send_msg":
        send_message(ctx)
      else:
        log.log(lvlError, "msg not understood: " & msgTuple.msg.req)

