setClass("H2OClient", representation(ip="character", port="numeric"), prototype(ip="127.0.0.1", port=54321))
setGeneric("h2o.init", function(ip = "127.0.0.1", port = 54321, startH2O = TRUE, silentUpgrade = FALSE, promptUpgrade = TRUE, Xmx = "2g") { standardGeneric("h2o.init") })
# setGeneric("h2o.shutdown", function(ip = "127.0.0.1", port = 54321, prompt = TRUE) { standardGeneric("h2o.shutdown") })
setGeneric("h2o.shutdown", function(object, prompt = TRUE) { standardGeneric("h2o.shutdown") })

h2o.__PAGE_RPACKAGE = "RPackage.json"
h2o.__PAGE_SHUTDOWN = "Shutdown.json"

setMethod("show", "H2OClient", function(object) {
  cat("IP Address:", object@ip, "\n")
  cat("Port      :", object@port, "\n")
})

# Checks H2O connection and installs H2O R package matching version on server if indicated by user
# 1) If can't connect and user doesn't want to start H2O, stop immediately
# 2) If user does want to start H2O and running locally, attempt to bring up H2O launcher
# 3) If user does want to start H2O, but running non-locally, print an error
setMethod("h2o.init", signature(ip="character", port="numeric", startH2O="logical", silentUpgrade="logical", promptUpgrade="logical", Xmx="character"), 
          function(ip, port, startH2O, silentUpgrade, promptUpgrade, Xmx) {
  myURL = paste("http://", ip, ":", port, sep="")
  if(!url.exists(myURL)) {
    if(!startH2O)
      stop(paste("Cannot connect to H2O server. Please check that H2O is running at", myURL))
    else if(ip=="localhost" || ip=="127.0.0.1") {
      cat("\n")
      cat("H2O is not running yet, starting it now...\n")
      # h2oWrapper.startLauncher()
      # invisible(readline("Start H2O, then hit <Return> to continue: "))
      h2o.startJar(Xmx)
      count = 0; while(!url.exists(myURL) && count < 10) { Sys.sleep(1); count = count + 1 }
      if(!url.exists(myURL)) stop("H2O failed to start, stopping execution.")
    } else stop("Can only start H2O launcher if IP address is localhost")
  }
  cat("Successfully connected to", myURL, "\n")
  h2o.checkPackage(myURL, silentUpgrade, promptUpgrade)
  
  if("package:h2oRClient" %in% search())
    detach("package:h2oRClient", unload=TRUE)
  if("h2oRClient" %in% installed.packages()[,1])
    library(h2oRClient)
  return(new("H2OClient", ip = ip, port = port))
})

setMethod("h2o.init", signature(ip="ANY", port="ANY", startH2O="ANY", silentUpgrade="ANY", promptUpgrade="ANY", Xmx="ANY"), 
          function(ip, port, startH2O, silentUpgrade, promptUpgrade, Xmx) {
  if(!(missing(ip) || class(ip) == "character"))
    stop(paste("ip cannot be of class", class(ip)))
  if(!(missing(port) || class(port) == "numeric"))
    stop(paste("port cannot be of class", class(port)))
  if(!(missing(startH2O) || class(startH2O) == "logical"))
    stop(paste("startH2O cannot be of class", class(startH2O)))
  if(!(missing(silentUpgrade) || class(silentUpgrade) == "logical"))
    stop(paste("silentUpgrade cannot be of class", class(silentUpgrade)))
  if(!(missing(promptUpgrade) || class(promptUpgrade) == "logical"))
    stop(paste("promptUpgrade cannot be of class", class(promptUpgrade)))
  if(!(missing(Xmx) || is.character(Xmx)))
    stop(paste("Xmx cannot be of class", class(Xmx)))
  if(!missing(Xmx) && !regexpr("^[1-9][0-9]*[gGmM]$", Xmx))
    stop("Xmx option must be like 2g or 1024m")
  h2o.init(ip, port, startH2O, silentUpgrade, promptUpgrade, Xmx)
})

# Shuts down H2O instance running at given IP and port
setMethod("h2o.shutdown", signature(object="H2OClient", prompt="logical"),
  function(object, prompt) {
    myURL = paste("http://", object@ip, ":", object@port, sep="")
    if(!url.exists(myURL)) stop(paste("There is no H2O instance running at", myURL))
    if(prompt) {
        ans = readline(paste("Are you sure you want to shutdown the H2O instance running at", myURL, "(Y/N)? "))
        temp = substr(ans, 1, 1)
    } else temp = "y"
    if(temp == "Y" || temp == "y") {
      res = getURLContent(paste(myURL, h2o.__PAGE_SHUTDOWN, sep="/"))
      res = fromJSON(res)
      if(!is.null(res$error))
        stop(paste("Unable to shutdown H2O. Server returned the following error:\n", res$error))
    }
    # if(url.exists(myURL)) stop("H2O failed to shutdown.")
})

setMethod("h2o.shutdown", signature(object="ANY", prompt="ANY"),
  function(object, prompt) {
    if(!(missing(object) || class(object) == "H2OClient"))
      stop(paste("object cannot be of class", class(object)))
    if(!(missing(prompt) || is.logical(prompt)))
      stop(paste("prompt cannot be of class", class(prompt)))
    h2o.shutdown(object, prompt)
})

#-------------------------------- Helper Methods --------------------------------#
# NB: if H2OVersion matches \.99999$ is a development version, so pull package info out of file.  yes this is a hack
#     but it makes development versions properly prompt upgrade
h2o.checkPackage <- function(myURL, silentUpgrade, promptUpgrade) {
  temp = postForm(paste(myURL, h2o.__PAGE_RPACKAGE, sep="/"), style = "POST")
  res = fromJSON(temp)
  if (!is.null(res$error))
    stop(paste(myURL," returned the following error:\n", h2oWrapper.__formatError(res$error)))

  H2OVersion = res$version
  myFile = res$filename
  serverMD5 = res$md5_hash

  if( grepl('\\.99999$', H2OVersion) ){
    H2OVersion <- sub('\\.tar\\.gz$', '', sub('.*_', '', myFile))
  }

  # sigh. I so wish people would occasionally listen to me; R expects a version to be %d.%d.%d.%d and will ignore anything after
  myPackages <- installed.packages()[,1]
  needs_upgrade <- F
  if( 'h2oRClient' %in% myPackages ){
    ver <- unclass( packageVersion('h2oRClient') )
    ver <- paste( ver[[1]], collapse='.' )
    needs_upgrade <- !(ver == H2OVersion)
  }

  if("h2oRClient" %in% myPackages && !needs_upgrade )
    cat("H2O R package and server version", H2OVersion, "match\n")
  else if(h2o.shouldUpgrade(silentUpgrade, promptUpgrade, H2OVersion)) {
    if("h2oRClient" %in% myPackages) {
      cat("Removing old H2O R package version", toString(packageVersion("h2oRClient")), "\n")
      remove.packages("h2oRClient")
    }
    cat("Downloading and installing H2O R package version", H2OVersion, "\n")
    # download.file(paste(myURL, "R", myFile, sep="/"), destfile = paste(getwd(), myFile, sep="/"), mode = "wb")
    temp = getBinaryURL(paste(myURL, "R", myFile, sep="/"))
    writeBin(temp, paste(getwd(), myFile, sep="/"))

    if(as.character(serverMD5) != as.character(md5sum(paste(getwd(), myFile, sep="/"))))
      warning("Mismatched MD5 hash! Check you have downloaded complete R package.")
    install.packages(paste(getwd(), myFile, sep="/"), repos = NULL, type = "source")
    file.remove(paste(getwd(), myFile, sep="/"))
  }
}

# Check if user wants to install H2O R package matching version on server
# Note: silentUpgrade supercedes promptUpgrade
h2o.shouldUpgrade <- function(silentUpgrade, promptUpgrade, H2OVersion) {
  if(silentUpgrade) return(TRUE)
  if(promptUpgrade) {
    ans = readline(paste("Do you want to install H2O R package", H2OVersion, "from the server (Y/N)? "))
    temp = substr(ans, 1, 1)
    if(temp == "Y" || temp == "y") return(TRUE)
    else if(temp == "N" || temp == "n") return(FALSE)
    else stop("Invalid answer! Please enter Y for yes or N for no")
  } else return(FALSE)
}

h2oWrapper.__formatError <- function(error, prefix="  ") {
  result = ""
  items = strsplit(error,"\n")[[1]];
  for (i in 1:length(items))
    result = paste(result, prefix, items[i], "\n", sep="")
  result
}

#---------------------------- H2O Jar Initialization -------------------------------#
.h2o.pkg.path <- NULL

.onLoad <- function(lib, pkg) {
  .h2o.pkg.path <<- paste(lib, pkg, sep = .Platform$file.sep)
  
  # Install and load H2O R package dependencies
  require(tools)
  myPackages = rownames(installed.packages())
  myReqPkgs = c("bitops", "RCurl", "rjson", "statmod")
  temp = lapply(myReqPkgs, function(x) { if(!x %in% myPackages) { cat("Installing package dependency", x, "\n"); install.packages(x, repos = "http://cran.rstudio.com/") }
                                         if(!require(x, character.only = TRUE)) stop("The required package ", x, " is not installed. Please type install.packages(\"", x, "\") to install the dependency from CRAN.") })
}

.onAttach <- function(libname, pkgname) {
  msg = paste(
    "\n",
    "----------------------------------------------------------------------\n",
    "\n",
    "Your next step is to start H2O and get a connection object (named\n",
    "'localH2O', for example):\n",
    "    > localH2O = h2o.init()\n",
    "\n",
    "For H2O package documentation, first call init() and then ask for help:\n",
    "    > localH2O = h2o.init()\n",
    "    > ??h2o\n",
    "\n",
    "To stop H2O you must explicitly call shutdown (either from R, as shown\n",
    "here, or from the Web UI):\n",
    "    > h2o.shutdown(localH2O)\n",
    "\n",
    "After starting H2O, you can use the Web UI at http://localhost:54321\n",
    "For more information visit http://docs.0xdata.com\n",
    "\n",
    "----------------------------------------------------------------------\n",
    sep = "")
  packageStartupMessage(msg)
}

h2o.startJar <- function(memory = "2g") {
  command <- Sys.which("java")
  #
  # TODO: tmp files should be user-independent
  #
  
  if(.Platform$OS.type == "windows") {
    stdout <- "C:/tmp/h2o_started_from_r.out"
    stderr <- "C:/tmp/h2o_started_from_r.err"
  } else {
    stdout <- "/tmp/h2o_started_from_r.out"
    stderr <- "/tmp/h2o_started_from_r.err"
  }
  
  jar_file <- paste(.h2o.pkg.path, "java", "h2o.jar", sep = .Platform$file.sep)
  jar_file <- paste('"', jar_file, '"', sep = "")
  args <- c(paste("-Xmx", memory, sep=""),
            "-jar", jar_file,
            "-name", "H2O_started_from_R",
            "-ip", "127.0.0.1",
            "-port", "54321"
            )
  cat("\n")
  cat(        "Note:  In case of errors look at the following log files:\n")
  cat(sprintf("           %s\n", stdout))
  cat(sprintf("           %s\n", stderr))
  cat("\n")
  system2(command, c("-version"))
  cat("\n")
  rc = system2(command,
               args=args,
               stdout=stdout,
               stderr=stderr,
               wait=FALSE)
  if (rc != 0) {
    stop(sprintf("Failed to exec %s", jar_file))
  }
}

#---------------------------------- Deprecated ----------------------------------#
# Start H2O launcher GUI if installed locally from InstallBuilder executable
h2oWrapper.startLauncher <- function() {
  myOS = Sys.info()["sysname"]
  
  if(myOS == "Windows") verPath = paste(Sys.getenv("APPDATA"), "h2o", sep="/")
  else verPath = paste(Sys.getenv("HOME"), "Library/Application Support/h2o", sep="/")
  myFiles = list.files(verPath)
  if(length(myFiles) == 0) stop("Cannot find location of H2O launcher. Please check that your H2O installation is complete.")
  # Must trim myFiles so all have format 1.2.3.45678.txt (use regexpr)!
  
  # Get H2O with latest version number
  # If latest isn't working, maybe go down list to earliest until one executes?
  fileName = paste(verPath, tail(myFiles, n=1), sep="/")
  myVersion = strsplit(tail(myFiles, n=1), ".txt")[[1]]
  launchPath = readChar(fileName, file.info(fileName)$size)
  if(is.null(launchPath) || launchPath == "")
    stop(paste("No H2O launcher matching H2O version", myVersion, "found"))
  
  cat("Launching H2O version", myVersion)
  if(myOS == "Windows") {
    tempPath = paste(launchPath, "windows/h2o.bat", sep="/")
    if(!file.exists(tempPath)) stop(paste("Cannot open H2OLauncher.jar! Please check if it exists at", tempPath))
    shell.exec(tempPath)
  }
  else {
    tempPath = paste(launchPath, "Contents/MacOS/h2o", sep="/")
    if(!file.exists(tempPath)) stop(paste("Cannot open H2OLauncher.jar! Please check if it exists at", tempPath))
    system(paste("bash ", tempPath))
  }
}

h2o.__genScript <- function(target = NULL, memory = "2g") {
  if(.Platform$OS.type == "windows")
    run.template <- paste(.h2o.pkg.path, "scripts", "h2o.bat.TEMPLATE", sep = .Platform$file.sep)
  else
    run.template <- paste(.h2o.pkg.path, "scripts", "h2o.TEMPLATE", sep = .Platform$file.sep)
  rt <- readLines(run.template)
  
  settings <- c("JAVA_HOME", "JAVA_PROG", "H2O_JAR", "FLAT", "MEM")
  sl <- list()
  for (i in settings) sl[[i]] <- Sys.getenv(i)
  if (nchar(sl[["JAVA_PROG"]]) == 0) {
    if (nchar(sl[["JAVA_HOME"]]) > 0) {
      jc <- paste(sl[["JAVA_HOME"]], "bin", "java", sep = .Platform$file.sep)
      if (file.exists(jc)) 
        sl[["JAVA_PROG"]] <- jc
    }
    else sl[["JAVA_PROG"]] <- "java"
  }
  sl[["H2O_JAR"]] <- system.file("java", "h2o.jar", package = "h2o")
  sl[["FLAT"]] <- system.file("java", "flatfile.txt", package = "h2o")
  sl[["MEM"]] <- memory
  
  for (i in names(sl)) rt <- gsub(paste("@", i, "@", sep = ""), sl[[i]], rt)
  if (is.null(target)) return(rt)
  writeLines(rt, target)
}