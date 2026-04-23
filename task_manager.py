import json
import os
import logging
from datetime import datetime

TASK_FILE = "user_tasks.json"

class TaskManager:
    def __init__(self, file_path=TASK_FILE):
        self.file_path = file_path
        self._load_tasks()

    def _load_tasks(self):
        if os.path.exists(self.file_path):
            try:
                with open(self.file_path, 'r') as f:
                    self.tasks = json.load(f)
            except json.JSONDecodeError:
                logging.error(f"Error decoding {self.file_path}. Starting with empty task list.")
                self.tasks = []
        else:
            self.tasks = []

    def _save_tasks(self):
        try:
            with open(self.file_path, 'w') as f:
                json.dump(self.tasks, f, indent=4)
        except Exception as e:
            logging.error(f"Error saving tasks: {e}")

    def add_task(self, description, due_date=None):
        task = {
            "id": len(self.tasks) + 1,
            "description": description,
            "due_date": due_date,
            "created_at": datetime.now().isoformat(),
            "completed": False
        }
        self.tasks.append(task)
        self._save_tasks()
        return task

    def get_pending_tasks(self):
        return [t for t in self.tasks if not t["completed"]]

    def get_all_tasks(self):
        return self.tasks

    def complete_task(self, task_id_or_description):
        # Try to find by ID first (if int)
        try:
            task_id = int(task_id_or_description)
            for task in self.tasks:
                if task["id"] == task_id:
                    task["completed"] = True
                    self._save_tasks()
                    return f"Task '{task['description']}' marked as completed."
        except ValueError:
            pass # Not an ID

        # Find by fuzzy description match
        for task in self.tasks:
            if task_id_or_description.lower() in task["description"].lower():
                 task["completed"] = True
                 self._save_tasks()
                 return f"Task '{task['description']}' marked as completed."
        
        return "Task not found."

    def delete_task(self, task_id):
        initial_count = len(self.tasks)
        self.tasks = [t for t in self.tasks if t["id"] != task_id]
        if len(self.tasks) < initial_count:
            self._save_tasks()
            return True
        return False
