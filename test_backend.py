import os
import unittest
from memory import MemoryManager
from task_manager import TaskManager

class TestBackend(unittest.TestCase):
    def setUp(self):
        # Use temporary files for testing
        self.memory_file = "test_memory.json"
        self.task_file = "test_tasks.json"
        
        # Clean up previous runs
        if os.path.exists(self.memory_file):
            os.remove(self.memory_file)
        if os.path.exists(self.task_file):
            os.remove(self.task_file)

    def tearDown(self):
        # Clean up after tests
        if os.path.exists(self.memory_file):
            os.remove(self.memory_file)
        if os.path.exists(self.task_file):
            os.remove(self.task_file)

    def test_memory_manager(self):
        mm = MemoryManager(self.memory_file)
        
        # Test preference
        mm.set_preference("name", "Varun")
        self.assertEqual(mm.get_preferences().get("name"), "Varun")
        
        # Test reloading
        mm2 = MemoryManager(self.memory_file)
        self.assertEqual(mm2.get_preferences().get("name"), "Varun")
        
        # Test history
        mm.add_conversation_turn("user", "Hello")
        history = mm.get_recent_history()
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["text"], "Hello")

    def test_task_manager(self):
        tm = TaskManager(self.task_file)
        
        # Test add task
        t1 = tm.add_task("Buy milk", "tomorrow")
        self.assertEqual(t1["description"], "Buy milk")
        self.assertEqual(len(tm.get_pending_tasks()), 1)
        
        # Test complete task by ID
        result = tm.complete_task(t1["id"])
        self.assertIn("marked as completed", result)
        self.assertEqual(len(tm.get_pending_tasks()), 0)
        
        # Test complete task by name
        tm.add_task("Walk the dog")
        result = tm.complete_task("walk")
        self.assertIn("marked as completed", result)

if __name__ == '__main__':
    unittest.main()
