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
  setCommand("c")

task docs, "Build doc html":
  switch("project") 
  switch("outdir", "build/doc") 
  setCommand("doc")
