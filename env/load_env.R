# load_env.R - Load AWS environment variables for R

load_env <- function() {
  # Get the directory where this script is located
  script_dir <- dirname(rstudioapi::getActiveDocumentContext()$path)
  
  # If running outside RStudio, use current working directory
  if (identical(script_dir, "")) {
    script_dir <- getwd()
  }
  
  # Check for .env or .env.example
  env_file <- file.path(script_dir, ".env")
  env_example <- file.path(script_dir, ".env.example")
  
  if (file.exists(env_file)) {
    target_file <- env_file
    source_name <- ".env"
  } else if (file.exists(env_example)) {
    target_file <- env_example
    source_name <- ".env.example (using defaults)"
  } else {
    stop(paste("✗ Error: No .env or .env.example file found in", script_dir))
  }
  
  # Parse and load environment variables
  tryCatch({
    lines <- readLines(target_file)
    
    for (line in lines) {
      line <- trimws(line)
      
      # Skip empty lines and comments
      if (nchar(line) == 0 || startsWith(line, "#")) {
        next
      }
      
      # Parse KEY=VALUE
      if (grepl("=", line)) {
        parts <- strsplit(line, "=", fixed = TRUE)[[1]]
        if (length(parts) == 2) {
          key <- trimws(parts[1])
          value <- trimws(parts[2])
          Sys.setenv(key = value)
        }
      }
    }
    
    cat("✓ Loaded environment variables from", source_name, "\n")
    
    # Verify critical variables
    required_vars <- c('AWS_ACCOUNT_ID_PRIMARY', 'AWS_ACCOUNT_ID_LAMBDA')
    missing <- required_vars[sapply(required_vars, function(x) Sys.getenv(x) == "")]
    
    if (length(missing) > 0) {
      stop(paste("✗ Error: Missing required environment variables:", paste(missing, collapse = ", ")))
    }
    
    cat("✓ Environment loaded successfully\n")
    cat("  Primary Account:", Sys.getenv("AWS_ACCOUNT_ID_PRIMARY"), "\n")
    cat("  Lambda Account:", Sys.getenv("AWS_ACCOUNT_ID_LAMBDA"), "\n")
    cat("  Region (Primary):", Sys.getenv("AWS_REGION_PRIMARY"), "\n")
    cat("  Region (Lambda):", Sys.getenv("AWS_REGION_LAMBDA"), "\n")
    
  }, error = function(e) {
    stop(paste("✗ Error loading environment variables:", e$message))
  })
}

# Auto-run when script is sourced
if (!interactive()) {
  load_env()
}
