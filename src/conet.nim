## Conet: Cotel networking
##
## Runs libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import libcoap, posix, nativesockets
import json, logging, parseutils
import conet_ctx
# Provides the core context data for conet module users to share
export conet_ctx

type
  ConetState* = ref object
    ## State for Conet; intended only for internal use
    securityMode*: SecurityMode
    serverPort*: int
    pskKey*: seq[char]
    pskClientId*: string

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
  #oplog.log(lvlDebug, "Response received")
  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(received, addr dataLen, addr dataPtr)

  var dataStr = newString(dataLen)
  copyMem(addr dataStr[0], dataPtr, dataLen)
  netChan.send( CoMsg(req: "response.payload", payload: dataStr) )


proc sendMessage(ctx: CContext, state: ConetState, jsonStr: string) =
  ## Send a message to exercise client flow with a server.
  let reqJson = parseJson(jsonStr)

  # init server address/port
  let address = create(CSockAddr)
  initAddress(address)
  try:
    let port = reqJson["remPort"].getInt()
    let info = getAddrInfo("127.0.0.1", port.Port, Domain.AF_INET,
                           SockType.SOCK_DGRAM, Protocol.IPPROTO_UDP)
    address.size = sizeof(SockAddr_in).SockLen
    address.`addr`.sin = cast[SockAddr_in](info.ai_addr[])
    freeaddrinfo(info)
  except OSError:
    oplog.log(lvlError, "Can't resolve server address")
    return

  #init session
  var session: CSession
  if getStr(reqJson["proto"]) == "coaps":
    # Assume libcoap retains PSK session, so look for it. Also assume use of
    # local interface 0.
    session = findSession(ctx, address, 0)
    if session == nil:
      session = newClientSessionPsk(ctx, nil, address, COAP_PROTO_DTLS,
                                    state.pskClientId,
                                    cast[ptr uint8](addr state.pskKey[0]),
                                    state.pskKey.len.uint)
  else:
    # proto must be 'coap'
    session = newClientSession(ctx, nil, address, COAP_PROTO_UDP)
  if session == nil:
    oplog.log(lvlError, "Can't create client session")
    return

  # init PDU, including type and code
  var msgType: uint8
  if reqJson["msgType"].getStr() == "CON":
    msgType = COAP_MESSAGE_CON
  else:
    msgType = COAP_MESSAGE_NON

  var pdu = initPdu(msgType, COAP_REQUEST_GET.uint8, 1000'u16,
                    maxSessionPduSize(session))
  if pdu == nil:
    oplog.log(lvlError, "Can't create client PDU")
    releaseSession(session)
    return

  # add Uri-Path options
  let uriPath = reqJson["uriPath"].getStr()
  var pos = 0
  var chain: COptlist

  while pos < uriPath.len:
    var token: string
    let plen = parseUntil(uriPath, token, '/', pos)
    #echo("start pos: ", pos, ", token: ", token, " of len ", plen)
    if plen > 0:
      let optlist = newOptlist(COAP_OPTION_URI_PATH, token.len.csize_t,
                               cast[ptr uint8](token.cstring))
      if optlist == nil:
        oplog.log(lvlError, "Can't create option list")
        return
      if insertOptlist(addr chain, optlist) == 0:
        oplog.log(lvlError, "Can't add to option chain")
        return
    pos = pos + plen + 1

  # Path may just be "/". No PDU option in that case.
  if chain == nil and uriPath != "/":
    oplog.log(lvlError, "Can't create option list")
    return
  if chain != nil and addOptlistPdu(pdu, addr chain) == 0:
    oplog.log(lvlError, "Can't create option list")
    deleteOptlist(chain)
    deletePdu(pdu)
    releaseSession(session)
    return
  deleteOptlist(chain)

  # send
  if send(session, pdu) == COAP_INVALID_TXID:
    deletePdu(pdu)


proc netLoop*(state: ConetState) =
  ## Setup server and run event loop
  oplog = newFileLogger("net.log", fmtStr="[$time] $levelname: ", bufSize=0)
  open(netChan)
  open(ctxChan)

  # init context, listen port/endpoint
  var ctx = newContext(nil)

  # CoAP server setup
  var address = create(CSockAddr)
  initAddress(address)
  address.`addr`.sin.sin_family = Domain.AF_INET.cushort
  address.`addr`.sin.sin_port = posix.htons(state.serverPort.uint16)

  var proto: CProto
  var secMode: string
  case state.securityMode
  of SECURITY_MODE_PSK:
    if setContextPsk(ctx, "", cast[ptr uint8](addr state.pskKey[0]),
                     state.pskKey.len.csize_t) == 0:
      oplog.log(lvlError, "Can't set context PSK")
      return
    proto = COAP_PROTO_DTLS
    secMode = "PSK"
  of SECURITY_MODE_NOSEC:
    proto = COAP_PROTO_UDP
    secMode = "NoSec"

  discard newEndpoint(ctx, address, proto)

  oplog.log(lvlInfo, "Cotel networking ", secMode, " started on port ",
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
        send_message(ctx, state, msgTuple.msg.payload)
      of "quit":
        break
      else:
        oplog.log(lvlError, "msg not understood: " & msgTuple.msg.req)

  if ctx != nil:
    freeContext(ctx)
  oplog.log(lvlInfo, "Exiting net gracefully")
