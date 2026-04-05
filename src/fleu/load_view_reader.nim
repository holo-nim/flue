{.deprecated: "not up to date".}

import ./[load_reader, load_buffer, reader_common]
import std/[streams, unicode] # just to expose API otherwise not used

export doLineColumn, line, column

when defined(js):
  type BufferView* = string
  type LoadReaderView* = ref LoadReader
elif holoReaderUseViews:
  type BufferView* = cstring
  type LoadReaderView* = var LoadReader
else:
  type BufferView* = cstring
  type LoadReaderView* = ptr LoadReader

type
  LoadViewReader* = object
    ## view type over the `LoadReader` type,
    ## to reduce pointer dereferences
    bufferView*: BufferView
    when BufferView is cstring:
      bufferViewLen*: int
    readerPtr*: LoadReaderView

when defined(js):
  template jsRawSet(a, b) =
    {.emit: [a, " = ", b, ";"].}

  template bufferViewLen*(reader: LoadViewReader): int =
    reader.bufferView.len
  template `buffer=`*(reader: LoadViewReader, s: string) =
    jsRawSet(reader.bufferView, s)
  template `buffer=`*(reader: LoadViewReader, s: typeof(nil)) =
    jsRawSet(reader.bufferView, "null")
  
  proc cannotViewBuffer*(reader: LoadViewReader): bool {.inline.} =
    {.emit: [result, " = ", reader.bufferView, " === null;"].}

  type SourceReader = LoadReader
  template source*(reader: LoadViewReader): LoadReader =
    reader.readerPtr[]
  template `source=`*(reader: LoadViewReader, s: SourceReader) =
    jsRawSet(reader.readerPtr, s)
elif LoadReaderView is ptr:
  template `buffer=`*(reader: LoadViewReader, s: string) =
    reader.bufferView = cstring(s)
    reader.bufferViewLen = s.len
  template `buffer=`*(reader: LoadViewReader, s: typeof(nil)) =
    reader.bufferView = nil

  proc cannotViewBuffer*(reader: LoadViewReader): bool {.inline.} =
    result = reader.bufferView.isNil

  type SourceReader = var LoadReader
  template source*(reader: LoadViewReader): var LoadReader =
    reader.readerPtr[]
  template `source=`*(reader: LoadViewReader, s: SourceReader) =
    reader.readerPtr = addr s
elif holoReaderUseViews:
  template `buffer=`*(reader: LoadViewReader, s: string) =
    reader.bufferView = cstring(s)
    reader.bufferViewLen = s.len
  template `buffer=`*(reader: LoadViewReader, s: typeof(nil)) =
    reader.bufferView = nil

  proc cannotViewBuffer*(reader: LoadViewReader): bool {.inline.} =
    result = reader.bufferView.isNil

  type SourceReader = var LoadReader
  template source*(reader: LoadViewReader): var LoadReader =
    reader.readerPtr
  template `source=`*(reader: LoadViewReader, s: SourceReader) =
    reader.readerPtr = s
else:
  {.error: "unknown way to handle state type: " & $ReaderState.}

template currentBuffer*(reader: LoadViewReader): string = reader.source.currentBuffer
template bufferPos*(reader: LoadViewReader): int = reader.source.bufferPos
template state*(reader: LoadViewReader): ReadState = reader.source.state

{.push checks: off, stacktrace: off.}

proc initLoadViewReader*(original: SourceReader): LoadViewReader {.inline.} =
  result = LoadViewReader()
  result.source = original

proc startRead*(reader: var LoadViewReader, str: sink string) {.inline.} =
  reader.source.startRead(str)
  reader.buffer = reader.source.currentBuffer
  inc reader.source.load.bufferLocks

proc startRead*(reader: var LoadViewReader, loader: BufferLoader, bufferCapacity = 32) {.inline.} =
  reader.source.startRead(loader, bufferCapacity)
  reader.buffer = nil

proc startRead*(reader: var LoadViewReader, stream: Stream, loadAmount = 16, bufferCapacity = 32) {.inline.} =
  reader.startRead(stream, loadAmount, bufferCapacity)
  reader.buffer = nil

when declared(File):
  proc startRead*(reader: var LoadViewReader, file: File, loadAmount = 16, bufferCapacity = 32) {.inline.} =
    reader.startRead(file, loadAmount, bufferCapacity)
    reader.buffer = nil

proc loadBufferOne*(reader: LoadViewReader) {.inline.} =
  if reader.cannotViewBuffer:
    reader.source.callLoader()

proc loadBufferBy*(reader: LoadViewReader, n: int) {.inline.} =
  if reader.cannotViewBuffer:
    reader.source.callLoaderBy(n)

proc peek*(reader: LoadViewReader, c: var char): bool {.inline.} =
  if reader.cannotViewBuffer:
    result = reader.source.peek(c)
  else:
    let nextPos = reader.source.bufferPos + 1
    doPeek(reader.bufferView, reader.bufferViewLen, nextPos, c, result)

proc unsafePeek*(reader: LoadViewReader): char {.inline.} =
  if reader.cannotViewBuffer:
    result = reader.source.unsafePeek()
  else:
    # this is extra unsafe
    result = reader.bufferView[reader.source.bufferPos + 1]

proc peek*(reader: LoadViewReader, c: var char, offset: int): bool {.inline.} =
  if reader.cannotViewBuffer:
    result = reader.source.peek(c, offset)
  else:
    let nextPos = reader.source.bufferPos + 1 + offset
    doPeek(reader.bufferView, reader.bufferViewLen, nextPos, c, result)

proc unsafePeek*(reader: LoadViewReader, offset: int): char {.inline.} =
  if reader.cannotViewBuffer:
    result = reader.source.unsafePeek(offset)
  else:
    # this is extra unsafe
    result = reader.bufferView[reader.source.bufferPos + 1 + offset]

proc peekCount*(reader: LoadViewReader, rune: var Rune): int {.inline.} =
  ## returns rune size if rune is peeked
  if reader.cannotViewBuffer:
    result = reader.source.peekCount(rune)
  else:
    let bpos = reader.source.bufferPos
    if bpos + 1 < reader.bufferViewLen:
      let start = reader.bufferView[bpos + 1]
      result = 0
      let b = start.byte
      var n = 0
      if b shr 5 == 0b110:
        n = 1
      elif b shr 4 == 0b1110:
        n = 2
      elif b shr 3 == 0b11110:
        n = 3
      elif b shr 2 == 0b111110:
        n = 4
      elif b shr 1 == 0b1111110:
        n = 5
      else:
        return
      if bpos + 1 + n < reader.bufferViewLen:
        result = n
        fastRuneAt(reader.bufferView.toOpenArray(0, reader.bufferViewLen - 1), bpos + 1, rune, doInc = false)

proc peek*(reader: LoadViewReader, rune: var Rune): bool {.inline.} =
  result = peekCount(reader, rune) != 0

template peekStrImpl(reader: LoadViewReader, cs) =
  if reader.cannotViewBuffer:
    result = reader.source.peek(cs)
  else:
    result = false
    let n = cs.len
    let bpos = reader.source.bufferPos
    if bpos + n < reader.bufferViewLen:
      result = true
      when nimvm:
        for i in 0 ..< n:
          cs[i] = reader.bufferView[bpos + 1 + i]
      else:
        when not holoReaderPeekStrCopyMem or defined(js) or defined(nimscript):
          for i in 0 ..< n:
            cs[i] = reader.bufferView[bpos + 1 + i]
        else:
          copyMem(addr cs[0], addr reader.bufferView[bpos + 1], n)

proc peek*(reader: LoadViewReader, cs: var openArray[char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peek*[I](reader: LoadViewReader, cs: var array[I, char]): bool {.inline.} =
  peekStrImpl(reader, cs)

proc peekOrZero*(reader: LoadViewReader): char {.inline.} =
  if not peek(reader, result):
    result = '\0'

proc hasNext*(reader: LoadViewReader): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy)

proc hasNext*(reader: LoadViewReader, offset: int): bool {.inline.} =
  var dummy: char
  result = peek(reader, dummy, offset)

proc lockBuffer*(reader: LoadViewReader) {.inline.} =
  if reader.cannotViewBuffer:
    reader.source.lockBuffer()

proc unlockBuffer*(reader: LoadViewReader) {.inline.} =
  if reader.cannotViewBuffer:
    reader.source.unlockBuffer()

proc unsafeNext*(reader: LoadViewReader) {.inline.} =
  reader.source.unsafeNext()

proc unsafeNextBy*(reader: LoadViewReader, n: int) {.inline.} =
  reader.source.unsafeNextBy(n)

proc next*(reader: LoadViewReader, c: var char): bool {.inline.} =
  if not peek(reader, c):
    return false
  result = true
  reader.source.unsafeNext(last = c)

proc next*(reader: LoadViewReader, rune: var Rune): bool {.inline.} =
  let size = peekCount(reader, rune)
  if size == 0:
    return false
  result = true
  reader.source.unsafeNext(last = rune)

proc next*(reader: LoadViewReader): bool {.inline.} =
  var dummy: char
  result = next(reader, dummy)

iterator chars*(reader: LoadViewReader): char =
  var c: char
  while reader.peek(c):
    yield c
    reader.unsafeNext()

iterator peekNext*(reader: LoadViewReader): char {.deprecated.} =
  ## deprecated alias for `chars`
  for c in chars(reader):
    yield c

proc peekMatch*(reader: LoadViewReader, c: char): bool {.inline.} =
  var c2: char
  if reader.peek(c2) and c2 == c:
    result = true
  else:
    result = false

proc nextMatch*(reader: LoadViewReader, c: char): bool {.inline.} =
  result = peekMatch(reader, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: LoadViewReader, c: char, offset: int): bool {.inline.} =
  if reader.cannotViewBuffer:
    result = reader.source.peekMatch(c, offset)
  else:
    let bpos = reader.source.bufferPos
    if bpos + 1 + offset < reader.bufferViewLen:
      if c != reader.bufferView[bpos + 1 + offset]:
        return false
      result = true
    else:
      result = false

proc peekMatch*(reader: LoadViewReader, rune: Rune): bool {.inline.} =
  var rune2: Rune
  if reader.peek(rune2) and rune2 == rune:
    result = true
  else:
    result = false

proc nextMatch*(reader: LoadViewReader, rune: Rune): bool {.inline.} =
  result = peekMatch(reader, rune)
  if result:
    reader.unsafeNextBy(size(rune))

proc peekMatch*(reader: LoadViewReader, cs: set[char], c: var char): bool {.inline.} =
  if reader.peek(c) and c in cs:
    result = true
  else:
    result = false

proc nextMatch*(reader: LoadViewReader, cs: set[char], c: var char): bool {.inline.} =
  result = peekMatch(reader, cs, c)
  if result:
    reader.unsafeNext()

proc peekMatch*(reader: LoadViewReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, dummy)

proc nextMatch*(reader: LoadViewReader, cs: set[char]): bool {.inline.} =
  var dummy: char
  result = reader.nextMatch(cs, dummy)

proc peekMatch*(reader: LoadViewReader, cs: set[char], offset: int, c: var char): bool {.inline.} =
  if reader.cannotViewBuffer:
    result = reader.source.peekMatch(cs, offset, c)
  else:
    let bpos = reader.source.bufferPos
    if bpos + 1 + offset < reader.bufferViewLen:
      let c2 = reader.bufferView[bpos + 1 + offset]
      if c2 in cs:
        c = c2
        return true
      result = false
    else:
      result = false

proc peekMatch*(reader: LoadViewReader, cs: set[char], offset: int): bool {.inline.} =
  var dummy: char
  result = reader.peekMatch(cs, offset, dummy)

template peekMatchStrImpl(reader: LoadViewReader, str) =
  if reader.cannotViewBuffer:
    result = reader.source.peekMatch(str)
  else:
    let bpos = reader.source.bufferPos
    if bpos + str.len < reader.bufferViewLen:
      for i in 0 ..< str.len:
        if str[i] != reader.bufferView[bpos + 1 + i]:
          return false
      result = true
    else:
      result = false

proc peekMatch*(reader: LoadViewReader, str: openArray[char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*[I](reader: LoadViewReader, str: array[I, char]): bool {.inline.} =
  peekMatchStrImpl(reader, str)

proc peekMatch*(reader: LoadViewReader, str: static string): bool {.inline.} =
  # maybe make a const array
  peekMatchStrImpl(reader, str)

proc nextMatch*(reader: LoadViewReader, str: openArray[char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*[I](reader: LoadViewReader, str: array[I, char]): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

proc nextMatch*(reader: LoadViewReader, str: static string): bool {.inline.} =
  result = peekMatch(reader, str)
  if result:
    reader.unsafeNextBy(str.len)

{.pop.}
