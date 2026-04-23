import json
import os
import logging

MEMORY_FILE = "user_memory.json"

class MemoryManager:
    def __init__(self, file_path=MEMORY_FILE):
        self.file_path = file_path
        self._load_memory()

    def _load_memory(self):
        if os.path.exists(self.file_path):
            try:
                with open(self.file_path, 'r') as f:
                    self.data = json.load(f)
            except json.JSONDecodeError:
                logging.error(f"Error decoding {self.file_path}. Starting with empty memory.")
                self.data = {}
        else:
            self.data = {}

    def _save_memory(self):
        try:
            with open(self.file_path, 'w') as f:
                json.dump(self.data, f, indent=4)
        except Exception as e:
            logging.error(f"Error saving memory: {e}")

    def get_user_data(self, key, default=None):
        return self.data.get(key, default)

    def update_user_data(self, key, value):
        self.data[key] = value
        self._save_memory()

    def add_conversation_turn(self, role, text):
        if "history" not in self.data:
            self.data["history"] = []
        
        # Keep last 20 turns to avoid exploding context
        history = self.data["history"]
        history.append({"role": role, "text": text})
        if len(history) > 20:
            history.pop(0)
        
        self.data["history"] = history
        self._save_memory()
        

    def get_recent_history(self):
        return self.data.get("history", [])

    def get_preferences(self):
        return self.data.get("preferences", {})

    def set_preference(self, key, value):
        if "preferences" not in self.data:
            self.data["preferences"] = {}
        self.data["preferences"][key] = value
        self._save_memory()
