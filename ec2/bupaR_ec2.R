# Define Python environment path
venv_path <- Sys.getenv("VENV_DIR", unset = "/home/pgx3874/jupyter-env")

# Set CRAN mirror
options(repos = c(CRAN = "https://cloud.r-project.org"))

# Install base dependencies
install.packages(c("devtools", "remotes", "reticulate"))

# Install CRAN packages
cran_packages <- c(
  "daqapo",
  "heuristicsmineR",
  "petrinetR",
  "processanimateR",
  "processpredictR",
  "understandBPMN",
  "xesreadR"
)

install.packages(cran_packages)

# GitHub-only package
remotes::install_github("fmannhardt/psmineR")

# Configure reticulate to use your existing Python venv
library(reticulate)

use_virtualenv(venv_path, required = TRUE)

# Ensure pm4py is installed in the venv
virtualenv_install(venv_path, "pm4py", ignore_installed = TRUE)

# Test modules
cat("\n✅ Verifying package load:\n")
invisible(lapply(c(cran_packages, "psmineR"), require, character.only = TRUE))

cat("All R packages loaded\n")

if (py_module_available("pm4py")) {
  cat("Python module pm4py available in", venv_path, "\n")
} else {
  cat("pm4py not available in", venv_path, "\n")
}
