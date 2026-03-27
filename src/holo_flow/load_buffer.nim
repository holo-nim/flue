import ./stringresize
import std/streams  # just to expose API otherwise not used

type
  BufferLoader* = proc (): string
  LoadBuffer* = object
    data*: string
      ## buffer string, users need to access directly & keep track of position
    loader*: BufferLoader
      ## loads a string at a time to add to the buffer when needed
      ## set to nil after returning empty string
    freeBefore*: int
      ## position before which we can cull the buffer

{.push checks: off, stacktrace: off.}

proc initLoadBuffer*(str: sink string): LoadBuffer {.inline.} =
  result = LoadBuffer(data: str, loader: nil)

proc initLoadBuffer*(loader: BufferLoader, capacity = 32): LoadBuffer {.inline.} =
  result = LoadBuffer(data: newStringOfCap(capacity), loader: loader)

proc initLoadBuffer*(stream: Stream, loadAmount = 16, capacity = 32): LoadBuffer {.inline.} =
  let loader = proc (): string =
    readStr(stream, loadAmount)
  result = initLoadBuffer(loader, capacity)

when declared(File):
  proc initLoadBuffer*(file: File, loadAmount = 16, capacity = 32): LoadBuffer {.inline.} =
    ## `file` has to last as long as the reader
    var buf = newString(loadAmount) # save allocations by capturing this in the loader, array would need constant load amount
    let loader = proc (): string =
      let n = readChars(file, buf)
      buf.setLen(n)
      result = buf
    result = initLoadBuffer(loader, capacity)

proc callLoader*(buffer: var LoadBuffer): int =
  ## for internal use, only called if buffer loader is known not to be nil
  ## returns number of moved chars
  # probably better not to inline
  result = 0
  let ex = buffer.loader()
  if ex.len == 0:
    buffer.loader = nil
    return
  let moved = buffer.data.smartResizeAdd(ex, buffer.freeBefore)
  if moved:
    result = buffer.freeBefore
    buffer.freeBefore = 0

proc loadOnce*(buffer: var LoadBuffer): int {.inline.} =
  ## returns number of moved chars
  result = 0
  if not buffer.loader.isNil:
    result = buffer.callLoader()

proc callLoaderBy*(buffer: var LoadBuffer, n: int): int =
  ## for internal use, only called if buffer loader is known not to be nil
  ## returns number of moved chars
  # probably better not to inline
  result = 0
  var left = n
  while left > 0:
    let ex = buffer.loader()
    if ex.len == 0:
      buffer.loader = nil
      return
    let moved = buffer.data.smartResizeAdd(ex, buffer.freeBefore)
    if moved:
      result += buffer.freeBefore
      buffer.freeBefore = 0
    left -= ex.len

proc loadBy*(buffer: var LoadBuffer, n: int): int {.inline.} =
  ## returns number of moved chars
  result = 0
  if not buffer.loader.isNil:
    result = buffer.callLoaderBy(n)

{.pop.}
