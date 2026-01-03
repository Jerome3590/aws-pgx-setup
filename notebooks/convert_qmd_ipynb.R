
library(quarto)

convert_qmd_folder_to_ipynb <- function(input_dir, output_dir = NULL) {
  # Set output directory to input directory if not specified
  if (is.null(output_dir)) output_dir <- input_dir
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  
  # List all .qmd files in the input directory
  qmd_files <- list.files(input_dir, pattern = "\\.qmd$", full.names = TRUE)
  
  if (length(qmd_files) == 0) {
    stop("No .qmd files found in the specified input directory.")
  }
  
  # Convert each .qmd file to .ipynb
  for (qmd_path in qmd_files) {
    output_name <- tools::file_path_sans_ext(basename(qmd_path))
    output_ipynb <- file.path(output_dir, paste0(output_name, ".ipynb"))
    message("Converting: ", qmd_path, " --> ", output_ipynb)
    quarto::quarto_convert(
      input = qmd_path,
      output = output_ipynb,
      to = "ipynb"
    )
    if (!file.exists(output_ipynb)) {
      warning("Conversion failed for: ", qmd_path)
    }
  }
  message("Batch conversion complete.")
}

# Example usage:
# convert_qmd_folder_to_ipynb("path/to/qmd_folder", output_dir = "path/to/output_folder")
