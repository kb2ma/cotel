## Straightforward wrapper module for libcoap. Click on the `{...}` for a proc
## to see the corresponding libcoap function name. libcoap provides
## [online documentation](https://libcoap.net/doc/reference/4.2.1/), or you
## may build it yourself from [source](https://github.com/obgm/libcoap).
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

const useWinVersion = defined(Windows) or defined(nimdoc)
when useWinVersion:
  import winlean
else:
  import posix
import nativesockets

# only supports Linux at present
const libName = "libcoap-2.so"

type
  CProto* = uint8
  ## coap_proto_t

  CTxid* = cint

const
  COAP_PROTO_NONE* = 0.CProto
  COAP_PROTO_UDP* = 1.CProto
  COAP_PROTO_DTLS* = 2.CProto
  COAP_PROTO_TCP* = 3.CProto
  COAP_PROTO_TLS* = 4.CProto

  # Message types
  COAP_MESSAGE_CON* = 0'u8
  COAP_MESSAGE_NON* = 1'u8
  COAP_MESSAGE_ACK* = 2'u8
  COAP_MESSAGE_RST* = 3'u8

  COAP_RESPONSE_CODE_201* = ((2 shl 5) or 1).uint8
  COAP_RESPONSE_CODE_202* = ((2 shl 5) or 2).uint8
  COAP_RESPONSE_CODE_204* = ((2 shl 5) or 4).uint8
  COAP_RESPONSE_CODE_205* = ((2 shl 5) or 5).uint8
  COAP_RESPONSE_CODE_404* = ((4 shl 5) or 4).uint8

  COAP_INVALID_TXID* = -1.CTxid
  COAP_IO_WAIT* = 0

type
  CRequestCode* = enum
    ## coap_request_t, and value is 'detail' portion of request method code
    COAP_REQUEST_GET = 1,
    COAP_REQUEST_POST,
    COAP_REQUEST_PUT,
    COAP_REQUEST_DELETE,
    COAP_REQUEST_PATCH,
    COAP_REQUEST_IPATCH

  CLogLevel* = enum
    ## coap_log_t logging levels
    LOG_EMERG,
    LOG_ALERT,
    LOG_CRIT,
    LOG_ERR,
    LOG_WARNING,
    LOG_NOTICE,
    LOG_INFO,
    LOG_DEBUG,
    COAP_LOG_CIPHERS

  COptionId* = enum
    ## libcoap COAP_OPTION... constants as an enum
    OPTION_IF_MATCH =        1, # opaque, 0-8 B
    OPTION_URI_HOST =        3, # String, 1-255 B
    OPTION_ETAG =            4, # opaque, 1-8 B
    OPTION_IF_NONE_MATCH =   5, # empty,  0 B
    OPTION_OBSERVE =         6, # empty/uint, 0 B/0-3 B
    OPTION_URI_PORT =        7, # uint, 0-2 B
    OPTION_LOCATION_PATH =   8, # String, 0-255 B
    OPTION_URI_PATH =       11, # String, 0-255 B
    OPTION_CONTENT_FORMAT = 12, # uint, 0-2 B
    OPTION_MAXAGE =         14, # uint, 0-4 B, default 60 Seconds
    OPTION_URI_QUERY =      15, # String, 1-255 B
    OPTION_ACCEPT =         17, # uint, 0-2 B
    OPTION_LOCATION_QUERY = 20, # String, 0-255 B
    OPTION_BLOCK2 =         23, # uint, 0-3 B
    OPTION_BLOCK1 =         27, # uint, 0-3 B
    OPTION_SIZE2 =          28, # uint, 0-4 B
    OPTION_PROXY_URI =      35, # String, 1-1034 B
    OPTION_PROXY_SCHEME =   39, # String, 1-255 B
    OPTION_SIZE1 =          60, # uint, 0-4 B
    OPTION_NORESPONSE =    258  # uint, 0-1 B

  CSockAddrUnion* {.union} = object
    ## Used only by CSockAddr
    sa*: SockAddr
    sin*: Sockaddr_in
    sin6*: Sockaddr_in6

  CSockAddr* {.importc: "struct coap_address_t",
              header: "<coap2/address.h>".} = object
    ## libcoap internal socket address
    size*: SockLen
    `addr`*: CSockAddrUnion

  CAddrTuple* {.importc: "struct coap_addr_tuple_t",
               header: "<coap2/coap_io.h>".} = object
    remote*: CSockAddr
    local*: CSockAddr

  CStringConst* {.importc: "struct coap_str_const_t",
                 header: "<coap2/str.h>"} = ptr object

  CHashHandle* {.importc: "struct UT_hash_handle",
                header: "<coap2/uthash.h>".} = object

  CContext* {.importc: "struct coap_context_t",
                 header: "<coap2/net.h>"} = ptr object
    ## libcoap top-level data object; libcoap always manages heap memory
    #response_handler*: pointer

  CEndpoint* = ptr object
    ## libcoap coap_endpoint_t
    proto*: CProto

  CResource* {.importc: "struct coap_resource_t",
                 header: "<coap2/resource.h>"} = ptr object

  CSession* {.importc: "struct coap_session_t",
                 header: "<coap2/coap_session.h>"} = ptr object
    proto*: CProto
    `type`*: uint8
    state*: uint8
    `ref`*: cuint
    tls_overhead*: cuint
    mtu*: culonglong
    local_if*: CSockAddr
    hh*: CHashHandle
    addr_info*: CAddrTuple
    ifindex*: cint

  CPdu* = ptr object
    ## coap_pdu_t
    `type`*: uint8
    code*: uint8

  COptlist* = ptr object

  CCoapBinary* = ptr object

  CCoapString* {.importc: "struct coap_string_t",
                 header: "<coap2/str.h>"} = ptr object

  CRequestHandler* = proc (context: CContext, resource: CResource,
                           session: CSession, req: CPdu, token: CCoapString,
                           query: CCoapString, resp: CPdu) {.noconv.}

  CResponseHandler* = proc (context: CContext, session: CSession, sent: CPdu,
                            received: CPdu, id: CTxid) {.noconv.}

  CLogHandler* = proc (level: CLogLevel, message: cstring) {.noconv.}


{.push dynlib: libName.}
# net.h
proc freeContext*(context: CContext) {.importc: "coap_free_context".}

proc newContext*(listen_addr: ptr CSockAddr): CContext
                {.importc: "coap_new_context".}

# Must include header pragma because library function is 'static inline'.
proc registerResponseHandler*(context: CContext, handler: CResponseHandler)
                             {.header: "coap2/net.h",
                               importc: "coap_register_response_handler".}

proc send*(session: CSession, pdu: CPdu): CTxid {.importc: "coap_send".}

proc setContextPsk*(context: CContext, hint: cstring, key: ptr uint8,
                    key_len: csize_t): cint {.importc: "coap_context_set_psk".}

# coap_session.h
proc findSession*(context: CContext, remote: ptr CSockAddr,
                  if_index: cint): CSession
                 {.importc: "coap_session_get_by_peer".}

proc freeEndpoint*(ep: CEndpoint) {.importc: "coap_free_endpoint".}

proc maxSessionPduSize*(session: CSession): csize_t
                       {.importc: "coap_session_max_pdu_size".}

proc newClientSession*(context: CContext, local_addr: ptr CSockAddr,
                       server_addr: ptr CSockAddr, proto: CProto): CSession
                      {.importc: "coap_new_client_session".}

proc newClientSessionPsk*(context: CContext, local_addr: ptr CSockAddr,
                          server_addr: ptr CSockAddr, proto: CProto,
                          identity: cstring, key: ptr uint8,
                          key_len: uint): CSession
                         {.importc: "coap_new_client_session_psk".}

proc newEndpoint*(context: CContext, listen_addr: ptr CSockAddr,
                 proto: CProto): CEndpoint {.importc: "coap_new_endpoint".}

proc releaseSession*(session: CSession) {.importc: "coap_session_release".}

# resource.h
proc addResource*(context: CContext, resource: CResource)
                 {.importc: "coap_add_resource".}

proc initResource*(uri_path: CStringConst, flags: cint): CResource
                  {.importc: "coap_resource_init".}

proc registerHandler*(resource: CResource, `method`: CRequestCode,
                      handler: CRequestHandler)
                     {.importc: "coap_register_handler".}

# pdu.h
proc addData*(pdu: CPdu, len: csize_t, data: cstring): cint
             {.importc: "coap_add_data".}

proc deletePdu*(pdu: CPdu) {.importc: "coap_delete_pdu".}

proc getData*(pdu: CPdu, len: ptr csize_t, data: ptr ptr uint8): cint
             {.importc: "coap_get_data".}

proc initPdu*(`type`: uint8, code: uint8, txid: uint16 = 0, size: csize_t): CPdu
             {.importc: "coap_pdu_init".}
  ## 'type' is one of the COAP_MESSAGE... constants
  ## 'code' param value is CRequestCode for a request

# option.h
proc addOptlistPdu*(pdu: CPdu, chain: ptr COptlist): cint
                   {.importc: "coap_add_optlist_pdu".}

proc deleteOptlist*(list: COptlist) {.importc: "coap_delete_optlist".}
  ## Must delete optlist created by newOptlist

proc insertOptlist*(chain: ptr COptlist, optlist: COptlist): cint
                   {.importc: "coap_insert_optlist".}
 
proc newOptlist*(number: uint16, length: csize_t, data: ptr uint8): COptlist
                {.importc: "coap_new_optlist".}

# coap_io.h
proc processIo*(context: CContext, timeout: uint32): cint
               {.importc: "coap_io_process".}

# coap_dtls.h
proc setDtlsLogLevel*(level: CLogLevel) {.importc: "coap_dtls_set_log_level".}

# address.h
proc initAddress*(address: ptr CSockAddr) {.importc: "coap_address_init".}

# str.h
proc makeStringConst*(str: cstring): CStringConst
                     {.importc: "coap_make_str_const".}

# coap_internal.h
proc encodeVarSafe*(buf: ptr uint8, length: csize_t, value: uint): cuint
                   {.importc: "coap_encode_var_safe".}

# coap_debug.h
proc setLogHandler*(handler: CLogHandler) {.importc: "coap_set_log_handler".}

proc setLogLevel*(level: CLogLevel) {.importc: "coap_set_log_level".}
{.pop.}
