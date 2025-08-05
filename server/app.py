import os
import logging
from flask import Flask, jsonify, send_from_directory
from waitress import serve

# Configure basic logging to print to console
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

app = Flask(__name__)
app.url_map.strict_slashes = False

# --- Path Configuration ---
# We construct the path relative to this script's location to be more robust.
# __file__ is the path to the current script. os.path.dirname gives its directory.
# os.path.join with '..' goes up one level to the project root, then into 'pictures'.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Go up one level to the project root, then into 'pictures'. This creates a clean, absolute path.
PICTURES_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, '..', 'pictures'))

logging.info(f"Server starting up...")
logging.info(f"Calculated script directory: {SCRIPT_DIR}")
logging.info(f"Final pictures directory set to: {PICTURES_DIR}")

@app.route('/pictures', methods=['GET'])
def list_pictures():
    """
    Lists all the pictures in the pictures directory.
    """
    logging.info("Request received for /pictures list.")
    try:
        logging.info(f"Checking if directory exists: '{PICTURES_DIR}'")
        if not os.path.isdir(PICTURES_DIR):
            logging.error(f"Directory does not exist: {PICTURES_DIR}")
            return jsonify({"error": "Pictures directory not found on server."}), 500

        logging.info(f"Directory exists. Attempting to list files...")
        pictures = [f for f in os.listdir(PICTURES_DIR) if os.path.isfile(os.path.join(PICTURES_DIR, f))]
        logging.info(f"Successfully found {len(pictures)} files.")
        return jsonify(pictures)
    except Exception as e:
        logging.error(f"An unexpected error occurred in list_pictures: {e}", exc_info=True)
        return jsonify({"error": "An internal server error occurred."}), 500

@app.route('/pictures/<string:filename>')
def get_picture(filename):
    """
    Serves a specific picture from the pictures directory.
    """
    logging.info(f"Request received to serve file: '{filename}'")
    return send_from_directory(PICTURES_DIR, filename)

if __name__ == '__main__':
    logging.info("Starting waitress server on http://0.0.0.0:5000")
    serve(app, host='0.0.0.0', port=5000)
