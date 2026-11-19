import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "smoke_test", Path(__file__).parents[1] / "scripts" / "smoke_test.py"
)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class ProjectReadinessTests(unittest.TestCase):
    def test_retries_only_readiness_failures_before_success(self):
        failures = [
            smoke.ApiError("GET", "test", 403, "Role not propagated"),
            smoke.ApiError(
                "GET",
                "test",
                400,
                '{"code":"invalid_configuration","message":"Listing agents timed out"}',
            ),
            {},
        ]
        with (
            patch.object(smoke, "request_json", side_effect=failures) as request,
            patch.object(smoke.time, "sleep") as sleep,
            patch("builtins.print"),
        ):
            smoke.wait_for_project("https://example.invalid", "synthetic-token")
        self.assertEqual(request.call_count, 3)
        self.assertEqual(sleep.call_count, 2)

    def test_other_configuration_errors_fail_immediately(self):
        failure = smoke.ApiError("GET", "test", 400, "invalid_configuration: bad binding")
        with (
            patch.object(smoke, "request_json", side_effect=failure),
            patch.object(smoke.time, "sleep") as sleep,
            self.assertRaises(smoke.ApiError) as raised,
        ):
            smoke.wait_for_project("https://example.invalid", "synthetic-token")
        self.assertIs(raised.exception, failure)
        sleep.assert_not_called()

    def test_readiness_timeout_preserves_failure(self):
        failure = smoke.ApiError("GET", "test", 403, "Role not propagated")
        with (
            patch.object(smoke, "request_json", side_effect=failure),
            patch.object(smoke.time, "monotonic", side_effect=[0, 301]),
            patch.object(smoke.time, "sleep") as sleep,
            self.assertRaises(smoke.ApiError) as raised,
        ):
            smoke.wait_for_project("https://example.invalid", "synthetic-token")
        self.assertIs(raised.exception, failure)
        sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
