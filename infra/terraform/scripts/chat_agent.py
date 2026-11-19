"""List and chat with Foundry agents from the private validation VM."""

import argparse
import json
import time
import urllib.parse
from pathlib import Path

from smoke_test import managed_identity_token, request_json


def project_endpoint(override=None):
    if override is None:
        config = Path(__file__).with_name("jumpbox-config.json")
        override = json.loads(config.read_text(encoding="utf-8"))["project_endpoint"]
    endpoint = override.rstrip("/")
    parsed = urllib.parse.urlparse(endpoint)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or not parsed.hostname.endswith(".services.ai.azure.com")
        or parsed.username is not None
        or parsed.password is not None
        or not parsed.path.startswith("/api/projects/")
        or not parsed.path[len("/api/projects/") :]
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("Expected a standard HTTPS Foundry project endpoint.")
    return endpoint


def list_agent_names(endpoint, token):
    names = []
    after = None
    seen = set()
    while True:
        query = {"api-version": "v1", "limit": 100}
        if after is not None:
            query["after"] = after
        page = request_json(
            f"{endpoint}/agents?{urllib.parse.urlencode(query)}", token=token
        )
        names.extend(agent["name"] for agent in page["data"])
        if not page["has_more"]:
            return names
        after = page["last_id"]
        if not after or after in seen:
            raise RuntimeError("Agent listing returned an invalid pagination cursor.")
        seen.add(after)


def send_message(endpoint, agent_name, conversation_id, message, token):
    base = f"{endpoint}/openai/v1"
    response = request_json(
        f"{base}/responses",
        "POST",
        {
            "agent_reference": {"type": "agent_reference", "name": agent_name},
            "conversation": conversation_id,
            "input": message,
            "max_output_tokens": 2048,
        },
        token,
    )
    deadline = time.monotonic() + 300
    while response["status"] in ("queued", "in_progress"):
        if time.monotonic() >= deadline:
            raise TimeoutError(f"Agent response did not complete: {response['id']}")
        time.sleep(3)
        response_id = urllib.parse.quote(response["id"], safe="")
        response = request_json(f"{base}/responses/{response_id}", token=token)
    if response["status"] != "completed":
        raise RuntimeError(
            f"Agent response ended with {response['status']}: {response.get('error')}"
        )
    text = "\n".join(
        item["text"]
        for output in response.get("output", [])
        if output.get("type") == "message"
        for item in output.get("content", [])
        if item.get("type") == "output_text"
    )
    if not text:
        raise RuntimeError("The completed agent response contained no output text.")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", help="Override the installed project endpoint.")
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--list", action="store_true", help="List project agent names.")
    choice.add_argument("--agent", help="Name of the agent to invoke.")
    parser.add_argument("--message", help="Send one message instead of opening a chat.")
    args = parser.parse_args()
    if args.list and args.message is not None:
        parser.error("--message requires --agent")
    if args.message is not None and not args.message.strip():
        parser.error("--message cannot be empty")

    endpoint = project_endpoint(args.endpoint)
    token = managed_identity_token()
    if args.list:
        names = list_agent_names(endpoint, token)
        print("\n".join(names) if names else "No agents found in this project.")
        return

    conversation = request_json(
        f"{endpoint}/openai/v1/conversations",
        "POST",
        {"metadata": {"purpose": "private-jumpbox-test"}},
        token,
    )
    if args.message is not None:
        print(send_message(endpoint, args.agent, conversation["id"], args.message, token))
        return

    print("Private agent chat. Enter /quit or Ctrl-D to exit.")
    while True:
        try:
            message = input("\nYou: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if message.lower() in ("/quit", "/exit"):
            return
        if message:
            token = managed_identity_token()
            print(f"Agent: {send_message(endpoint, args.agent, conversation['id'], message, token)}")


if __name__ == "__main__":
    main()
