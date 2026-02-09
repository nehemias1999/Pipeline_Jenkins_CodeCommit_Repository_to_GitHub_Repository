import sys
import re

def extract_repo_name(url: str) -> str:
    """
    Extracts the repository name in 'organization/repository' format
    from a GitHub URL (HTTPS or SSH).
    """
    if not url:
        raise ValueError("Must provide a valid GitHub repository URL.")

    # Remove valid prefixes
    url = url.strip()
    url = re.sub(r'^https://github\.com/', '', url)
    url = re.sub(r'^git@github\.com:', '', url)

    # Remove .git suffix if it exists
    if url.endswith('.git'):
        url = url.removesuffix('.git')

    return url

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)

    url = sys.argv[1]
    try:
        repository_name = extract_repo_name(url)
        print(";" + repository_name)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
