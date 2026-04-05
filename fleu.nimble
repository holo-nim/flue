# Package

version       = "0.1.0"
author        = "metagn"
description   = "data streaming using a dynamic buffer"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.0"

task docs, "build docs for all modules":
  exec "nim r tasks/build_docs.nim"

task tests, "run tests for multiple backends and defines":
  exec "nim r tasks/run_tests.nim"
