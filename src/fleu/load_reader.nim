import ./[load_buffer, reader_common]
import std/[streams, unicode] # just to expose API otherwise not used

export doLineColumn, line, column

{.push checks: off, stacktrace: off.}

type
  LoadState* = object
    buffer*: LoadBuffer
    bufferLocks*: int

proc startLoad*(load: var LoadState, str: sink string) {.inline.} =
  load.buffer = initLoadBuffer(str)
  load.bufferLocks = 0

proc startLoad*(load: var LoadState, loader: BufferLoader, bufferCapacity = 32) {.inline.} =
  load.buffer = initLoadBuffer(loader, bufferCapacity)
  load.bufferLocks = 0

proc startLoad*(load: var LoadState, stream: Stream, loadAmount = 16, bufferCapacity = 32) {.inline.} =
  load.buffer = initLoadBuffer(stream, loadAmount, bufferCapacity)
  load.bufferLocks = 0

when declared(File):
  proc startLoad*(load: var LoadState, file: File, loadAmount = 16, bufferCapacity = 32) {.inline.} =
    ## `file` has to last as long as the loader
    load.buffer = initLoadBuffer(file, loadAmount, bufferCapacity)
    load.bufferLocks = 0

type
  LoadReader* = object
    state*: ReadState
    load*: LoadState
  TrackedLoadReader* = object
    state*: TrackedReadState
    load*: LoadState

proc initLoadReader*(): LoadReader {.inline.} =
  result = LoadReader(state: initReadState())

proc initLoadReader*(doLineColumn: bool): LoadReader {.inline, deprecated: "line column option is ignored, use tracked load reader".} =
  result = initLoadReader()

proc initTrackedLoadReader*(doLineColumn = holoReaderLineColumn): TrackedLoadReader {.inline.} =
  result = TrackedLoadReader(state: initTrackedReadState(doLineColumn))

template LoadReaderType: untyped = LoadReader

include includes/load_reader_impl

template LoadReaderType: untyped {.redefine.} = TrackedLoadReader

include includes/load_reader_impl

{.pop.}
