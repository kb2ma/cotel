# Cotel artifact builder

# hide the noisy messages
hint("Conf", false)
hint("Processing", false)

task build, "Build executable":
  switch("out", "cotel")
  switch("outdir", "build/bin") 
  switch("debugger", "native")
  setCommand("c")

task docs, "Deploy doc html + search index to build/doc directory":
  #selfExec("doc --project --outdir:build/doc gui")
  switch("project") 
  switch("outdir", "build/doc") 
  setCommand("doc")
