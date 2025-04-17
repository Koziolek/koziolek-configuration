# ChatGPT Bash Client
# Usage: chatgpt -p "Your prompt here" [-m model] [-t temperature] [-k max_tokens]

# Default values for optional parameters
DEFAULT_MODEL="gpt-4o"
DEFAULT_TEMPERATURE=0.7
DEFAULT_MAX_TOKENS=1000

# OpenAI API key
CHATGPT_API_KEY="$OPENAI_KEY"

# OpenAI API endpoint
CHATGPT_ENDPOINT="https://api.openai.com/v1/chat/completions"
CHATGPT_MODEL_ENDPOINT="https://api.openai.com/v1/models"

# Main function
function chatgpt() {
    local prompt model temperature max_tokens
    # Get list of models names
    function models() {
       response=$(curl -s -X GET "$CHATGPT_MODEL_ENDPOINT" -H "Authorization: Bearer $CHATGPT_API_KEY")
       readarray -t models < <(echo "$response" | jq -r '.data[].id')

       # Now 'models' is a bash array containing all the IDs
       echo "Available models:"
       for model in "${models[@]}"; do
         echo "  $model"
       done
    }

    # Execute query to given model
    function ask() {
        # Check if prompt is provided
        if [ -z "$prompt" ]; then
            echo "Error: Prompt is required."
            usage
            return 1
        fi

        # Set default values if not provided
        model=${model:-$DEFAULT_MODEL}
        temperature=${temperature:-$DEFAULT_TEMPERATURE}
        max_tokens=${max_tokens:-$DEFAULT_MAX_TOKENS}
        # Make API request
        response=$(curl -s -X POST "$CHATGPT_ENDPOINT" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $CHATGPT_API_KEY" \
            -d '{
                "model": "'"$model"'",
                "messages": [{"role": "user", "content": "'"$prompt"'"}],
                "max_tokens": '"$max_tokens"',
                "temperature": '"$temperature"'
            }')

        # Check for errors
        if [ $? -ne 0 ]; then
            echo "Error: Failed to connect to the OpenAI API."
            return 1
        fi

        # Parse and display the response
        echo "$response" | jq -r '.choices[0].message.content'
    }

    # Local precheck function to ensure the API key is set
    function precheck() {
        if [ -z "$CHATGPT_API_KEY" ]; then
            echo "Error: OPENAI_KEY is not set. Please set it before using this script."
            echo "You can export it using:"
            echo "  export OPENAI_KEY='your_api_key_here'"
            return 1
        fi
    }

    # Local usage function
    function usage() {
        echo "Usage: chatgpt -p \"Your prompt here\" [-m model] [-t temperature] [-k max_tokens] [-M] [-h]"
        echo
        echo "Options:"
        echo "  -p    Prompt (required)"
        echo "  -m    Model to use (default: $DEFAULT_MODEL)"
        echo "  -M    List available models"
        echo "  -t    Temperature (default: $DEFAULT_TEMPERATURE)"
        echo "  -k    Max tokens (default: $DEFAULT_MAX_TOKENS)"
        echo "  -h    Prints this help"
        echo
        models
        echo
    }

    # Parse arguments
    while getopts "p:m:t:k:Mh" opt; do
        case $opt in
            p) prompt="$OPTARG" ;;
            m) model="$OPTARG" ;;
            t) temperature="$OPTARG" ;;
            k) max_tokens="$OPTARG" ;;
            M) models; return 0 ;;
            h) usage; return 0 ;;
            *) usage; return 1 ;;
        esac
    done

    precheck || return 1
    ask
}

export -f chatgpt
