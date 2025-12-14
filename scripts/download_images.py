#!/usr/bin/env python3

import os
import sys
import json
import shutil
import argparse
import socket
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
import hashlib

# --- CONFIGURATION ---
API_URL = "https://api.meshtastic.org/resource/deviceHardware"
IMAGE_BASE_URL = "https://flasher.meshtastic.org/img/devices/"
REQUEST_TIMEOUT = 15
MAX_WORKERS = 16
# --- END CONFIGURATION ---

print_lock = threading.Lock()

def locked_print(*args, **kwargs):
    with print_lock:
        print(*args, **kwargs)

def get_contents_json(filename):
    data = {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1}
    }
    if filename.lower().endswith('.svg'):
        data["properties"] = {"preserves-vector-representation": True}
    return data

def load_manifest(manifest_path, log_warning):
    if not os.path.exists(manifest_path):
        return {}
    try:
        with open(manifest_path, 'r') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        log_warning(f"Could not read or parse manifest at '{manifest_path}'. Starting fresh.")
        return {}

def save_manifest(data, manifest_path):
    with open(manifest_path, 'w') as f:
        json.dump(data, f, indent=2)

def download_image(url, local_path, log_warning):
    """
    Downloads an image from a URL to a local path, but only if the content is valid.
    Returns a tuple (success: bool, error_message: str|None).
    """
    try:
        with urllib.request.urlopen(url, timeout=REQUEST_TIMEOUT) as response:
            if response.status != 200:
                return (False, f"Server returned status {response.status} for {url}")
            
            content_type = response.headers.get('Content-Type', '').lower()
            if not content_type.startswith('image/'):
                return (False, f"Invalid content type '{content_type}' for image at {url}. Server may have returned an error page.")

            with open(local_path, 'wb') as out_file:
                shutil.copyfileobj(response, out_file)
            return (True, None)

    except (urllib.error.URLError, urllib.error.HTTPError, socket.timeout, IOError) as e:
        return (False, f"Failed to download image from {url}: {e}")

def process_image(image_filename, base_dir, local_manifest, verbose_print, log_warning, target_mode):
    image_url = f"{IMAGE_BASE_URL}{image_filename}"
    asset_name = os.path.splitext(image_filename)[0]

    if target_mode == "xcassets":
        asset_dir = os.path.join(base_dir, f"{asset_name}.imageset")
        local_image_path = os.path.join(asset_dir, image_filename)
    else:
        asset_dir = base_dir
        local_image_path = os.path.join(base_dir, image_filename)

    verbose_print(f"Processing Asset: {asset_name} ({image_filename})")

    try:
        request = urllib.request.Request(image_url, method='HEAD')
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as head_response:
            remote_etag = head_response.headers.get('ETag') or head_response.headers.get('Last-Modified')
    except (urllib.error.URLError, urllib.error.HTTPError, socket.timeout) as e:
        log_warning(f"Could not check remote file status for {asset_name}: {e}")
        return ("failed", image_filename, None)

    if not remote_etag:
        log_warning(f"Could not get ETag/Last-Modified for {asset_name}. Forcing update.")
        remote_etag = "force-update-" + str(os.urandom(8).hex())

    local_info = local_manifest.get('files', {}).get(image_filename)

    should_download = False
    status = ""
    if not local_info or not os.path.exists(local_image_path):
        verbose_print(f"  -> New asset '{asset_name}'. Downloading...")
        status = "new"
        should_download = True
    elif local_info.get("etag") != remote_etag:
        verbose_print(f"  -> ETag mismatch for '{asset_name}'. Updating...")
        status = "updated"
        should_download = True
    else:
        verbose_print(f"  -> Asset '{asset_name}' is up-to-date. Skipping.")
        return ("skipped", image_filename, remote_etag)

    if should_download:
        os.makedirs(asset_dir, exist_ok=True)
        success, error_message = download_image(image_url, local_image_path, log_warning)
        if success:
            if target_mode == "xcassets":
                contents_json_path = os.path.join(asset_dir, "Contents.json")
                with open(contents_json_path, 'w') as f:
                    json.dump(get_contents_json(image_filename), f, indent=2)
            return (status, image_filename, remote_etag)
        else:
            log_warning(f"Download failed for {asset_name}: {error_message}")
            if target_mode == "xcassets":
                if os.path.exists(asset_dir):
                    shutil.rmtree(asset_dir)
            else:
                if os.path.exists(local_image_path):
                    os.remove(local_image_path)
            return ("failed", image_filename, None)

    return ("skipped", image_filename, remote_etag)

def main():
    parser = argparse.ArgumentParser(description="Downloads and syncs image assets.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--output-dir",
        help="Path to a regular directory where images and the manifest will be stored."
    )
    group.add_argument(
        "--output-xcassets",
        help="Path to the .xcassets directory to populate (legacy behavior)."
    )
    parser.add_argument("--output-json", help="If the API data has changed, save the raw JSON to this filename.")
    parser.add_argument("--force", action="store_true", help="Force a full sync, ignoring the API content hash check.")
    parser.add_argument("--verbose", action="store_true", help="Enable detailed logging for debugging.")
    args = parser.parse_args()

    target_mode = "xcassets" if args.output_xcassets else "directory"
    base_dir = args.output_xcassets if target_mode == "xcassets" else args.output_dir

    def verbose_print(*p_args, **p_kwargs):
        if args.verbose:
            locked_print(*p_args, **p_kwargs)

    def log_warning(message):
        locked_print(f"warning: {message}")

    def log_error(message):
        locked_print(f"error: {message}", file=sys.stderr)

    manifest_file = os.path.join(base_dir, "image_manifest.json")
    verbose_print(f"--- Starting Image Asset Sync ---")
    verbose_print(f"Target Path: {base_dir} ({'xcassets' if target_mode == 'xcassets' else 'directory'} mode)")
    os.makedirs(base_dir, exist_ok=True)
    local_manifest = load_manifest(manifest_file, log_warning)
    new_manifest = {}

    verbose_print(f"Fetching device list from {API_URL}...")
    try:
        with urllib.request.urlopen(API_URL, timeout=REQUEST_TIMEOUT) as response:
            api_data_bytes = response.read()
            new_api_hash = hashlib.sha256(api_data_bytes).hexdigest()
            devices = json.loads(api_data_bytes.decode('utf-8'))
    except (urllib.error.URLError, urllib.error.HTTPError, socket.timeout) as e:
        log_error(f"Could not fetch API data from {API_URL}: {e}")
        sys.exit(0) # Fail silently, XCode may be building offline without a network
    except json.JSONDecodeError:
        log_error("Failed to parse JSON from API response. The server may be down or the response is corrupt.")
        sys.exit(1)

    if not args.force:
        previous_api_hash = local_manifest.get("api_hash")
        if previous_api_hash == new_api_hash:
            verbose_print("\nAPI data has not changed. Nothing to do. Use --force to override.")
            verbose_print("--- Sync Complete ---")
            sys.exit(0)
        else:
            verbose_print("API data has changed. Proceeding with sync.")
    else:
        verbose_print("Force flag detected. Skipping API hash check.")

    # --- SAVE JSON IF REQUESTED ---
    if args.output_json:
        verbose_print(f"Saving API JSON to '{args.output_json}'...")
        try:
            with open(args.output_json, 'w') as f:
                json.dump(devices, f, indent=2)
        except IOError as e:
            log_error(f"Failed to save output JSON to {args.output_json}: {e}")
    # ------------------------------

    verbose_print(f"Found {len(devices)} devices in API response.")
    required_image_filenames = set(
        image_filename for device in devices for image_filename in device.get("images", [])
    )
    stats = {"new": 0, "updated": 0, "skipped": 0, "failed": 0}
    verbose_print(f"\n--- Syncing {len(required_image_filenames)} unique assets using up to {MAX_WORKERS} threads ---")

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_image = {
            executor.submit(process_image, filename, base_dir, local_manifest, verbose_print, log_warning, target_mode): filename
            for filename in required_image_filenames
        }
        for future in as_completed(future_to_image):
            image_filename = future_to_image[future]
            try:
                status, _, remote_etag = future.result()
                stats[status] += 1
                if status != "failed":
                    if 'files' not in new_manifest:
                        new_manifest['files'] = {}
                    new_manifest['files'][image_filename] = {"etag": remote_etag}
                else:
                    # Keep old entry if download failed to avoid re-download loop next time if API didn't change,
                    # but usually, we want to retry on failure. Here we just don't add it to new manifest,
                    # or we could copy the old one. Let's copy old info if available to be safe.
                    old_file_info = local_manifest.get('files', {}).get(image_filename)
                    if old_file_info:
                        if 'files' not in new_manifest:
                            new_manifest['files'] = {}
                        new_manifest['files'][image_filename] = old_file_info
            except Exception as exc:
                log_warning(f"An unexpected exception occurred while processing {image_filename}: {exc}")
                stats["failed"] += 1

    verbose_print("\n--- Pruning old assets ---")
    pruned_count = 0
    for filename in list(local_manifest.get('files', {}).keys()):
        if filename not in required_image_filenames:
            asset_name = os.path.splitext(filename)[0]
            if target_mode == "xcassets":
                asset_dir = os.path.join(base_dir, f"{asset_name}.imageset")
                verbose_print(f"Pruning {asset_name}...")
                if os.path.exists(asset_dir):
                    shutil.rmtree(asset_dir)
            else:
                file_path = os.path.join(base_dir, filename)
                verbose_print(f"Pruning {filename}...")
                if os.path.exists(file_path):
                    os.remove(file_path)
            pruned_count += 1
    if pruned_count == 0:
        verbose_print("No assets to prune.")

    new_manifest['api_hash'] = new_api_hash
    verbose_print("\nSaving new manifest...")
    save_manifest(new_manifest, manifest_file)
    verbose_print("\n--- Sync Complete ---")
    verbose_print(f"New: {stats['new']}, Updated: {stats['updated']}, Skipped: {stats['skipped']}, Failed: {stats['failed']}, Pruned: {pruned_count}")
    verbose_print("--------------------")
    if stats["failed"] > 0:
        log_warning(f"{stats['failed']} image(s) failed to sync. Check the build log for details.")

if __name__ == "__main__":
    main()