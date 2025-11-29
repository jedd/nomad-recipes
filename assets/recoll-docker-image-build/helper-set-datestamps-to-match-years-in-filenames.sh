#!/bin/bash
# Extract year from directory/filename and touch with Jan 1st of that year

# This works well in my repository since I have a structure like
#   /Books - IT/Books - Python/book title in long form (2016, author, publisher)/book title in long form (2016, author, publisher).pdf

# Later indexing in RECOLL will pick up the mtime of the file, so the date search feature becomes useful.

find /hub/pub/documentation/Books\ -\ IT/ -type f \( -name "*.pdf" -o -name "*.epub" -o -name "*.chm" \) -print0 | while IFS= read -r -d '' file; do
  # Extract year from filename (pattern: "....(YYYY,...")
  # Use head -1 to take only the first match
  year=$(echo "$file" | grep -oP '\(\K\d{4}(?=,)' | head -1)
  
  if [ ! -z "$year" ]; then
    echo "Setting $file to ${year}-01-01"
    touch -t "${year}01011200" "$file"
  fi
done

