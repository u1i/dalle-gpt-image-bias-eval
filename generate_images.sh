#!/bin/bash

# Configuration
NUM_IMAGES=100  # Number of images to generate
RETRY_DELAY=60  # Delay in seconds before retrying after an error
OUTPUT_DIR="generated"  # Directory to store generated images

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install it with 'brew install jq'."
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Read prompt from prompt.txt
if [ ! -f "prompt.txt" ]; then
    echo "Error: prompt.txt file not found!"
    exit 1
fi

PROMPT=$(cat prompt.txt)
echo "Using prompt: $PROMPT"

# Function to generate an image
generate_image() {
    local attempt=$1
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local output_file="${OUTPUT_DIR}/image_${attempt}_${timestamp}.png"
    local response_file="${OUTPUT_DIR}/response_${attempt}_${timestamp}.json"
    
    echo "Generating image $attempt of $NUM_IMAGES..."
    
    # Make the API call and save the response
    response=$(curl --silent --location --request POST '$endpoint' \
    --header 'api-key: $apikey' \
    --header 'Content-Type: application/json' \
    --data "{
        \"prompt\": \"$PROMPT\",
        \"model\": \"gpt-image-1\",
        \"size\": \"1024x1024\", 
        \"n\": 1,
        \"quality\": \"high\"
    }")
    
    # Save the full JSON response for reference
    echo "$response" > "$response_file"
    
    # Check for rate limiting or other errors
    http_code=$(echo "$response" | jq -r '.error.code // empty')
    error_message=$(echo "$response" | jq -r '.error.message // empty')
    
    if [ ! -z "$http_code" ] || [ ! -z "$error_message" ]; then
        echo "Error detected: $http_code - $error_message"
        
        # Check for rate limiting (429)
        if [[ "$http_code" == "429" || "$error_message" == *"rate limit"* ]]; then
            echo "Rate limit reached. Waiting for $RETRY_DELAY seconds before retrying..."
            sleep $RETRY_DELAY
            return 1  # Return error to trigger retry
        else
            echo "Unknown error. Check $response_file for details."
            return 1  # Return error to trigger retry
        fi
    fi
    
    # Extract the base64 image data using jq
    b64_json=$(echo "$response" | jq -r '.data[0].b64_json')
    
    # Check if b64_json is null or empty
    if [ -z "$b64_json" ] || [ "$b64_json" == "null" ]; then
        echo "Error: Could not extract base64 image data. Check $response_file for details."
        return 1  # Return error to trigger retry
    fi
    
    # Decode the base64 data and save it as an image file
    echo "$b64_json" | base64 --decode > "$output_file"
    
    # Check if the image was saved successfully
    if [ -s "$output_file" ]; then
        # Get the file size
        filesize=$(du -h "$output_file" | cut -f1)
        echo "Success! Image $attempt saved to $output_file (Size: $filesize)"
        return 0  # Success
    else
        echo "Error: Failed to save image or image is empty."
        return 1  # Return error to trigger retry
    fi
}

# Main loop to generate images
successful_generations=0
total_attempts=0

echo "Starting generation of $NUM_IMAGES images..."
echo "Images will be saved to the '$OUTPUT_DIR' directory"

while [ $successful_generations -lt $NUM_IMAGES ]; do
    ((total_attempts++))
    
    # Generate image with retry logic
    max_retries=5
    retry_count=0
    success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$success" != "true" ]; do
        if generate_image $successful_generations; then
            success=true
            ((successful_generations++))
        else
            ((retry_count++))
            if [ $retry_count -ge $max_retries ]; then
                echo "Failed after $max_retries attempts. Moving to next image."
                break
            else
                echo "Retrying... (Attempt $retry_count of $max_retries)"
                sleep 5  # Brief pause between retries
            fi
        fi
    done
    
    # Add a small delay between successful generations to avoid overwhelming the API
    if [ "$success" == "true" ]; then
        sleep 2
    fi
    
    # Progress report
    echo "Progress: $successful_generations/$NUM_IMAGES complete (Total attempts: $total_attempts)"
done

echo "Generation complete! Successfully generated $successful_generations images out of $NUM_IMAGES requested."
echo "Total attempts: $total_attempts"
echo "All images and responses are saved in the '$OUTPUT_DIR' directory."
