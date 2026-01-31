#!/bin/bash

# Loop through all .ipynb files in the current directory
for file in *.ipynb; do
    # Remove the file extension and append .qmd
    base_name=$(basename "$file" .ipynb)
    output_file="${base_name}.qmd"
    
    # Convert the notebook to a Quarto .qmd file
    echo "Converting $file to $output_file..."
    quarto convert "$file" -o "$output_file"
done

echo "Conversion completed!"
