"""Run inside the deployment VNet using a VM system-assigned managed identity.

Uses only Python's standard library. Creates and retains synthetic test artifacts
for inspection; it does not delete agents, conversations, files, or vector stores.
"""

import argparse
import ipaddress
import json
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


class ApiError(RuntimeError):
    def __init__(self, method, url, status, details):
        super().__init__(f"{method} {url}: HTTP {status}: {details}")
        self.status = status
        self.details = details


def request_json(url, method="GET", body=None, token=None, content_type=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if isinstance(body, dict):
        body = json.dumps(body).encode()
        content_type = "application/json"
    if content_type:
        headers["Content-Type"] = content_type
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        details = error.read().decode()
        raise ApiError(method, url, error.code, details) from error


def wait_for_project(endpoint, token):
    deadline = time.monotonic() + 300
    while True:
        try:
            request_json(f"{endpoint}/agents?api-version=v1", token=token)
            return
        except ApiError as error:
            initializing = (
                error.status == 400
                and "invalid_configuration" in error.details
                and "Listing agents timed out" in error.details
            )
            if (error.status != 403 and not initializing) or time.monotonic() >= deadline:
                raise
            print(
                f"Waiting for project readiness; retrying read after: {error}",
                flush=True,
            )
            time.sleep(15)


def managed_identity_token():
    url = (
        "http://169.254.169.254/metadata/identity/oauth2/token?"
        + urllib.parse.urlencode(
            {"api-version": "2018-02-01", "resource": "https://ai.azure.com"}
        )
    )
    request = urllib.request.Request(url, headers={"Metadata": "true"})
    # Never send IMDS requests through a proxy or print the resulting token.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=30) as response:
        return json.load(response)["access_token"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--storage", required=True)
    parser.add_argument("--search", required=True)
    parser.add_argument("--cosmos", required=True)
    args = parser.parse_args()
    endpoint = args.endpoint.rstrip("/")
    account_host = urllib.parse.urlparse(endpoint).hostname
    hosts = [
        account_host,
        f"{args.storage}.blob.core.windows.net",
        f"{args.search}.search.windows.net",
        f"{args.cosmos}.documents.azure.com",
    ]
    evidence = {"dns": {}, "checks": {}}
    for host in hosts:
        addresses = sorted(
            {item[4][0] for item in socket.getaddrinfo(host, 443, socket.AF_INET)}
        )
        if not addresses or not all(ipaddress.ip_address(ip).is_private for ip in addresses):
            raise RuntimeError(f"Expected private IPv4 addresses for {host}: {addresses}")
        evidence["dns"][host] = addresses
    print(json.dumps({"private_dns": evidence["dns"]}), flush=True)

    token = managed_identity_token()
    wait_for_project(endpoint, token)

    base = f"{endpoint}/openai/v1"
    marker = "HOA-INTAKE-TF-READY-7391"
    boundary = f"foundry-{uuid.uuid4().hex}"
    content = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="purpose"\r\n\r\nassistants\r\n'
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="synthetic-hoa.txt"\r\n'
        "Content-Type: text/plain\r\n\r\n"
        f"The synthetic HOA deployment validation code is {marker}.\r\n"
        f"--{boundary}--\r\n"
    ).encode()
    uploaded = request_json(
        f"{base}/files",
        "POST",
        content,
        token,
        f"multipart/form-data; boundary={boundary}",
    )
    evidence["file_id"] = uploaded["id"]
    store = request_json(
        f"{base}/vector_stores",
        "POST",
        {"name": "synthetic-hoa-validation", "file_ids": [uploaded["id"]]},
        token,
    )
    evidence["vector_store_id"] = store["id"]
    deadline = time.monotonic() + 600
    while store["status"] != "completed":
        if store["status"] == "expired" or store.get("file_counts", {}).get("failed", 0):
            raise RuntimeError(f"Vector store indexing failed: {store}")
        if time.monotonic() >= deadline:
            raise TimeoutError(f"Vector store did not complete: {store}")
        time.sleep(10)
        store = request_json(f"{base}/vector_stores/{store['id']}", token=token)
    if store.get("file_counts", {}).get("completed", 0) != 1:
        raise RuntimeError(f"Expected one indexed file: {store}")
    evidence["checks"]["file_indexing"] = "passed"
    print(json.dumps({"file_id": uploaded["id"], "vector_store": store}), flush=True)

    name = f"terraform-smoke-{uuid.uuid4().hex[:8]}"
    agent = request_json(
        f"{endpoint}/agents?api-version=v1",
        "POST",
        {
            "name": name,
            "definition": {
                "kind": "prompt",
                "model": args.model,
                "instructions": (
                    "You are a synthetic infrastructure test agent, not a financial "
                    "or housing decision-maker. Always search the provided file "
                    "before answering. Return its validation code verbatim."
                ),
                "tools": [{"type": "file_search", "vector_store_ids": [store["id"]]}],
            },
        },
        token,
    )
    evidence["agent_name"] = agent["name"]
    conversation = request_json(
        f"{base}/conversations",
        "POST",
        {"metadata": {"purpose": "synthetic-terraform-validation"}},
        token,
    )
    evidence["conversation_id"] = conversation["id"]
    response = request_json(
        f"{base}/responses",
        "POST",
        {
            "agent_reference": {"type": "agent_reference", "name": name},
            "conversation": conversation["id"],
            "input": "Search the uploaded document and return the synthetic HOA validation code.",
            "max_output_tokens": 2048,
        },
        token,
    )
    deadline = time.monotonic() + 300
    while response["status"] in ("queued", "in_progress"):
        if time.monotonic() >= deadline:
            raise TimeoutError(f"Agent response did not complete: {response['id']}")
        time.sleep(5)
        response = request_json(f"{base}/responses/{response['id']}", token=token)
    output = response.get("output", [])
    text = "\n".join(
        item["text"]
        for message in output
        if message.get("type") == "message"
        for item in message.get("content", [])
        if item.get("type") == "output_text"
    )
    if response["status"] != "completed" or marker not in text:
        raise RuntimeError(f"Agent failed to return the indexed marker: {response}")
    if not any(item.get("type") == "file_search_call" for item in output):
        raise RuntimeError(f"Response did not contain a file_search_call: {response}")
    evidence["response_id"] = response["id"]
    evidence["response_status"] = response["status"]
    evidence["answer"] = text
    evidence["checks"]["agent_file_search_conversation"] = "passed"
    print(json.dumps(evidence, indent=2), flush=True)


if __name__ == "__main__":
    main()
