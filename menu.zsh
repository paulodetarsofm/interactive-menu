#!/bin/zsh

# Ensure jq and fzf are installed
if ! command -v jq &> /dev/null; then
  echo "jq is required but not installed. Install it and try again."
  return
fi

if ! command -v fzf &> /dev/null; then
  echo "fzf is required but not installed. Install it and try again."
  return
fi

# Function to get color codes based on color names
get_color_code() {
  case $1 in
    "black")   echo "30" ;;
    "red")     echo "31" ;;
    "green")   echo "32" ;;
    "yellow")  echo "33" ;;
    "blue")    echo "34" ;;
    "magenta") echo "35" ;;
    "cyan")    echo "36" ;;
    "white")   echo "37" ;;
    "default") echo "39" ;;
    *)         echo "39" ;;  # Default to no color
  esac
}

# Function to execute a sequence of commands
execute_commands() {
  local commands_to_execute=("$@")

  for command_to_execute in "${commands_to_execute[@]}"; do
    if [[ "$command_to_execute" == "exit" ]]; then
      return
    fi

    eval "$command_to_execute"

    if [[ $? -ne 0 ]]; then
      echo "Error executing command: $command_to_execute"
    fi
  done
}

# Function to change directory and run the commands
change_dir() {
  local dir="$1"
  shift
  local commands=("$@")

  # Change directory and run commands
  pushd "$dir" > /dev/null || { echo "Failed to change directory to $dir"; return 1; }
  execute_commands "${commands[@]}"
  popd > /dev/null
}

# Get the directory of the script
script_dir=$(dirname "$(realpath "$0")")
menu_json="$script_dir/menu.json"

# Determine the maximum width for the option column and add some extra space
max_option_width=$(jq -r '.menu_items[].option | length' "$menu_json" | sort -nr | head -n1)
max_option_width=$((max_option_width + 5))

# Determine the maximum width for the example column and add some extra space
max_example_width=$(jq -r '.menu_items[].example | length' "$menu_json" | sort -nr | head -n1)
max_example_width=$((max_example_width + 1))

# Extract menu items and color codes
menu_items=$(
  jq -r --argjson padding '
    {
      "option": 5,
      "example": 0
    }' '.menu_items[] |
    "\(.option)\t|\t\(.example)\t|\t\(.colors.option // "default")\t|\t\(.colors.example // "default")\t|\t\(.padding.option // 0)\t|\t\(.padding.example // 0)"
  ' "$menu_json"
)

# Apply colors and format the menu
formatted_menu=$(
  echo "$menu_items" | while
    IFS=$'\t|\t' read -r option example option_color example_color option_padding example_padding; do
      option_color_code=$(get_color_code "$option_color")
      example_color_code=$(get_color_code "$example_color")

      # Apply padding to the option column
      padded_option=$(printf "%-*s" $((max_option_width + option_padding)) "$option")

      # Handle empty example column and apply padding
      if [[ -z "$example" ]]; then
        padded_example=$(printf "%*s" $((max_example_width + example_padding)) "")
      else
        padded_example=$(printf "%-*s" $((max_example_width + example_padding)) "$example")
      fi

      # Print the formatted menu with colors applied and proper column alignment
      printf "\033[%sm%-*s \033[0m\033[%sm%s\033[0m\n" \
            "$option_color_code" \
            "$((max_option_width + option_padding))" \
            "$padded_option" \
            "$example_color_code" \
            "$padded_example"

  done
)

# Display the menu and get the user's choice
selected_option=$(echo "$formatted_menu" | fzf \
  --prompt "Select an option: " \
  --layout reverse \
  --border \
  --no-info \
  --ansi \
)

if [[ -n "$selected_option" ]]; then
  # Extract the option text by handling spaces correctly
  option_text=$(echo "$selected_option" | awk -v max_width="$max_option_width" '
    {
      # The option field should be padded to max_width, so extract accordingly
      option = substr($0, 1, max_width)

      # Remove leading and trailing spaces
      gsub(/^[ \t]+/, "", option)
      gsub(/[ \t]+$/, "", option)

      print option
    }'
  )

  # Get the commands associated with the selected option into an array
  commands_array=()

  while IFS= read -r cmd; do
    commands_array+=("$cmd")
  done < <(jq -r --arg option "$option_text" '.menu_items[] | select(.option == $option) | .commands[]' "$menu_json")

  # Determine if the command contains a directory change
  first_command="${commands_array[0]}"

  if [[ "$first_command" == cd* ]]; then
    dir=$(echo "$first_command" | awk '{print substr($0, 4)}')

    # Extract commands excluding the directory change
    remaining_commands=("${commands_array[@]:1}")

    change_dir "$dir" "${remaining_commands[@]}"
  else
    # No directory change needed
    execute_commands "${commands_array[@]}"
  fi
fi
