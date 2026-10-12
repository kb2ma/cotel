# Cotel artifact builder. Run against main module, like below:
#
#    $ nim <task> src/gui/main

# hide the noisy messages
hint("Conf", false)
hint("Processing", false)

task build, "Build executable":
  #switch("forceBuild", "on")
  switch("path", "src")
  switch("out", "cotel")
  switch("outdir", "build/bin")
  switch("debugger", "native")
  #switch("define", "release")
  # nimgl/imgui's impl_glfw.nim declares its clipboard callbacks with a plain
  # cstring where ImGuiIO expects const char*; newer GCC/Clang treat that
  # mismatch as a hard error by default.
  switch("passC", "-Wno-error=incompatible-pointer-types")
  setCommand("c")

task buildRelease, "Build release executable":
  switch("path", "src")
  switch("out", "cotel")
  switch("outdir", "build/bin")
  switch("define", "release")
  switch("passC", "-Wno-error=incompatible-pointer-types")
  setCommand("c")

task lint, "Check executable":
  # Run in a separate process (rather than setCommand("check") directly):
  # `nim check` invoked from within a task shares compiler state with the
  # task's own NimScript evaluation, corrupting the system module and
  # producing bogus errors instead of real ones.
  selfExec("check --path:src " & paramStr(paramCount()))

task docs, "Build doc html":
  switch("project") 
  switch("outdir", "build/doc") 
  setCommand("doc")
