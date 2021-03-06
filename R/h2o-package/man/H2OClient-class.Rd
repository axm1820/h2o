\name{H2OClient-class}
\Rdversion{1.1}
\docType{class}
\alias{H2OClient-class}
\alias{show,H2OClient-method}

\title{Class \code{"H2OClient"}}
\description{
An object representing the server/local machine on which H2O is running.
}
\section{Objects from the Class}{
Objects can be created by calls of the form \code{new("H2OClient", ...)}
%%  ~~ describe objects here ~~ 
}
\section{Slots}{
  \describe{
    \item{\code{ip}:}{Object of class \code{"character"} representing the IP address of the H2O server. }
    \item{\code{port}:}{Object of class \code{"numeric"} representing the port number of the H2O server. }
  }
}
\section{Methods}{
  \describe{
    \item{show}{\code{signature(object = "H2OClient")}: ... }
	 }
}
\references{
%%  ~~put references to the literature/web site here~~
}
\author{
%%  ~~who you are~~
}
\note{
%%  ~~further notes~~
}

%% ~Make other sections like Warning with \section{Warning }{....} ~

\seealso{
%%  ~~objects to See Also as \code{\link{~~fun~~}}, ~~~
%%  ~~or \code{\linkS4class{CLASSNAME}} for links to other classes ~~~
}
\examples{
showClass("H2OClient")
}
\keyword{classes}
