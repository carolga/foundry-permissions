import sys
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
import chat_agent


class AgentChatTests(unittest.TestCase):
    def test_lists_all_pages_and_rejects_a_repeated_cursor(self):
        pages = [
            {"data": [{"name": "first"}], "has_more": True, "last_id": "page one"},
            {"data": [{"name": "second"}], "has_more": False},
        ]
        with patch.object(chat_agent, "request_json", side_effect=pages) as request:
            names = chat_agent.list_agent_names("https://example.invalid", "token")
        self.assertEqual(names, ["first", "second"])
        self.assertIn("after=page+one", request.call_args_list[1].args[0])

        pages[1] = {"data": [], "has_more": True, "last_id": "page one"}
        with (
            patch.object(chat_agent, "request_json", side_effect=pages),
            self.assertRaisesRegex(RuntimeError, "pagination cursor"),
        ):
            chat_agent.list_agent_names("https://example.invalid", "token")

    def test_chat_uses_the_named_agent_and_returns_completed_text(self):
        responses = [
            {"id": "response-1", "status": "in_progress"},
            {
                "status": "completed",
                "output": [
                    {"type": "file_search_call"},
                    {"type": "message", "content": [{"type": "output_text", "text": "found"}]},
                ],
            },
        ]
        with (
            patch.object(chat_agent, "request_json", side_effect=responses) as request,
            patch.object(chat_agent.time, "sleep"),
        ):
            text = chat_agent.send_message(
                "https://example.invalid", "test-agent", "conversation-1", "hello", "token"
            )
        self.assertEqual(text, "found")
        body = request.call_args_list[0].args[2]
        self.assertEqual(body["agent_reference"]["name"], "test-agent")
        self.assertEqual(body["conversation"], "conversation-1")

    def test_failed_or_non_text_responses_are_not_reported_as_success(self):
        for response in [
            {"status": "failed", "error": {"message": "failed"}},
            {"status": "completed", "output": []},
        ]:
            with (
                self.subTest(response=response),
                patch.object(chat_agent, "request_json", return_value=response),
                self.assertRaises(RuntimeError),
            ):
                chat_agent.send_message("https://example.invalid", "agent", "conv", "hi", "token")

    def test_rejects_non_foundry_endpoint_before_sending_a_token(self):
        with self.assertRaises(ValueError):
            chat_agent.project_endpoint("https://example.invalid/api/projects/p")


if __name__ == "__main__":
    unittest.main()
