import os
from flask import Flask, jsonify, send_from_directory

app = Flask(__name__)

# Path to the pictures directory
PICTURES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pictures')

@app.route('/pictures', methods=['GET'])
def list_pictures():
    """
    Provides a list of picture filenames in the pictures directory.
    """
    try:
        picture_files = [f for f in os.listdir(PICTURES_DIR) if os.path.isfile(os.path.join(PICTURES_DIR, f))]
        return jsonify(picture_files)
    except FileNotFoundError:
        return jsonify({"error": "Pictures directory not found. Please create a 'pictures' directory next to app.py."}), 404

@app.route('/pictures/<path:filename>')
def get_picture(filename):
    """
    Serves a specific picture from the pictures directory.
    """
    return send_from_directory(PICTURES_DIR, filename)

if __name__ == '__main__':
    # We run the server on 0.0.0.0 to make it accessible from other devices on the same network (like your phone).
    app.run(host='0.0.0.0', port=5000, debug=True)
