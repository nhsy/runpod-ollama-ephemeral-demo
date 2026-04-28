#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "requests"
# ]
# ///
"""
scripts/gpu_availability.py
Query RunPod GraphQL API for community GPU availability and pricing.

Usage:
    python scripts/gpu_availability.py [--min-vram 24] [--cloud community|secure|all]

Reads RUNPOD_API_KEY from environment or .env file in the project root.
"""

import argparse
import os
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import requests
except ImportError:
    print(
        "Error: requests library not installed. Run: pip install requests",
        file=sys.stderr,
    )
    sys.exit(1)


RUNPOD_GRAPHQL = "https://api.runpod.io/graphql"
REQUEST_TIMEOUT = 30
MAX_RETRIES = 3
RETRY_BACKOFF = 2  # seconds

# Region aliases → ISO country codes recognised by RunPod
LOCATION_REGIONS: dict[str, list[str]] = {
    "US": ["US"],
    "CA": ["CA"],
    "AU": ["AU"],
    "JP": ["JP"],
    "EU": ["CZ", "DE", "FR", "IS", "NL", "NO", "PL", "RO", "SE"],
}
# All individual country codes (for validation)
ALL_COUNTRY_CODES: set[str] = {
    "AU",
    "CA",
    "CZ",
    "DE",
    "FR",
    "IS",
    "JP",
    "NL",
    "NO",
    "PL",
    "RO",
    "SE",
    "US",
}

QUERY = """
query GpuTypes($countryCode: String) {
  gpuTypes {
    id
    displayName
    memoryInGb
    communityCloud
    secureCloud
    lowestPrice(input: { gpuCount: 1, countryCode: $countryCode }) {
      minimumBidPrice
      uninterruptablePrice
    }
  }
}
"""


def load_api_key() -> str:
    """Load RunPod API key from environment or .env file."""
    key = os.environ.get("RUNPOD_API_KEY", "")
    if key:
        return key

    env_file = Path(__file__).parent.parent / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line.startswith("RUNPOD_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
                if key:
                    return key

    print(
        "Error: RUNPOD_API_KEY not set.\n"
        "  1. Copy .env.template to .env: cp .env.template .env\n"
        "  2. Add your API key to .env\n"
        "  3. Or export it: export RUNPOD_API_KEY=rp_xxx",
        file=sys.stderr,
    )
    sys.exit(1)


def make_graphql_request(
    api_key: str,
    query: str,
    variables: Optional[dict] = None,
    max_retries: int = MAX_RETRIES,
) -> dict:
    """
    Make a GraphQL request with retry logic for transient failures.

    Args:
        api_key: RunPod API key
        query: GraphQL query string
        max_retries: Maximum number of retry attempts

    Returns:
        Parsed JSON response as dict

    Raises:
        SystemExit: On non-retryable errors or if retries exhausted
    """
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "runpod-ollama-ephemeral/1.0",
    }
    payload = {"query": query, "variables": variables or {}}

    for attempt in range(1, max_retries + 1):
        try:
            response = requests.post(
                f"{RUNPOD_GRAPHQL}?api_key={api_key}",
                json=payload,
                headers=headers,
                timeout=REQUEST_TIMEOUT,
            )

            # Handle HTTP errors
            if response.status_code >= 500:
                raise requests.exceptions.ConnectionError(
                    f"Server error ({response.status_code}) - retryable"
                )

            response.raise_for_status()

            body = response.json()

            # Handle GraphQL errors
            if "errors" in body:
                for err in body["errors"]:
                    print(
                        f"API error: {err.get('message', 'Unknown error')}",
                        file=sys.stderr,
                    )
                sys.exit(1)

            return body

        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
            if attempt < max_retries:
                wait_time = RETRY_BACKOFF * attempt
                print(
                    f"Request failed (attempt {attempt}/{max_retries}): {e}\n"
                    f"  Retrying in {wait_time}s...",
                    file=sys.stderr,
                )
                time.sleep(wait_time)
            else:
                print(
                    f"Error: API request failed after {max_retries} attempts.\n"
                    "  1. Check your internet connection\n"
                    "  2. Verify RUNPOD_API_KEY is correct\n"
                    "  3. Try again later",
                    file=sys.stderr,
                )
                sys.exit(1)

        except requests.exceptions.RequestException as e:
            print(
                f"Error: API request failed: {e}\n"
                "  Check your internet connection and API key.",
                file=sys.stderr,
            )
            sys.exit(1)

    # Should not reach here, but just in case
    sys.exit(1)


def fetch_gpu_types(
    api_key: str, country_codes: Optional[list[str]] = None
) -> list[dict]:
    """Fetch GPU types from RunPod API, optionally filtered to specific country codes.

    For multiple country codes (e.g. EU region), queries each country separately and
    merges results, keeping the lowest available price per GPU across all countries.
    GPUs with no pricing in any of the target countries are excluded.
    """
    if not country_codes:
        body = make_graphql_request(api_key, QUERY, variables={"countryCode": None})
        return body["data"]["gpuTypes"]

    # Query each country and merge
    merged: dict[str, dict] = {}
    for code in country_codes:
        body = make_graphql_request(api_key, QUERY, variables={"countryCode": code})
        for g in body["data"]["gpuTypes"]:
            gpu_id = g["id"]
            lp = g.get("lowestPrice") or {}
            spot = lp.get("minimumBidPrice")
            on_dem = lp.get("uninterruptablePrice")
            if spot is None and on_dem is None:
                # Not available in this country — skip
                if gpu_id not in merged:
                    continue
            elif gpu_id not in merged:
                merged[gpu_id] = g
            else:
                # Keep the lowest non-null price across countries
                existing_lp = merged[gpu_id].get("lowestPrice") or {}
                merged[gpu_id]["lowestPrice"] = {
                    "minimumBidPrice": _min_price(
                        existing_lp.get("minimumBidPrice"), spot
                    ),
                    "uninterruptablePrice": _min_price(
                        existing_lp.get("uninterruptablePrice"), on_dem
                    ),
                }

    return list(merged.values())


def _min_price(a: Optional[float], b: Optional[float]) -> Optional[float]:
    if a is None:
        return b
    if b is None:
        return a
    return min(a, b)


def format_price(price: Optional[float]) -> str:
    if price is None:
        return "  n/a  "
    return f"${price:.4f}"


def main() -> None:
    parser = argparse.ArgumentParser(description="RunPod GPU availability checker")
    parser.add_argument(
        "--min-vram",
        type=int,
        default=0,
        metavar="GB",
        help="Minimum VRAM in GB (default: 0 = show all)",
    )
    parser.add_argument(
        "--cloud",
        choices=["community", "secure", "all"],
        default="community",
        help="Filter by cloud type (default: community)",
    )
    parser.add_argument(
        "--sort",
        choices=["name", "vram", "price", "spot"],
        default="price",
        help="Sort by field (default: price)",
    )
    parser.add_argument(
        "--location",
        metavar="LOC",
        default=None,
        help=(
            "Filter by location: region alias (US, EU, CA, AU, JP) "
            "or individual country code (NL, DE, FR, …). Default: global."
        ),
    )
    args = parser.parse_args()

    # Resolve location → list of country codes
    country_codes: Optional[list[str]] = None
    if args.location:
        loc = args.location.upper()
        if loc in LOCATION_REGIONS:
            country_codes = LOCATION_REGIONS[loc]
        elif loc in ALL_COUNTRY_CODES:
            country_codes = [loc]
        else:
            print(
                f"Error: unknown location '{args.location}'.\n"
                f"  Regions: {', '.join(sorted(LOCATION_REGIONS))}\n"
                f"  Country codes: {', '.join(sorted(ALL_COUNTRY_CODES))}",
                file=sys.stderr,
            )
            sys.exit(1)

    api_key = load_api_key()
    gpu_types = fetch_gpu_types(api_key, country_codes=country_codes)

    # Filter
    results = []
    for g in gpu_types:
        vram = g.get("memoryInGb") or 0
        if vram < args.min_vram:
            continue
        if args.cloud == "community" and not g.get("communityCloud"):
            continue
        if args.cloud == "secure" and not g.get("secureCloud"):
            continue
        results.append(g)

    # Sort - use on-demand price
    def sort_key(g: dict):
        lp = g.get("lowestPrice") or {}
        if args.sort == "spot":
            return lp.get("minimumBidPrice") or 999
        if args.sort == "price":
            return lp.get("uninterruptablePrice") or 999
        if args.sort == "vram":
            return g.get("memoryInGb") or 0
        return g.get("displayName", "")

    results.sort(key=sort_key)

    if not results:
        print(
            f"No GPUs found matching filters (min-vram={args.min_vram}, cloud={args.cloud})"
        )
        return

    # Print table
    col_name = 56
    col_disp = 16
    col_vram = 8
    col_comm = 9
    col_sec = 9
    col_spot = 10
    col_od = 10

    header = (
        f"{'GPU ID (variables.tf)':<{col_name}} {'DISPLAY NAME':<{col_disp}}"
        f" {'VRAM':>{col_vram}} {'COMM':>{col_comm}}"
        f" {'SECURE':>{col_sec}} {'SPOT':>{col_spot}} {'ON-DEMAND':>{col_od}}"
    )
    print()
    print(header)
    print("-" * len(header))

    for g in results:
        lp = g.get("lowestPrice") or {}
        spot = lp.get("minimumBidPrice")
        on_dem = lp.get("uninterruptablePrice")
        comm = "yes" if g.get("communityCloud") else "-"
        sec = "yes" if g.get("secureCloud") else "-"

        print(
            f"{g['id']:<{col_name}}"
            f" {g.get('displayName', ''):<{col_disp}}"
            f" {str(g.get('memoryInGb', '?')) + ' GB':>{col_vram}}"
            f" {comm:>{col_comm}}"
            f" {sec:>{col_sec}}"
            f" {format_price(spot):>{col_spot}}"
            f" {format_price(on_dem):>{col_od}}"
        )

    print()
    loc_label = args.location.upper() if args.location else "global"
    print(
        f"  {len(results)} GPUs shown | cloud={args.cloud}"
        f" | min-vram={args.min_vram}GB | location={loc_label}"
        f" | sorted by {args.sort}"
    )
    print()


if __name__ == "__main__":
    main()
