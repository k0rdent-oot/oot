#!/usr/bin/env python3

import time
import sys
import os
from kubernetes import client, config
from kubernetes.dynamic import DynamicClient
from kubernetes.client.rest import ApiException


def wait_for_management_ready(management_resource, management_name, timeout=300):
    """
    Wait for a Kubernetes Management Custom Resource to reach Ready status.

    Polls the Management CR until its status conditions show type="Ready" and status="True".
    Handles cases where the CR doesn't exist yet by continuing to wait.

    Args:
        management_resource: Dynamic client resource for Management CRs
        management_name (str): Name of the Management CR to wait for
        timeout (int): Maximum time to wait in seconds (default: 300)

    Returns:
        The Management CR object if ready, None if timeout occurs

    Raises:
        ApiException: For API errors other than 404 (not found)
    """
    print(f"Waiting for Management CR '{management_name}' to be ready...")

    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            cr = management_resource.get(name=management_name)
            if cr.status and cr.status.get("conditions"):
                for condition in cr.status.conditions:
                    if condition.get("type") == "Ready" and condition.get("status") == "True":
                        print(f"Management CR '{management_name}' is ready!")
                        return cr

            print("Still waiting...")
            time.sleep(5)

        except ApiException as e:
            if e.status == 404:
                print(f"Management CR '{management_name}' doesn't exist yet, waiting...")
                time.sleep(5)
            else:
                raise e

    print(f"Timeout after {timeout} seconds waiting for Management CR")
    return None


def apply_management_patch_with_retry(management_resource, management_name, patch_data, max_retries=5):
    """
    Apply a patch to a Management Custom Resource with exponential backoff retry logic.

    Attempts to patch the Management CR using merge-patch strategy. On failure, retries
    with exponential backoff (2^attempt seconds) to handle transient errors like
    resource conflicts or temporary API unavailability.

    Args:
        management_resource: Dynamic client resource for Management CRs
        management_name (str): Name of the Management CR to patch
        patch_data (dict): JSON patch data to apply to the resource
        max_retries (int): Maximum number of retry attempts (default: 5)

    Returns:
        bool: True if patch was successful, False otherwise

    Raises:
        Exception: Re-raises the final exception if all retry attempts fail
    """
    print(f"Applying patch Management CR '{management_name}'...")

    for attempt in range(max_retries):
        try:
            print(f"Patch attempt {attempt + 1}/{max_retries}...")
            patched_cr = management_resource.patch(
                name=management_name,
                body=patch_data,
                content_type="application/merge-patch+json"
            )

            print(f"Successfully patched Management CR '{management_name}'")
            return True

        except Exception as e:
            if attempt == max_retries - 1:
                print(f"All patch attempts failed. Final error: {e}")
                raise e

            backoff_time = 2 ** attempt
            print(f"Patch failed: {e}\nRetrying in {backoff_time} seconds...")
            time.sleep(backoff_time)

    return False


def find_provider_index(providers, provider_name):
    """
    Find the index of a provider by name in the providers list.

    Searches through the providers list to locate a provider with the specified name.
    This is used to determine if a provider already exists and where it's located
    in the list for update operations.

    Args:
        providers (list): List of provider dictionaries from Management CR spec
        provider_name (str): Name of the provider to search for

    Returns:
        tuple: (index, exists) where:
            - index (int|None): The list index if found, None if not found
            - exists (bool): True if provider was found, False otherwise
    """
    for i, provider in enumerate(providers):
        if provider.get("name") == provider_name:
            return i, True
    return None, False


def add_new_provider(updated_providers, provider_name, template_value=None):
    """
    Add a new provider to the providers list with template values.

    Creates a new provider dictionary with the specified name and adds
    template field. The new provider is appended to the updated_providers
    list which will be used to patch the Management CR.

    Args:
        updated_providers (list): List of provider dictionaries to append the new provider to
        provider_name (str): Name for the new provider
        template_value (str, optional): Template value to add to the provider

    Returns:
        None: Modifies updated_providers list in-place
    """
    print(f"Provider '{provider_name}' not found, adding new provider")

    new_provider = {"name": provider_name}

    if template_value:
        new_provider["template"] = template_value
        print(f"Adding template to provider: {template_value}")

    updated_providers.append(new_provider)


def update_existing_provider(updated_providers, provider_index, provider_name, template_value=None):
    """
    Update an existing provider with new template values.

    Modifies an existing provider in the updated_providers list by adding or updating
    template field. This is used when a provider exists but lacks the required template values.

    Args:
        updated_providers (list): List of provider dictionaries containing the provider to update
        provider_index (int): Index of the provider to update in the list
        provider_name (str): Name of the provider (used for logging only)
        template_value (str, optional): Template value to add/update on the provider

    Returns:
        None: Modifies updated_providers list in-place
    """
    print(f"Found provider '{provider_name}' with no config, updating...")

    if template_value:
        updated_providers[provider_index]["template"] = template_value
        print(f"Adding template to provider: {template_value}")


def main():
    """
    Main function that orchestrates the Kubernetes Management CR provider patching process.

    This function performs the following operations:
    1. Reads configuration from environment variables
    2. Establishes Kubernetes API client connections
    3. Waits for the Management CR to be ready
    6. Updates or creates the specified provider in the Management CR
    7. Applies the patch to the Management CR

    Environment Variables:
        API_VERSION: Kubernetes API version for Management CRs (default: k0rdent.mirantis.com/v1beta1)
        MANAGEMENT_NAME: Name of the Management CR to patch (default: kcm)
        PROVIDER_NAME: Name of the provider to update/create (required)
        TEMPLATE_VALUE: Optional template value to add to the provider (required)

    Exit Codes:
        0: Success
        1: Error (missing required env vars, timeouts, API errors, etc.)
    """
    api_version = os.getenv('API_VERSION', 'k0rdent.mirantis.com/v1beta1')
    management_name = os.getenv('MANAGEMENT_NAME', 'kcm')
    provider_name = os.getenv('PROVIDER_NAME')
    template_value = os.getenv('TEMPLATE_VALUE')

    print("=== Kubernetes Management CR Provider Patcher ===")

    print(f"Provider: {provider_name}")
    print(f"Management CR: {management_name}")
    print(f"API Version: {api_version}")
    print(f"Template: {template_value}")

    try:
        try:
            config.load_incluster_config()
            print("Using in-cluster configuration")
        except:
            config.load_kube_config()
            print("Using local kubeconfig")

        k8s_client = client.ApiClient()
        dynamic_client = DynamicClient(k8s_client)
        v1 = client.CoreV1Api()

        management_resource = dynamic_client.resources.get(
            api_version=api_version,
            kind="Management"
        )

        cr = wait_for_management_ready(management_resource, management_name, timeout=300)
        if cr is None:
            print("ERROR: Timeout waiting for management CR to be ready")
            sys.exit(1)

        print(f"Starting patch operation for provider: {provider_name}")

        providers = cr.spec.get("providers", [])
        if not providers:
            print("ERROR: No providers found in spec.providers")
            sys.exit(1)

        provider_index, provider_exists = find_provider_index(providers, provider_name)

        updated_providers = [dict(provider) for provider in providers]
        if not provider_exists:
            add_new_provider(updated_providers, provider_name, template_value)
        else:
            update_existing_provider(updated_providers, provider_index, provider_name, template_value)

        apply_management_patch_with_retry(
            management_resource,
            management_name,
            {
                "spec": {
                    "providers": updated_providers
                }
            }
        )
        print(f"Provider '{provider_name}' now has the updated configuration")
        print("Job completed successfully!")

    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
