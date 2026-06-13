# =============================================================================
# IMPORTS - Libraries we need for our function
# =============================================================================
import azure.functions as func
import logging
import json
import re
from datetime import datetime
import os
import uuid
from azure.cosmos import CosmosClient

# =============================================================================
# COSMOS DB CLIENT (OUTSIDE YOUR FUNCTIONS)
# =============================================================================
CONNECTION_STRING = os.getenv("DATABASE_CONNECTION_STRING")
DATABASE_NAME = os.getenv("COSMOS_DATABASE_NAME")
CONTAINER_NAME = os.getenv("COSMOS_CONTAINER_NAME")

cosmos_client = CosmosClient.from_connection_string(CONNECTION_STRING)
database = cosmos_client.get_database_client(DATABASE_NAME)
container = database.get_container_client(CONTAINER_NAME)

# =============================================================================
# CREATE THE FUNCTION APP
# =============================================================================
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# =============================================================================
# DEFINE THE TEXT ANALYZER FUNCTION
# =============================================================================
@app.route(route="TextAnalyzer")
def TextAnalyzer(req: func.HttpRequest) -> func.HttpResponse:

    logging.info('Text Analyzer API was called!')

    # STEP 1: GET TEXT
    text = req.params.get('text')
    if not text:
        try:
            req_body = req.get_json()
            text = req_body.get('text')
        except ValueError:
            pass

    # STEP 2: ANALYZE TEXT
    if text:
        words = text.split()
        word_count = len(words)
        char_count = len(text)
        char_count_no_spaces = len(text.replace(" ", ""))
        sentence_count = len(re.findall(r'[.!?]+', text)) or 1
        paragraph_count = len([p for p in text.split('\n\n') if p.strip()])
        reading_time_minutes = round(word_count / 200, 1)
        avg_word_length = round(char_count_no_spaces / word_count, 1) if word_count > 0 else 0
        longest_word = max(words, key=len) if words else ""

        analysis = {
            "wordCount": word_count,
            "characterCount": char_count,
            "characterCountNoSpaces": char_count_no_spaces,
            "sentenceCount": sentence_count,
            "paragraphCount": paragraph_count,
            "averageWordLength": avg_word_length,
            "longestWord": longest_word,
            "readingTimeMinutes": reading_time_minutes
        }

        # =============================================================================
        # STEP 13.3 — STORE RESULT IN COSMOS DB
        # =============================================================================

        # Generate unique ID
        doc_id = str(uuid.uuid4())

        # Build document
        document = {
            "id": doc_id,
            "analysis": analysis,
            "metadata": {
                "analyzedAt": datetime.utcnow().isoformat(),
                "textPreview": text[:100] + "..." if len(text) > 100 else text
            },
            "originalText": text
        }

        # Insert into Cosmos DB
        container.create_item(document)

        # Return analysis + ID
        return func.HttpResponse(
            json.dumps({
                "id": doc_id,
                "analysis": analysis,
                "metadata": document["metadata"]
            }, indent=2),
            mimetype="application/json",
            status_code=200
        )

    # STEP 4: HANDLE MISSING TEXT
    else:
        instructions = {
            "error": "No text provided",
            "howToUse": {
                "option1": "Add ?text=YourText to the URL",
                "option2": "Send a POST request with JSON body: {\"text\": \"Your text here\"}",
                "example": "https://your-function-url/api/TextAnalyzer?text=Hello world"
            }
        }

        return func.HttpResponse(
            json.dumps(instructions, indent=2),
            mimetype="application/json",
            status_code=400
        )

# =============================================================================
# STEP 14 — GET ANALYSIS HISTORY ENDPOINT
# =============================================================================
@app.route(route="GetAnalysisHistory")
def GetAnalysisHistory(req: func.HttpRequest) -> func.HttpResponse:
    try:
        # Read optional limit parameter
        limit_param = req.params.get("limit")
        limit = int(limit_param) if limit_param else None
        # Query all items in the container
        query = "SELECT * FROM c"
        items = list(container.query_items(
            query=query,
            enable_cross_partition_query=True
        ))

        # Apply limit if provided
        if limit is not None:
            items = items[:limit]

        # Return the full history
        return func.HttpResponse(
            json.dumps(items, indent=2),
            mimetype="application/json",
            status_code=200
        )

    except Exception as e:
        return func.HttpResponse(
            f"Error retrieving history: {str(e)}",
            status_code=500
        )
